import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/astrologer_api.dart';
import '../api/session_api.dart';
import 'astro_deep_link.dart';
import 'callkit_service.dart';
import 'delivery_ack.dart';
import 'device_info.dart';
import 'local_notifs.dart';
import 'presence_ack.dart';

/// Background/terminated-state handler. Must be a top-level function (FCM spawns
/// a separate isolate that can't reach the app's DI graph). Broadcasts are sent
/// DATA-ONLY (no `notification` block) so Android wakes this isolate on every
/// receipt — which lets us (1) ACK true device delivery to the backend and
/// (2) draw the tray notification ourselves (the OS no longer draws it for
/// data-only messages). Keep work light. Mirrors the user app.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  final data = message.data;

  // Silent reachability probe: the backend pinged us to check the device still
  // has internet. ACK it (proves connectivity → stays online) and stop — no
  // notification, no CallKit. Reaching this handler AT ALL means FCM got through,
  // and the ACK confirms our uplink works too.
  if ((data['type'] ?? '').toString() == 'presence_ping') {
    await PresenceAck.send();
    return;
  }

  // Confirm receipt for delivery analytics (best-effort; reads token from
  // secure storage which is shared with this isolate).
  await DeliveryAck.send(data['broadcastId']?.toString());

  // An incoming consultation request → raise the WhatsApp-style NATIVE call
  // screen (works fully-killed / over the lock screen). callType=='incoming' is
  // the trigger; 'cancel' tears the screen down when the ring is withdrawn.
  final callType = (data['callType'] ?? '').toString();
  if (callType == 'incoming') {
    await CallKitService.showIncoming(data);
    return;
  }
  if (callType == 'cancel') {
    await CallKitService.dismiss((data['sessionId'] ?? '').toString());
    return;
  }

  // Draw the notification ourselves since data-only messages have no OS banner.
  final title = (message.notification?.title ?? data['title'] ?? 'Rudraganga').toString();
  final body = (message.notification?.body ?? data['body'] ?? '').toString();
  if (title.isNotEmpty || body.isNotEmpty) {
    await LocalNotifs.show(title, body, payload: PushService._payloadUri(data));
  }
}

/// Owns Firebase Cloud Messaging for the astrologer app: permission, registering
/// the device token with the backend, token refresh, turning foreground pushes
/// into visible local notifications, and ACK-ing device delivery so the admin
/// "Delivered" analytics reflect reality.
///
/// Kept as a singleton (created in main before the API exists). Call [attach]
/// once the authenticated [AstrologerApi] is available, then:
///   • [init]                once at startup (registers the FG/BG listeners)
///   • [registerWithBackend] on login/bootstrap (so broadcasts reach this device)
///   • [unregisterFromBackend] on logout (drops the token server-side)
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _fcm = FirebaseMessaging.instance;
  AstrologerApi? _api;
  SessionApi? _sessionApi; // for REST reject from the native call screen
  String? _lastToken;
  bool _listenersReady = false;

  String get platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Wire the authenticated APIs used for token registration, click attribution,
  /// and rejecting a session from the native call screen. Safe before/after init.
  void attach(AstrologerApi api, {SessionApi? sessionApi}) {
    _api = api;
    if (sessionApi != null) _sessionApi = sessionApi;
  }

  /// Register FG/BG/tap listeners. Safe to call once at startup, before login.
  Future<void> init() async {
    if (_listenersReady) return;
    _listenersReady = true;

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // Native call-screen actions (accept/decline). Accept routes into the app to
    // join the session; decline rejects it (best-effort REST so it works even
    // when the socket isn't connected yet, e.g. just after a cold launch).
    CallKitService.listen(
      onAccept: (sessionId, serviceType) {
        // CRITICAL: hit the backend ACCEPT immediately from the event handler —
        // do NOT wait for the app to route + bootstrap. This records the accept
        // server-side (which unblocks the seeker and starts the session)
        // regardless of cold-start timing, so a killed/locked-phone accept can't
        // strand both sides. The REST accept is idempotent server-side.
        _sessionApi?.accept(sessionId).catchError((_) => null);
        // Stash so the bootstrap (resumePendingAccept) + the route both finish
        // the accept / land on the session screen once the UI is ready.
        CallKitService.pendingAcceptSessionId = sessionId;
        CallKitService.pendingAcceptServiceType = serviceType;
        CallKitService.routeIntoApp(sessionId, serviceType);
      },
      onDecline: (sessionId) {
        _sessionApi?.reject(sessionId).catchError((_) {});
        CallKitService.dismiss(sessionId);
      },
    );

    // Tap on a foreground (local) notification → the payload carries the
    // deep-link + broadcastId. Attribute the tap, then route to the destination.
    LocalNotifs.onTap = (payload) {
      if (payload.isEmpty) return;
      final uri = Uri.tryParse(payload);
      final bid = uri?.queryParameters['bid'];
      if (bid != null && bid.isNotEmpty) _recordClick(bid);
      AstroDeepLink.open(payload);
    };

    // Foreground: the OS does NOT show a tray banner, so we draw one via the
    // local-notifications channel. Also ACK delivery — the message has
    // demonstrably arrived on this device.
    FirebaseMessaging.onMessage.listen((msg) {
      // Silent reachability probe (foreground): ACK connectivity, draw nothing.
      // In practice the socket heartbeat already keeps a foreground app fresh, so
      // this is just belt-and-suspenders for the probe/heartbeat race window.
      if ((msg.data['type'] ?? '').toString() == 'presence_ping') {
        PresenceAck.send();
        return;
      }
      _recordDelivered(msg.data['broadcastId']?.toString());
      // Incoming request in the foreground: the socket usually rings the in-app
      // screen already, but if the socket is momentarily down the push still
      // raises the native call screen (CallKit). 'cancel' dismisses it.
      final callType = (msg.data['callType'] ?? '').toString();
      if (callType == 'incoming') {
        CallKitService.showIncoming(msg.data);
        return;
      }
      if (callType == 'cancel') {
        CallKitService.dismiss((msg.data['sessionId'] ?? '').toString());
        return;
      }
      final n = msg.notification;
      final title = (n?.title ?? msg.data['title'] ?? 'Rudraganga').toString();
      final body = (n?.body ?? msg.data['body'] ?? '').toString();
      if (title.isEmpty && body.isEmpty) return;
      LocalNotifs.show(title, body, payload: _payloadUri(msg.data));
    });

    // Tap on a tray notification that opened the app from the BACKGROUND.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // Tap that launched the app from a TERMINATED state.
    _fcm.getInitialMessage().then((msg) {
      if (msg != null) _handleTap(msg);
    });

    // If the token rotates while logged in, push the new one to the backend.
    _fcm.onTokenRefresh.listen((token) async {
      _lastToken = token;
      try {
        final device = await DeviceInfo.collect();
        await _api?.registerFcmToken(token, platform: platform, device: device);
      } catch (_) {/* will retry on next login/bootstrap */}
    });
  }

  /// A tray-notification tap (background/terminated): a tap proves receipt too,
  /// so ACK delivery (de-duped server-side), attribute the click, AND route to
  /// the deep-link the admin attached (data.deeplink).
  void _handleTap(RemoteMessage msg) {
    final bid = msg.data['broadcastId']?.toString();
    _recordDelivered(bid);
    _recordClick(bid);
    final deeplink = msg.data['deeplink']?.toString();
    if (deeplink != null && deeplink.isNotEmpty) {
      AstroDeepLink.open(deeplink);
      return;
    }
    // No explicit admin deeplink → route by the notification `type` (e.g.
    // new_follower → followers page), matching the foreground/in-app path.
    final type = (msg.data['type'] ?? '').toString();
    if (type.isNotEmpty) AstroDeepLink.open('rudraganga://notification/$type');
  }

  /// Encode an FCM data map into a payload string for the local notification so
  /// a foreground tap can attribute the click. Carries bid (the broadcastId).
  static String _payloadUri(Map<String, dynamic> data) {
    final bid = data['broadcastId']?.toString();
    final q = (bid != null && bid.isNotEmpty) ? '?bid=$bid' : '';
    final explicit = data['deeplink']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit.contains('?') ? '$explicit&bid=$bid' : '$explicit$q';
    }
    final type = (data['type'] ?? 'system').toString();
    return 'rudraganga://notification/$type$q';
  }

  /// Best-effort tap attribution → backend increments the broadcast's tap count.
  void _recordClick(String? broadcastId) {
    if (broadcastId == null || broadcastId.isEmpty) return;
    _api?.recordNotificationClick(broadcastId).catchError((_) {});
  }

  /// Best-effort device-delivery ACK → backend counts true (device-confirmed)
  /// delivery. Uses the standalone helper so the same path works everywhere.
  void _recordDelivered(String? broadcastId) {
    DeliveryAck.send(broadcastId).catchError((_) {});
  }

  /// Ask the OS for notification permission (Android 13+ / iOS show a prompt).
  /// Returns true if authorized or provisionally authorized.
  Future<bool> requestPermission() async {
    try {
      final settings = await _fcm.requestPermission(alert: true, badge: true, sound: true);
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Fetch this device's FCM token (null if unavailable / not permitted).
  Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Request permission then return the token in one step (for the registration
  /// form). No-throw: returns null on any failure so it never blocks the flow.
  Future<String?> ensureToken() async {
    final ok = await requestPermission();
    if (!ok) return null;
    return getToken();
  }

  /// Fetch the FCM token + register it with the backend so broadcasts reach this
  /// device. Requests permission if not yet decided (the astrologer app has no
  /// dedicated permissions screen, unlike the user app). Best-effort: never
  /// throws — a push failure must not block the app.
  Future<void> registerWithBackend() async {
    try {
      final api = _api;
      if (api == null) return;
      var settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        // No prior decision → ask now (first login).
        await requestPermission();
        settings = await _fcm.getNotificationSettings();
      }
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) return;
      _lastToken = token;
      final device = await DeviceInfo.collect();
      await api.registerFcmToken(token, platform: platform, device: device);
    } catch (_) {
      // Don't let push failures block the app — best-effort.
    }
  }

  /// Remove this device's token from the backend, then delete it locally so a
  /// logged-out device stops receiving the previous astrologer's pushes.
  Future<void> unregisterFromBackend() async {
    final token = _lastToken;
    try {
      if (token != null) await _api?.removeFcmToken(token);
    } catch (_) {/* ignore */}
    try {
      await _fcm.deleteToken();
    } catch (_) {/* ignore */}
    _lastToken = null;
  }
}
