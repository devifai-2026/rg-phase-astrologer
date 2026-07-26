import 'package:flutter/material.dart';

import '../../providers/session_provider.dart';
import '../../services/astro_deep_link.dart';
import 'incoming_call_screen.dart';

/// Presents the full-screen, call-style incoming-request UI. Works from a live
/// socket event (app in foreground) and is also the destination a full-screen
/// FCM notification taps into when the app is backgrounded/killed.
///
/// Uses [AstroDeepLink.navigatorKey] so it can push from outside the widget
/// tree (e.g. a notification tap handled in the headless isolate / on resume).
class IncomingRing {
  static bool _showing = false;
  // Which session the visible ring belongs to, so dismiss() can't pop another.
  static String? _showingSessionId;

  static ServiceKind _kind(String? type) => switch (type) {
        'call' => ServiceKind.call,
        'video' => ServiceKind.video,
        _ => ServiceKind.chat,
      };

  /// Populate the incoming state from a payload and ring full-screen.
  /// Payload shape: { sessionId, type, from:{alias} | alias, ratePerMin, expiresInSec }.
  static void present(SessionProvider session, Map<String, dynamic> d) {
    final sessionId = (d['sessionId'] ?? '').toString();
    if (sessionId.isEmpty) return;
    final type = d['type']?.toString();
    final alias = (d['from'] is Map ? d['from']['alias'] : d['alias'])?.toString() ?? 'Seeker';
    final rate = (d['ratePerMin'] as num?)?.toInt() ?? 0;
    final expires = (d['expiresInSec'] as num?)?.toInt() ?? 60;

    session.setIncoming(
      sessionId: sessionId,
      kind: _kind(type),
      alias: alias,
      ratePerMin: rate,
      expiresInSec: expires,
    );

    final nav = AstroDeepLink.navigatorKey.currentState;
    if (nav == null || _showing) return;
    _showing = true;
    _showingSessionId = sessionId;
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => IncomingCallScreen(kind: _kind(type)),
    )).whenComplete(() {
      // The route is the single source of truth for the latch: whatever removes
      // it (our pop, a system back, an accept's pushReplacement) clears here.
      _showing = false;
      _showingSessionId = null;
    });
  }

  /// Dismiss the ring screen (declined / cancelled / expired).
  ///
  /// Pass the sessionId whenever it is known: a bare pop can otherwise remove
  /// whatever happens to be on top — a DIFFERENT session's ring, or an unrelated
  /// route pushed above it. Mismatched ids are ignored.
  static void dismiss([String? sessionId]) {
    if (!_showing) return;
    if (sessionId != null && _showingSessionId != null && sessionId != _showingSessionId) return;
    final nav = AstroDeepLink.navigatorKey.currentState;
    if (nav == null) return;
    // Do NOT clear the latch here. maybePop() can be refused (a PopScope guard),
    // and clearing it anyway desynced the state so the next present() pushed a
    // duplicate ring. The route's whenComplete above is what clears it.
    nav.maybePop();
  }
}
