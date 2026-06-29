import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'astro_deep_link.dart';

/// WhatsApp-style native incoming-call screen for consultation requests.
///
/// A high-priority FCM message (data: callType=='incoming') raises the system
/// call UI via [showIncoming] — works even when the app is fully killed or the
/// device is locked. The astrologer swipes:
///   • Accept  → CallKit fires ActionCallAccept → we stash the sessionId as the
///               "pending accept" and route into the app, which (on the next
///               bootstrap / while running) accepts the session and joins.
///   • Decline → ActionCallDecline → reject the session (best-effort REST).
///
/// A 'cancel' control push (or socket cancel/expire) calls [dismiss] so the call
/// screen tears down in sync with the server's 60s ring window.
///
/// Android-first. The same flutter_callkit_incoming API drives iOS CallKit later
/// (needs VoIP/PushKit wiring), so this surface stays unchanged.
class CallKitService {
  CallKitService._();

  /// Map a serviceType (chat/call/video) to a CallKit "video?" flag + label.
  static bool _isVideo(String type) => type == 'video';

  /// A stable per-session CallKit id. flutter_callkit_incoming keys calls by a
  /// UUID-like string; we reuse the sessionId so dismiss() can target it exactly.
  static String _callId(String sessionId) => sessionId;

  /// Raise the native incoming-call screen for a request payload.
  /// payload keys: sessionId, serviceType (chat/call/video), alias,
  /// ratePerMin, expiresInSec.
  static Future<void> showIncoming(Map<String, dynamic> payload) async {
    final sessionId = (payload['sessionId'] ?? '').toString();
    if (sessionId.isEmpty) return;
    final type = (payload['serviceType'] ?? payload['type2'] ?? payload['type'] ?? 'chat').toString();
    final alias = (payload['alias'] ?? 'Seeker').toString();
    final isVideo = _isVideo(type);
    final label = type == 'chat' ? 'Chat consultation' : (isVideo ? 'Video consultation' : 'Voice consultation');
    // Ring window: keep the native screen alive for the server's window (default
    // 60s) so it auto-dismisses if unanswered (server also marks it missed).
    final timeoutSec = int.tryParse((payload['expiresInSec'] ?? '60').toString()) ?? 60;

    final params = CallKitParams(
      id: _callId(sessionId),
      nameCaller: '$alias · $label',
      appName: 'Rudraganga',
      handle: 'Astrology consultation',
      type: isVideo ? 1 : 0, // 0 = audio, 1 = video native UI
      duration: timeoutSec * 1000, // auto-dismiss window (ms)
      textAccept: 'Accept',
      textDecline: 'Decline',
      // We carry the full payload so the accept handler (which may run in a
      // background isolate) has everything to recover the session.
      extra: <String, dynamic>{
        'sessionId': sessionId,
        'serviceType': type,
        'alias': alias,
      },
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed consultation',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0B0B0C',
        actionColor: '#E0584A',
        // Launch the Flutter activity (over the lock screen) on accept.
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(handleType: 'generic', supportsVideo: true),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Dismiss the call screen for a session (cancelled / expired / accepted
  /// elsewhere). Safe to call even if no call is showing.
  static Future<void> dismiss(String sessionId) async {
    if (sessionId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(_callId(sessionId));
    } catch (_) {/* nothing showing */}
  }

  /// Tear down any/all active call screens (e.g. on logout).
  static Future<void> dismissAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  /// The sessionId the astrologer accepted from the native screen while the app
  /// was not running, awaiting the app to finish bootstrap and act on it.
  static String? pendingAcceptSessionId;

  /// Wire the global CallKit event stream once (call from PushService.init).
  /// onAccept / onDecline let the app perform the accept/reject with its DI
  /// graph; when the app isn't ready yet we stash a pending accept instead.
  static void listen({
    required void Function(String sessionId, String serviceType) onAccept,
    required void Function(String sessionId) onDecline,
  }) {
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      final body = (event.body is Map) ? Map<String, dynamic>.from(event.body as Map) : <String, dynamic>{};
      final extra = (body['extra'] is Map) ? Map<String, dynamic>.from(body['extra'] as Map) : <String, dynamic>{};
      final sessionId = (extra['sessionId'] ?? body['id'] ?? '').toString();
      final serviceType = (extra['serviceType'] ?? 'chat').toString();
      if (sessionId.isEmpty) return;

      switch (event.event) {
        case Event.actionCallAccept:
          onAccept(sessionId, serviceType);
          break;
        case Event.actionCallDecline:
        case Event.actionCallTimeout:
          onDecline(sessionId);
          break;
        default:
          break;
      }
    });
  }

  /// Parse the CallKit `extra` JSON some platforms hand back as a string.
  static Map<String, dynamic> decodeExtra(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) return Map<String, dynamic>.from(m);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// Route into the app after an accept — opens the incoming/session screen via
  /// the deep-link navigator (handles the cold-start case via its _pending).
  static void routeIntoApp(String sessionId, String serviceType) {
    if (kDebugMode) debugPrint('[CallKit] accept → route session $sessionId ($serviceType)');
    AstroDeepLink.open('rudraganga://astro/incoming?sessionId=$sessionId&stype=$serviceType&accepted=1');
  }
}
