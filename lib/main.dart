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
import 'api/auth_session.dart';
import 'api/socket_service.dart';
import 'api/token_store.dart';
import 'net/app_lifecycle_binder.dart';
import 'net/host_resolver.dart';
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
    final tag = (data is Map && data['tagline'] is String) ? (data['tagline'] as String).trim() : '';
    if (tag.isNotEmpty) Strings.brandTagline = tag;
  } catch (_) {/* keep neutral default */}
  final api = AstrologerApi(client, tokens);
  // One HostResolver + one AuthSession, SHARED by the socket and (in future) the
  // REST client, so they can never disagree about which host they're on or race
  // two refreshes against a rotating refresh token.
  final hostResolver = HostResolver();
  await hostResolver.load();
  final authSession = AuthSession(tokens, apiBase: () => hostResolver.apiBase)
    ..onSessionExpired = () { tokens.clear(); };
  final socket = SocketService(tokens, resolver: hostResolver, auth: authSession);
  final sessionApi = SessionApi(client);
  final liveApi = LiveApi(client);
  final serviceFeedbackApi = ServiceFeedbackApi(client);
  final horoscopeApi = HoroscopeApi(client);
  final panchangApi = PanchangApi(client);
  // Give push the authenticated APIs: token registration + tap attribution, and
  // SessionApi so the native call screen can reject a request over REST.
  final session = SessionProvider();
  // `session` too, so a decline taken on the NATIVE CallKit screen also clears
  // the in-app ring state (otherwise the Flutter ring stayed up on a session the
  // server had already rejected).
  PushService.instance.attach(
    api,
    sessionApi: sessionApi,
    session: session,
    // A silent presence_ping means the server thinks we're unreachable. If the
    // app is in the foreground with a dead socket, rebuild it instead of merely
    // ACKing — otherwise the astrologer stays invisible to seekers until they
    // notice and re-toggle, which is the impression we most need to avoid.
    onPresencePing: () => socket.nudge(),
  );
  // Notification inbox (bell badge + Notifications screen), backed by the
  // /notifications API. A live 'new-notification' socket event (e.g. an admin
  // approving a storefront item) refreshes it so the badge updates instantly.
  final notifications = NotificationsProvider(NotificationApi(client));
  socket.onNewNotification = (_) => notifications.load();

  // GLOBAL link→provider mirror. DashboardShell also binds this, but only while
  // it is mounted: before the dashboard exists (splash, permissions, onboarding)
  // and after it disposes, nothing updated _socketLive, so the UI fell back to a
  // stale value. Binding here means the displayed status always reflects the real
  // transport for the app's whole lifetime.
  socket.addListener(() => session.setSocketLive(socket.status.reachable));
  session.setSocketLive(socket.status.reachable);

  // ONE lifecycle observer for the link (replaces per-screen observers that each
  // fired their own connect on resume and handled no other state).
  // Keep a reference (it used to be a throwaway expression, so nothing could
  // ever set hold-open) and derive hold-open from live session state: while a
  // consultation is running OR a request is ringing, backgrounding must NOT tear
  // the socket down — that dropped the astrologer mid-consultation and made them
  // look offline to the seeker who was still being billed.
  final lifecycle = AppLifecycleBinder(socket: socket, tokens: tokens, resolver: hostResolver);
  lifecycle.shouldHoldOpen = () => session.inSession || session.incomingSessionId != null;
  lifecycle.attach();

  // ── Consultation realtime wiring ──
  // An incoming request rings a full-screen call-style screen. When the app is
  // NOT foreground (backgrounded-in-RAM with a live socket), a pushed Flutter
  // route is invisible — delegate to the native CallKit screen instead (the
  // same surface the FCM path raises; showIncoming dedupes by sessionId).
  socket.onIncomingRequest = (d) {
    final inForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (inForeground) {
      IncomingRing.present(session, d);
    } else {
      CallKitService.showIncoming({
        ...d,
        'serviceType': d['type'],
        'alias': (d['from'] is Map ? d['from']['alias'] : d['alias'])?.toString() ?? 'Seeker',
      });
    }
  };
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
    // Re-assert availability once when a session ends. Previously this fired
    // three times (0/1.2s/3s) over BOTH the socket and HTTP, to paper over a
    // server bug where the post-session recompute could derive "offline" while
    // Agora teardown briefly stalled the socket. That is now fixed properly
    // server-side (a short post-session grace on the presence lease), and
    // SocketService re-asserts intent on every reconnect by itself — so one
    // emit is enough. It is also cheap and harmless if the server already
    // recomputed. No-op when the astrologer's intent is offline.
    if (session.isOnline) socket.setOnline(true);
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
  // hasRefresh, not the old ambiguous hasSession. And socket.start() (not the
  // old connect()) always ends in a DEFINITE state: it refreshes a missing access
  // token, and if that fails it lands in LinkState.fatal with a Retry affordance
  // instead of returning silently and leaving the UI on "Connecting…" forever.
  if (tokens.hasRefresh) {
    socket.start();
    PushService.instance.registerWithBackend(); // fire-and-forget; self-heals on token refresh
    notifications.load(); // fire-and-forget; primes the bell badge + inbox
    // RESUME: the app may have been killed / swiped out of RAM mid-consultation.
    // Ask the server for a still-live session and re-enter it (rejoining the
    // socket room and reloading the transcript) instead of landing on the
    // dashboard while the seeker is still being billed.
    session.resumeFromActive(sessionApi, socket);
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
