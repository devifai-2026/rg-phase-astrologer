import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/socket_service.dart';
import '../api/token_store.dart';
import 'host_resolver.dart';
import 'link_state.dart';

/// ONE app-wide lifecycle observer for the realtime link.
///
/// Previously three screens each registered their own observer and each called
/// `socket.connect()` on resume (so a resume with a call screen open fired three
/// connects), while NOTHING handled `paused`/`detached` — so the server only
/// learned the astrologer was gone when the ping timed out, and the client never
/// re-read tokens that a background isolate had rotated.
class AppLifecycleBinder with WidgetsBindingObserver {
  AppLifecycleBinder({
    required SocketService socket,
    required TokenStore tokens,
    required HostResolver resolver,
  })  : _socket = socket,
        _tokens = tokens,
        _resolver = resolver;

  final SocketService _socket;
  final TokenStore _tokens;
  final HostResolver _resolver;

  Timer? _backgroundTimer;

  /// While this returns true, backgrounding does NOT tear the socket down — a
  /// live consultation (or a ringing request) must survive the astrologer
  /// glancing at another app.
  ///
  /// A PREDICATE, not a bool, on purpose: the previous `bool holdOpen` was never
  /// assigned anywhere, so the socket was always dropped 20s after backgrounding
  /// — mid-consultation included. A manually-set flag would also leak `true` on
  /// any crash or mis-ordered teardown, which would keep the socket (and the
  /// astrologer's presence) alive forever. Deriving it from live session state
  /// self-corrects: when the session ends, hold-open evaporates on its own.
  bool Function()? shouldHoldOpen;

  bool get _holdOpen {
    try { return shouldHoldOpen?.call() ?? false; } catch (_) { return false; }
  }

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() {
    _backgroundTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundTimer?.cancel();
        _onResumed();
        break;
      case AppLifecycleState.paused:
        _onPaused();
        break;
      case AppLifecycleState.detached:
        _backgroundTimer?.cancel();
        _socket.stop(reason: 'terminating');
        break;
      // inactive/hidden fire for transient overlays (permission dialogs, the app
      // switcher preview). Acting on them causes flapping, so ignore them.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _onResumed() async {
    // A background isolate (the FCM presence-ping handler) may have rotated the
    // tokens while we slept. Re-read them BEFORE reconnecting, or we hand the
    // socket a stale access token and then try to refresh with a refresh token
    // that was already rotated away — which used to log the user out.
    try {
      if (await _tokens.diskRevisionChanged()) await _tokens.reloadFromDisk();
    } catch (_) {/* best-effort */}

    // nudge() resets the retry budget and exits fatal/backoff/stopped, so a
    // resume is always a fresh chance to connect.
    _socket.nudge();

    // If we drifted onto the sslip.io fallback, see whether the primary is back.
    // This is the recovery the old one-way switch never had.
    if (_resolver.isOnFallback) _resolver.probePrimary();
  }

  void _onPaused() {
    if (_holdOpen) return; // mid-consultation / ringing: keep the socket alive
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(LinkTimings.backgroundGrace, () {
      // Re-check at fire time, not just at schedule time: a request can start
      // ringing during the grace window, and dropping the socket then would kill
      // the very connection that carries `request-accepted`.
      if (_holdOpen) return;
      // Tell the server explicitly rather than letting the ping time out, so the
      // astrologer stops being advertised as reachable within ~1s instead of ~16s.
      // Presence while backgrounded is maintained by the FCM presence_ping path.
      _socket.stop(reason: 'background');
    });
  }
}
