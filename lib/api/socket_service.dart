import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_config.dart';
import 'token_store.dart';

/// Realtime Socket.io connection for the astrologer. Connects to the host root
/// with the access token in `handshake.auth.token` (matches the backend, which
/// auto-marks the astrologer ONLINE on connect). Auto-reconnects and re-auths
/// with a fresh token. Mirrors the user app's SocketService.
class SocketService extends ChangeNotifier {
  final TokenStore _tokens;
  SocketService(this._tokens);

  io.Socket? _socket;
  bool _connected = false;
  bool get connected => _connected;

  /// Raw socket for self-contained features (e.g. the live broadcast room) that
  /// attach/detach their own listeners. Null before the socket connects.
  io.Socket? get raw => _socket;

  Timer? _heartbeatTimer;
  Timer? _graceTimer; // debounces brief drops so the UI doesn't flap to "Connecting…"

  // Socket host with the same fallback as the REST client: if the primary host
  // (api.devifai.in) keeps failing to connect — usually its public DNS is
  // briefly unresolvable — switch to the deterministic sslip.io fallback (which
  // never flaps) and rebuild the socket there. Without this, "go online" spins
  // on "Connecting…" forever while REST has already fallen back.
  String _socketHost = ApiConfig.socketUrl;
  int _connectErrors = 0;

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
  void connect() {
    final token = _tokens.accessToken;
    if (token == null || token.isEmpty) return;
    if (_socket != null) {
      _socket!.auth = {'token': token};
      if (!_socket!.connected) _socket!.connect();
      return;
    }

    _socket = io.io(
      _socketHost,
      io.OptionBuilder()
          // WEBSOCKET ONLY. On Android, socket_io_client's XHR-polling transport
          // is unreliable — the long-poll GET hangs and the engine fires a
          // `timeout` (the multi-minute "Connecting…" spinner with NO backend
          // hit). Websocket connects directly in one upgrade-free handshake and
          // is the stable transport on mobile. No polling means no polling↔ws
          // upgrade churn either. (Server allows both; we just pin the client.)
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({
            'token': token,
            if (ApiConfig.tenant.isNotEmpty) 'tenant': ApiConfig.tenant,
          })
          .enableReconnection()
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(3000)
          .build(),
    );

    final s = _socket!;
    s.onConnect((_) {
      _graceTimer?.cancel();
      _connected = true;
      _connectErrors = 0; // healthy again
      notifyListeners();
      _startHeartbeat();
      onConnected?.call();
    });
    // Don't flap the UI on a brief drop. socket.io auto-reconnects within ~1s;
    // only mark disconnected (which shows "Connecting…") if it stays down past a
    // short grace window. A quick reconnect cancels the timer → no flicker.
    s.onDisconnect((_) {
      _stopHeartbeat();
      _graceTimer?.cancel();
      _graceTimer = Timer(const Duration(milliseconds: 2500), () {
        _connected = false;
        notifyListeners();
      });
    });
    // Always send the freshest token on reconnect (it may have rotated).
    s.onReconnectAttempt((_) => s.auth = {'token': _tokens.accessToken ?? ''});
    s.onConnectError((_) {
      // After a few failed attempts on the primary host, assume its DNS is
      // unresolvable on this network and rebuild the socket on the sslip.io
      // fallback (once) — so "go online" doesn't spin forever while REST has
      // already fallen back. Surfaced via `connected` after the grace window.
      _connectErrors++;
      if (_connectErrors >= 3 &&
          ApiConfig.hasFallback &&
          _socketHost != ApiConfig.fallbackHost) {
        _socketHost = ApiConfig.fallbackHost;
        _connectErrors = 0;
        try { _socket?.dispose(); } catch (_) {}
        _socket = null;
        connect(); // rebuild on the fallback host
      }
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

  // ── Heartbeat — every 3s while connected. Keeps the backend presence row
  //    fresh (socketCount/online + a per-beat astrologer recompute) so the
  //    astrologer never silently drifts to "offline" for users while their app
  //    is open. Also the fast keep-alive the user requested.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeat(); // immediate beat on connect
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sendHeartbeat());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeat() {
    final s = _socket;
    if (s == null || !s.connected) return;
    s.emitWithAck('heartbeat', <String, dynamic>{}, ack: (_) {/* pong */});
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

  /// Disconnect + tear down (on logout).
  void disconnect() {
    _stopHeartbeat();
    _graceTimer?.cancel();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    notifyListeners();
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
