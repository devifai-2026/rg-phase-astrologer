import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/astrologer_api.dart';
import 'api/notification_api.dart';
import 'api/session_api.dart';
import 'api/live_api.dart';
import 'api/service_feedback_api.dart';
import 'api/horoscope_api.dart';
import 'api/panchang_api.dart';
import 'api/socket_service.dart';
import 'api/token_store.dart';
import 'firebase_options.dart';
import 'i18n/strings.dart';
import 'providers/notifications_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/requests/incoming_ring.dart';
import 'services/callkit_service.dart';
import 'screens/splash/splash_one_screen.dart';
import 'services/analytics.dart';
import 'services/astro_deep_link.dart';
import 'services/local_notifs.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (Cloud Messaging — push). Best-effort: a failure here must not
  // block app launch (e.g. on a device without Play Services).
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Local notifications must be ready before any FCM message can arrive — the
    // backend sends DATA-ONLY pushes, so we render the tray banner ourselves.
    await LocalNotifs.init();
    await PushService.instance.init();
    // Ask for the full-screen-intent grant so the incoming-call screen can pop
    // OVER the lock screen on Android 14+ (no-op elsewhere).
    await CallKitService.ensureFullScreenIntentPermission();
    Analytics.instance.setProp('role', 'astrologer'); // GA: segment astrologer app
  } catch (_) {/* push is optional — continue without it */}

  // Lock to portrait — no landscape rotation.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final settings = SettingsProvider();
  await settings.load(); // restore theme + locale before first frame

  // Auth session: load any stored token, build the shared authenticated API.
  final tokens = TokenStore();
  await tokens.load();
  final client = ApiClient(tokens);
  // Send the chosen language as `x-lang` on every request so the backend returns
  // dynamic content in that language regardless of the saved profile field.
  client.langCode = settings.effectiveLangCode;
  settings.onLanguageChanged = (code) => client.langCode = code;

  // Tenant brand name + logo (drives the {appName} placeholder + splash/login logo).
  // AWAIT it (bounded) so the FIRST frame already shows the tenant's brand — not
  // the neutral default flashing first. On failure we keep the neutral default.
  try {
    final data = await client.get('/app-config').timeout(const Duration(seconds: 8));
    final name = (data is Map && data['appName'] is String) ? (data['appName'] as String).trim() : '';
    if (name.isNotEmpty) Strings.brandName = name;
    final logo = (data is Map && data['logoUrl'] is String) ? (data['logoUrl'] as String).trim() : '';
    if (logo.isNotEmpty) Strings.brandLogoUrl = logo;
  } catch (_) {/* keep neutral default */}
  final api = AstrologerApi(client, tokens);
  final socket = SocketService(tokens);
  final sessionApi = SessionApi(client);
  final liveApi = LiveApi(client);
  final serviceFeedbackApi = ServiceFeedbackApi(client);
  final horoscopeApi = HoroscopeApi(client);
  final panchangApi = PanchangApi(client);
  // Give push the authenticated APIs: token registration + tap attribution, and
  // SessionApi so the native call screen can reject a request over REST.
  PushService.instance.attach(api, sessionApi: sessionApi);
  final session = SessionProvider();
  // Notification inbox (bell badge + Notifications screen), backed by the
  // /notifications API. A live 'new-notification' socket event (e.g. an admin
  // approving a storefront item) refreshes it so the badge updates instantly.
  final notifications = NotificationsProvider(NotificationApi(client));
  socket.onNewNotification = (_) => notifications.load();

  // ── Consultation realtime wiring ──
  // An incoming request rings a full-screen call-style screen (even from the
  // background, via the deep-link navigator). The seeker is anonymous (alias).
  socket.onIncomingRequest = (d) => IncomingRing.present(session, d);
  socket.onRequestCancelled = (d) {
    final sid = (d['sessionId'] ?? '').toString();
    if (sid == session.incomingSessionId || sid == session.activeSessionId) { session.clearIncoming(); IncomingRing.dismiss(); }
    CallKitService.dismiss(sid); // also tear down the native call screen
  };
  socket.onRequestExpired = (d) {
    session.clearIncoming();
    IncomingRing.dismiss();
    CallKitService.dismiss((d['sessionId'] ?? '').toString());
  };
  socket.onSessionStarted = (d) {
    CallKitService.dismiss((d['sessionId'] ?? '').toString()); // call connected → drop the ring UI
    session.onSessionStarted(d);
  };
  socket.onReceiveMessage = (d) => session.addLiveMessage(d);
  socket.onGiftReceived = (d) => session.addLiveMessage({...d, 'kind': 'gift'});
  socket.onSessionEnded = (d) {
    session.onSessionEnded(d);
    // Auto re-assert availability whenever ANY session (chat/call/video) ends.
    // The backend already recomputes + broadcasts presence on end, but this is a
    // guaranteed client-side nudge from the astrologer who is provably online
    // right now: it forces a fresh `set-online` → recompute → astrologer-status
    // broadcast, so every user's list/detail flips the astrologer back to online
    // immediately (the bug where the seeker's screen stayed 'offline' after a
    // call). No-op when the astrologer's intent is offline.
    //
    // VIDEO end specifically: tearing down the Agora video engine is heavy and
    // can briefly stall the socket, so a single immediate emit may land while the
    // presence store still reads the call as live (→ user sees 'offline'). Fire
    // the re-assert NOW and again after the teardown settles, over BOTH the
    // socket (fast path) and the durable HTTP toggle (survives a socket blip).
    if (session.isOnline) {
      void reassert() {
        socket.setOnline(true);
        api.setOnline(true).catchError((_) {}); // durable HTTP fallback
      }
      reassert();
      Future.delayed(const Duration(milliseconds: 1200), () { if (session.isOnline) reassert(); });
      Future.delayed(const Duration(milliseconds: 3000), () { if (session.isOnline) reassert(); });
    }
  };
  // Session truly dead (refresh failed) → wipe persisted tokens and drop the
  // socket so the next launch / next screen cleanly falls back to OTP login
  // instead of retrying a doomed session forever.
  client.onSessionExpired = () {
    tokens.clear();
    socket.disconnect();
    notifications.reset();
  };
  // Cold start with an existing session → connect immediately (goes online),
  // (re)register this device's FCM token, and prime the notification inbox.
  if (tokens.hasSession) {
    socket.connect();
    PushService.instance.registerWithBackend(); // fire-and-forget; self-heals on token refresh
    notifications.load(); // fire-and-forget; primes the bell badge + inbox
  }

  runApp(RgAstrologerApp(settings: settings, api: api, socket: socket, notifications: notifications, session: session, sessionApi: sessionApi, liveApi: liveApi, serviceFeedbackApi: serviceFeedbackApi, horoscopeApi: horoscopeApi, panchangApi: panchangApi));
}

class RgAstrologerApp extends StatelessWidget {
  final SettingsProvider settings;
  final AstrologerApi api;
  final SocketService socket;
  final NotificationsProvider notifications;
  final SessionProvider session;
  final SessionApi sessionApi;
  final LiveApi liveApi;
  final ServiceFeedbackApi serviceFeedbackApi;
  final HoroscopeApi horoscopeApi;
  final PanchangApi panchangApi;
  const RgAstrologerApp({super.key, required this.settings, required this.api, required this.socket, required this.notifications, required this.session, required this.sessionApi, required this.liveApi, required this.serviceFeedbackApi, required this.horoscopeApi, required this.panchangApi});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        Provider<AstrologerApi>.value(value: api),
        Provider<SessionApi>.value(value: sessionApi),
        Provider<LiveApi>.value(value: liveApi),
        Provider<ServiceFeedbackApi>.value(value: serviceFeedbackApi),
        Provider<HoroscopeApi>.value(value: horoscopeApi),
        Provider<PanchangApi>.value(value: panchangApi),
        ChangeNotifierProvider<SocketService>.value(value: socket),
        ChangeNotifierProvider<NotificationsProvider>.value(value: notifications),
        ChangeNotifierProvider.value(value: session),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, s, _) {
          return MaterialApp(
            // Neutral OS-level title; the user-visible app label comes from the
            // Android manifest (tenant.appLabel, set per build), so no tenant's
            // name leaks into another tenant's build.
            title: 'Astro Partner',
            debugShowCheckedModeBanner: false,
            // Lets notification taps route deep-links from outside the tree.
            navigatorKey: AstroDeepLink.navigatorKey,
            navigatorObservers: [Analytics.instance.observer], // auto screen_view → GA

            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: s.themeMode,
            locale: s.locale, // null → follow device
            supportedLocales: Strings.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SplashOneScreen(),
          );
        },
      ),
    );
  }
}
