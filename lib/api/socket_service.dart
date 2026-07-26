import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../net/host_resolver.dart';
import '../net/link_state.dart';
import 'api_config.dart';
import 'auth_session.dart';
import 'token_store.dart';

/// Realtime Socket.io connection for the astrologer, driven by an EXPLICIT state
/// machine (see net/link_state.dart).
///
/// The old version tracked a single `_connected` bool and relied on socket.io's
/// internal reconnect loop, which produced the "Connecting… forever" bug in
/// several distinct ways:
///   - connect() returned SILENTLY when the access token was null/empty, with no
///     error, no retry and no state change (the reported case, after a reinstall
///     wiped the token while the refresh token survived);
///   - onConnectError neither set state nor notified listeners;
///   - the sslip.io fallback needed 3 socket-level connect_errors, was one-way
///     AND one-shot, and could be burned by a non-connectivity error (a bad
///     token), leaving no path back to the primary host;
///   - no attempt had a deadline, so a stalled handshake just hung.
///
/// Now: every transient state is bounded by a timer this class owns, and every
/// exit from backoff either retries or lands in `fatal`, which the UI renders as
/// an actionable error with a Retry button. An unbounded spinner is unreachable.
class SocketService extends ChangeNotifier {
  SocketService(this._tokens, {HostResolver? resolver, AuthSession? auth})
      : _resolver = resolver ?? HostResolver(),
        _auth = auth ?? AuthSession(_tokens) {
    _status = LinkStatus(state: LinkState.noAuth, activeHost: _resolver.activeHost);
    // A host change (fallback rotation, or recovery back to primary) must rebuild
    // the socket — it's pinned to a URL at construction time.
    _resolver.hostChanges.addListener(_onHostChanged);
  }

  final TokenStore _tokens;
  final HostResolver _resolver;
  final AuthSession _auth;

  HostResolver get resolver => _resolver;
  AuthSession get auth => _auth;

  io.Socket? _socket;

  LinkStatus _status = const LinkStatus(state: LinkState.noAuth, activeHost: '');
  LinkStatus get status => _status;

  /// Kept for backwards compatibility with existing call sites. Prefer
  /// `status.reachable`, which also excludes the half-open `degraded` case.
  bool get connected => _status.state == LinkState.connected;

  /// Raw socket for self-contained features (e.g. the live broadcast room) that
  /// attach/detach their own listeners. Null before the socket connects.
  io.Socket? get raw => _socket;

  Timer? _heartbeatTimer;
  Timer? _ackTimer;
  Timer? _graceTimer;    // debounces brief drops so the UI doesn't flap
  Timer? _attemptTimer;  // OUR connect deadline, shorter than socket.io's 20s
  Timer? _backoffTimer;

  int _attempt = 0;        // attempts on the current host
  int _totalAttempts = 0;  // attempts across all hosts since the last success
  int _beatSeq = 0;
  int? _pendingBeat;
  int _missedBeats = 0;
  bool _stopped = false;   // explicit stop (logout / background) suppresses retries

  // Server → client callbacks the rest of the app can hook.
  void Function(Map<String, dynamic>)? onIncomingRequest;
  void Function(Map<String, dynamic>)? onReceiveMessage;
  void Function(Map<String, dynamic>)? onNewNotification;
  void Function(Map<String, dynamic>)? onSessionEnded;
  /// The seeker cancelled their still-ringing request → dismiss the ring screen.
  void Function(Map<String, dynamic>)? onRequestCancelled;
  /// The ring timed out (no answer) → dismiss the ring screen.
  void Function(Map<String, dynamic>)? onRequestExpired;
  /// Both sides accepted → session is live (carries the Agora token for media).
  void Function(Map<String, dynamic>)? onRequestAccepted;
  /// Both joined the room → timer/billing start (carries the shared startedAt).
  void Function(Map<String, dynamic>)? onSessionStarted;
  /// A gift arrived during a live session.
  void Function(Map<String, dynamic>)? onGiftReceived;
  /// Wallet/earnings updated (astrologer is credited on session end).
  void Function(Map<String, dynamic>)? onWalletUpdated;
  void Function(Map<String, dynamic>)? onTyping;
  void Function(Map<String, dynamic>)? onStopTyping;
  /// Live presence for THIS astrologer (server is source of truth) — fired on
  /// any server-side presence recompute (toggle, auto-busy, disconnect, admin).
  void Function(Map<String, dynamic>)? onPresence;
  /// Fired when the socket (re)connects, so the app can re-sync presence from
  /// the backend after a reconnect blip.
  void Function()? onConnected;

  /// Connect (idempotent). Call once a session exists — after OTP verification
  /// / when the astrologer reaches the complete-profile screen, and on cold
  /// start if a token is already stored.
  /// The freshest handshake auth (token may have rotated since connect).
  Map<String, dynamic> _authPayload([String? token]) => {
        'token': token ?? _tokens.accessToken ?? '',
        if (ApiConfig.tenant.isNotEmpty) 'tenant': ApiConfig.tenant,
      };

  // ── State machine ─────────────────────────────────────────────────────────

  void _emitState(
    LinkState state, {
    LinkFatalReason? fatalReason,
    String? errorCode,
    DateTime? nextAttemptAt,
    bool clearNextAttempt = false,
    bool clearFatal = false,
  }) {
    _status = _status.copyWith(
      state: state,
      activeHost: _resolver.activeHost,
      attempt: _attempt,
      fatalReason: fatalReason,
      lastErrorCode: errorCode,
      nextAttemptAt: nextAttemptAt,
      clearNextAttempt: clearNextAttempt,
      clearFatal: clearFatal,
      connectedSince: state == LinkState.connected ? DateTime.now() : null,
    );
    notifyListeners();
  }

  /// Public entry point. Idempotent and safe to call repeatedly (cold start,
  /// login, every app resume, deep-link accept). Replaces the old `connect()`,
  /// which no-op'd on a missing token; this always ends in a definite state.
  void start() {
    _stopped = false;
    if (_status.state == LinkState.connected || _status.state == LinkState.connecting) return;
    _attempt = 0;
    _totalAttempts = 0;
    _authenticate();
  }

  /// Nudge an existing machine: resets budgets and retries immediately. Used on
  /// app resume, connectivity regained, and the UI's Retry button — the escape
  /// hatch out of `fatal`/`backoff` that the old code never had.
  void nudge() {
    _stopped = false;
    _backoffTimer?.cancel();
    if (_status.state == LinkState.connected) return;
    _attempt = 0;
    _totalAttempts = 0;
    _emitState(_status.state, clearFatal: true);
    _authenticate();
  }

  /// Legacy alias so existing call sites keep working.
  void connect() => start();

  Future<void> _authenticate() async {
    if (_stopped) return;
    // No refresh token at all → we cannot obtain a session. Terminal, and the UI
    // must show a sign-in prompt rather than a spinner.
    if (!_tokens.hasRefresh) {
      _emitState(LinkState.noAuth);
      return;
    }
    if (_tokens.accessUsable) return _openSocket();

    _emitState(LinkState.authenticating);
    bool ok;
    try {
      ok = await _auth
          .ensureFreshAccessToken()
          .timeout(LinkTimings.refreshTimeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    if (_stopped) return;
    if (ok) return _openSocket();
    // Distinguish "server says no" (dead session) from "network is flaky" (retry).
    if (_auth.lastRefreshWasRejected) {
      _emitState(LinkState.fatal, fatalReason: LinkFatalReason.authRejected, errorCode: 'auth');
      return;
    }
    _scheduleBackoff('refresh_failed');
  }

  void _openSocket() {
    if (_stopped) return;
    final token = _tokens.accessToken;
    // Should be unreachable (accessUsable was just checked) but never silently
    // no-op the way the old connect() did — go through the auth path instead.
    if (token == null || token.isEmpty) { _authenticate(); return; }

    if (_socket != null) {
      _socket!.auth = _authPayload(token);
      if (!_socket!.connected) {
        _emitState(LinkState.connecting);
        _armAttemptDeadline();
        _socket!.connect();
      }
      return;
    }

    _emitState(LinkState.connecting);

    _socket = io.io(
      _resolver.socketUrl,
      io.OptionBuilder()
          // WEBSOCKET ONLY. On Android, socket_io_client's XHR-polling transport
          // is unreliable — the long-poll GET hangs and the engine fires a
          // `timeout` (the multi-minute "Connecting…" spinner with NO backend
          // hit). Websocket connects directly in one upgrade-free handshake and
          // is the stable transport on mobile. No polling means no polling↔ws
          // upgrade churn either. (Server allows both; we just pin the client.)
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth(_authPayload(token))
          // We own the retry loop, so socket.io's own reconnection is DISABLED.
          // Leaving it on meant two competing retry loops, and its failures were
          // reported as manager-level `reconnect_error` which this class never
          // listened for — so the app could never tell that retrying was failing.
          .disableReconnection()
          .build(),
    );

    final s = _socket!;
    // socket_io_client caches the Manager+Socket per URL and a REUSED socket
    // ignores the opts auth above (auth is only read in the Socket constructor)
    // — after a logout→login that means the handshake would carry the PREVIOUS
    // user's token. Assign auth directly so the freshest identity always wins.
    s.auth = _authPayload(token);
    s.onConnect((_) {
      _attemptTimer?.cancel();
      _graceTimer?.cancel();
      _attempt = 0;
      _totalAttempts = 0;
      _missedBeats = 0;
      _pendingBeat = null;
      _status = _status.copyWith(socketId: s.id);
      _emitState(LinkState.connected, clearNextAttempt: true, clearFatal: true);
      _resolver.markHealthy();
      _startHeartbeat();
      onConnected?.call();
    });

    s.onDisconnect((_) {
      _stopHeartbeat();
      if (_stopped) { _emitState(LinkState.stopped); return; }
      // The grace window only debounces the UI badge; the machine starts
      // reconnecting immediately. Previously the grace was the ONLY thing that
      // set disconnected state, so a socket that died without re-emitting
      // `disconnect` could leave the UI claiming "connected".
      _graceTimer?.cancel();
      _graceTimer = Timer(LinkTimings.disconnectGrace, () {
        if (_status.state == LinkState.connected) _emitState(LinkState.connecting);
      });
      _scheduleBackoff('disconnected');
    });

    s.onConnectError((err) {
      _attemptTimer?.cancel();
      final code = _classify(err);
      // An auth-shaped rejection means the token is bad, not the network — force
      // a refresh instead of burning host-rotation budget on it (the old code
      // counted these toward the sslip.io switch, which could never help).
      if (code == 'auth') {
        _teardownSocket();
        _authenticate();
        return;
      }
      _scheduleBackoff(code);
    });

    s.on('incoming-request', (d) => onIncomingRequest?.call(_map(d)));
    s.on('receive-message', (d) => onReceiveMessage?.call(_map(d)));
    s.on('new-notification', (d) => onNewNotification?.call(_map(d)));
    s.on('session-ended', (d) => onSessionEnded?.call(_map(d)));
    s.on('my-presence', (d) => onPresence?.call(_map(d)));
    s.on('request-cancelled', (d) => onRequestCancelled?.call(_map(d)));
    s.on('request-expired', (d) => onRequestExpired?.call(_map(d)));
    s.on('request-accepted', (d) => onRequestAccepted?.call(_map(d)));
    s.on('session-started', (d) => onSessionStarted?.call(_map(d)));
    s.on('gift-received', (d) => onGiftReceived?.call(_map(d)));
    s.on('wallet-updated', (d) => onWalletUpdated?.call(_map(d)));
    s.on('typing', (d) => onTyping?.call(_map(d)));
    s.on('stop-typing', (d) => onStopTyping?.call(_map(d)));

    _armAttemptDeadline();
    s.connect();
  }

  /// Tell the backend the astrologer's online/offline choice.
  void setOnline(bool online) {
    if (_socket == null) return;
    _socket!.emit('set-online', {'online': online});
  }

  /// Start a break of [minutes] (shown busy to seekers) or end it ([minutes]<=0).
  /// The ack reports { ok, reason?, breakUntil? } — `reason: 'in_consultation'`
  /// means a break can't start while a session is live.
  void setBreak(int minutes, {void Function(Map<String, dynamic>)? ack}) {
    final s = _socket;
    if (s == null) { ack?.call({'ok': false}); return; }
    s.emitWithAck('set-break', {'minutes': minutes}, ack: (resp) => ack?.call(_map(resp)));
  }

  /// Our own connect deadline. socket.io's internal timeout is 20s, which is far
  /// too long to leave a user staring at a spinner, and with reconnection disabled
  /// nothing else would ever fire.
  void _armAttemptDeadline() {
    _attemptTimer?.cancel();
    _attemptTimer = Timer(LinkTimings.attemptTimeout, () {
      if (_status.state != LinkState.connecting) return;
      _teardownSocket();
      _scheduleBackoff('timeout');
    });
  }

  /// Normalize a connect error so the UI and telemetry can be specific, and so
  /// auth failures are distinguishable from network failures.
  String _classify(dynamic err) {
    final msg = err?.toString().toLowerCase() ?? '';
    if (msg.contains('auth') || msg.contains('unauthor') || msg.contains('invalid token')) return 'auth';
    if (msg.contains('timeout')) return 'timeout';
    if (msg.contains('refused')) return 'refused';
    if (msg.contains('host') || msg.contains('dns') || msg.contains('resolve')) return 'dns';
    return 'network';
  }

  void _teardownSocket() {
    _stopHeartbeat();
    _attemptTimer?.cancel();
    _graceTimer?.cancel();
    final s = _socket;
    _socket = null;
    if (s != null) {
      try { s.clearListeners(); } catch (_) {}
      try { s.dispose(); } catch (_) {}
    }
  }

  /// Exponential backoff with full jitter, rotating hosts at the per-host budget
  /// and landing in `fatal` once the total budget is spent. Every failure path
  /// funnels through here, which is what bounds the machine.
  void _scheduleBackoff(String errorCode) {
    if (_stopped) return;
    _backoffTimer?.cancel();
    _attempt++;
    _totalAttempts++;

    if (_totalAttempts >= LinkTimings.totalBudget) {
      _teardownSocket();
      _emitState(LinkState.fatal,
          fatalReason: LinkFatalReason.allHostsExhausted, errorCode: errorCode);
      return;
    }

    // Per-host budget spent → try the other candidate (and tell the backend, so
    // the PO console can graph impacted users).
    if (_attempt >= LinkTimings.hostBudget && _resolver.hasAlternate) {
      _resolver.rotate(reason: errorCode).then((rotated) {
        if (rotated) _attempt = 0;
      });
    }

    final expMs = LinkTimings.backoffBase.inMilliseconds * math.pow(2, math.min(_attempt, 6));
    final cappedMs = math.min(expMs.toDouble(), LinkTimings.backoffMax.inMilliseconds.toDouble());
    // Full jitter: without it, every astrologer on the platform retries in the
    // same instant after an outage and the herd looks like a second outage.
    final jitter = 1 + ((_rng.nextDouble() * 2 - 1) * LinkTimings.backoffJitter);
    final delay = Duration(milliseconds: (cappedMs * jitter).round().clamp(200, 30000));

    _emitState(LinkState.backoff,
        errorCode: errorCode, nextAttemptAt: DateTime.now().add(delay));
    _backoffTimer = Timer(delay, () {
      if (_stopped) return;
      _teardownSocket();
      _authenticate(); // re-checks the token, so a rotation is picked up
    });
  }

  final _rng = math.Random();

  /// Rebuild on the new host when the resolver switches (rotation, or recovery
  /// back to primary). A socket.io Socket is pinned to its URL at construction.
  void _onHostChanged() {
    if (_stopped) return;
    if (_socket == null) return;
    _teardownSocket();
    _authenticate();
  }

  // ── Heartbeat ───────────────────────────────────────────────────────────────
  // This beat does NOT prove the socket is alive — engine.io's pong does that,
  // and the server refreshes its Redis presence lease from it. This carries only
  // activity counters, so the old 3s cadence was ~20 wasted round-trips/min that
  // each triggered a full presence recompute server-side.
  //
  // It DOES double as the half-open detector: a socket.io socket can report
  // `connected` while the TCP connection is a zombie (mobile NAT timeout), and
  // only a missing ack reveals it.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _missedBeats = 0;
    _pendingBeat = null;
    _sendHeartbeat(); // beat immediately on connect
    _heartbeatTimer = Timer.periodic(LinkTimings.heartbeatInterval, (_) => _sendHeartbeat());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    _pendingBeat = null;
  }

  void _sendHeartbeat() {
    // ONE in-flight beat, ever. socket.io retains an entry in its internal `acks`
    // map for every emitWithAck until the server replies, so on a half-open
    // socket the old code leaked a closure every 3s, unbounded.
    if (_pendingBeat != null) { _onBeatMissed(); return; }
    final s = _socket;
    if (s == null || !s.connected) return;
    final id = ++_beatSeq;
    _pendingBeat = id;
    s.emitWithAck('heartbeat', <String, dynamic>{}, ack: (_) {
      if (_pendingBeat != id) return; // stale ack
      _pendingBeat = null;
      _ackTimer?.cancel();
      _missedBeats = 0;
      _status = _status.copyWith(lastAckAt: DateTime.now());
      if (_status.state == LinkState.degraded) _emitState(LinkState.connected);
    });
    _ackTimer?.cancel();
    _ackTimer = Timer(LinkTimings.heartbeatAckTimeout, () {
      _pendingBeat = null; // reclaim our slot regardless of the server
      _onBeatMissed();
    });
  }

  void _onBeatMissed() {
    _missedBeats++;
    if (_missedBeats == 2 && _status.state == LinkState.connected) {
      _emitState(LinkState.degraded, errorCode: 'heartbeat_missed');
    }
    if (_missedBeats >= 3) {
      // A half-open socket never self-heals — force a rebuild.
      _teardownSocket();
      _scheduleBackoff('heartbeat_dead');
    }
  }

  void emit(String event, [dynamic data]) => _socket?.emit(event, data);

  // ── Consultation session emits (astrologer side) ──
  void acceptSession(String sessionId) => _socket?.emit('accept-session', {'sessionId': sessionId});
  void rejectSession(String sessionId) => _socket?.emit('reject-session', {'sessionId': sessionId});
  void joinSession(String sessionId) => _socket?.emit('join-session', {'sessionId': sessionId});
  void endSession(String sessionId) => _socket?.emit('end-session', {'sessionId': sessionId});
  void sendMessage(String sessionId, {String? message, String? mediaUrl, String? mediaType, String? productId}) {
    _socket?.emit('send-message', {
      'sessionId': sessionId,
      if (message != null) 'message': message,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (productId != null) 'productId': productId, // astrologer shares a product card
    });
  }
  void markRead(String sessionId, String to) => _socket?.emit('mark-read', {'sessionId': sessionId, 'to': to});

  /// Deliberately stop the link: logout, or backgrounded past the grace window.
  /// Suppresses all retries until [start]/[nudge].
  ///
  /// Logout MUST call this. It previously didn't, so the socket stayed connected
  /// with a revoked token, heartbeating every 3s and holding the previous
  /// astrologer's presence open server-side.
  void stop({String reason = 'stopped'}) {
    _stopped = true;
    _backoffTimer?.cancel();
    // Tell the server we're going away so it drops the presence lease at once,
    // instead of waiting out the ping timeout.
    try { _socket?.emit('going-away', {'reason': reason}); } catch (_) {}
    _teardownSocket();
    _emitState(LinkState.stopped, clearNextAttempt: true);
  }

  /// Legacy alias (logout path).
  void disconnect() => stop(reason: 'logout');

  /// Report no network so we stop burning retries and show the right message.
  void setNetworkUnavailable(bool offline) {
    if (offline) {
      if (_status.state == LinkState.offlineNoNetwork) return;
      _backoffTimer?.cancel();
      _teardownSocket();
      _emitState(LinkState.offlineNoNetwork, errorCode: 'no_network', clearNextAttempt: true);
    } else if (_status.state == LinkState.offlineNoNetwork) {
      nudge();
    }
  }

  @override
  void dispose() {
    _resolver.hostChanges.removeListener(_onHostChanged);
    _backoffTimer?.cancel();
    _teardownSocket();
    super.dispose();
  }

  /// Normalize a socket payload to a Map. socket_io_client sometimes delivers
  /// the handler args as a List (e.g. [data, ackId]) instead of the data object
  /// directly — so unwrap the first element before checking for a Map.
  Map<String, dynamic> _map(dynamic d) {
    var v = d;
    if (v is List) v = v.isNotEmpty ? v.first : null;
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }
}
