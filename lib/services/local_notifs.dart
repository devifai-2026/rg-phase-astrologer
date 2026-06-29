import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// On-device notifications. The backend sends DATA-ONLY FCM messages (no
/// `notification` block) so the OS never draws a tray banner — we render it
/// ourselves via this plugin, both in the foreground and from the headless
/// background isolate. Mirrors the user app's LocalNotifs.
class LocalNotifs {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static final _rand = Random();

  static const _channel = AndroidNotificationChannel(
    'rg_general', 'Rudraganga', description: 'General app notifications', importance: Importance.high,
  );

  /// High-importance channel for incoming consultation requests. Max importance
  /// so it can present a full-screen, call-style UI even when the app is in the
  /// background or killed (paired with fullScreenIntent below).
  static const _incomingChannel = AndroidNotificationChannel(
    'rg_incoming', 'Incoming requests',
    description: 'Incoming chat / call / video consultation requests',
    importance: Importance.max,
    playSound: true,
  );

  /// Called when the user taps a local notification, with its `payload` string
  /// (we pass the broadcastId so taps can be attributed). Set by PushService.
  static void Function(String payload)? onTap;

  static Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) onTap?.call(p);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.createNotificationChannel(_incomingChannel);
    // Ask for notification permission (Android 13+) so requests can ring.
    await android?.requestNotificationsPermission();
    _ready = true;
  }

  /// Show a full-screen, call-style incoming-request notification. On Android
  /// (with USE_FULL_SCREEN_INTENT) this surfaces over the lock screen / other
  /// apps like a phone call; tapping carries [payload] (sessionId|type) to the
  /// ring screen. On iOS it shows as a high-priority heads-up notification.
  static Future<void> showIncoming(String title, String body, {required String payload}) async {
    await init();
    await _plugin.show(
      1001, // fixed id so a cancel/replace targets the active ring
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rg_incoming', 'Incoming requests',
          channelDescription: 'Incoming consultation requests',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true, // ring over lock screen / other apps
          ongoing: true,
          autoCancel: false,
          timeoutAfter: 60000, // auto-dismiss after the ring window
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Cancel the active incoming-request notification (accepted/cancelled/expired).
  static Future<void> cancelIncoming() async => _plugin.cancel(1001);

  /// Show a notification immediately — used to surface a foreground/background
  /// FCM push (the OS won't draw the banner for data-only messages). [payload]
  /// is returned to [onTap] when the user taps it.
  static Future<void> show(String title, String body, {String? payload}) async {
    await init();
    await _plugin.show(
      _rand.nextInt(1 << 30),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails('rg_general', 'Rudraganga',
            channelDescription: 'General app notifications', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}
