import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/session_api.dart';
import '../api/socket_service.dart';
import '../providers/session_provider.dart';
import 'callkit_service.dart';
import '../screens/ai/recap_list_screen.dart';
import '../screens/dashboard/dashboard_shell.dart';
import '../screens/followers/followers_screen.dart';
import '../screens/live/go_live_setup_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/requests/active_session_screen.dart';
import '../screens/requests/call_screen.dart';
import '../screens/requests/incoming_ring.dart';
import '../screens/settings/astro_settings_screen.dart';
import '../screens/storefront/storefront_screen.dart';
import '../widgets/slide_route.dart';

/// Routes a notification deep-link to a destination inside the astrologer app.
///
/// The admin's "On tap, open" dropdown emits `rudraganga://astro/<route>` URIs
/// (see ASTRO_LINK_TARGETS in admin/src/pages/Notifications.jsx) — this maps each
/// to a tab or screen. Navigation goes through [navigatorKey] so it works from a
/// notification tap (foreground/background/terminated), outside the widget tree.
///
/// Tab routes (home/requests/history/earnings/profile) ask the [DashboardShell]
/// to switch tabs and pop any pushed screens. Screen routes push on top. All
/// no-op gracefully if the navigator isn't ready (e.g. still on the splash/login
/// screen) — the tap still opens the app, just to wherever it was.
class AstroDeepLink {
  /// Attach to MaterialApp(navigatorKey:) so routing works from outside a widget.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// A link received before the navigator (or the dashboard) was ready — e.g. a
  /// terminated-state tap handled during early startup, while the splash is
  /// still showing. Replayed by [flushPending] once the dashboard mounts.
  static String? _pending;

  /// Handle a deep-link string. Accepts the full `rudraganga://astro/<route>`
  /// URI or a bare `<route>`. Unknown/empty links just open the app (no-op).
  static void open(String? link) {
    if (link == null || link.isEmpty) return;
    final route = _route(link);
    if (route == null) return;

    final nav = navigatorKey.currentState;
    if (nav == null) {
      // Navigator not mounted yet (cold-start tap during splash) → remember it
      // and replay once the dashboard is on screen.
      _pending = link;
      return;
    }

    // Incoming consultation request tapped from a full-screen notification →
    // recover the session + ring. Carries ?sessionId=&stype= in the link.
    // `accepted=1` means the astrologer hit ACCEPT on the native CallKit screen
    // (often a cold start): don't re-ring — complete the accept and jump into the
    // session, exactly like the in-app Accept button. This also unblocks the USER
    // (the backend accept emits 'request-accepted' to them, ending "requesting").
    if (route == 'incoming') {
      final accepted = Uri.tryParse(link)?.queryParameters['accepted'] == '1';
      if (accepted) {
        _acceptIncoming(link);
      } else {
        _openIncoming(link);
      }
      return;
    }

    // AI recap review (Feature 1): rudraganga://astro/recaps?recapId=<id>.
    // Open the queue, and jump straight to the named recap if provided.
    if (route == 'recaps') {
      final recapId = Uri.tryParse(link)?.queryParameters['recapId'];
      nav.push(slideRoute(RecapListScreen(openRecapId: recapId)));
      return;
    }

    switch (route) {
      case 'home':
        _toTab(nav, DashboardShell.tabHome);
        break;
      case 'requests':
        _toTab(nav, DashboardShell.tabRequests);
        break;
      case 'history':
        _toTab(nav, DashboardShell.tabHistory);
        break;
      case 'earnings':
        _toTab(nav, DashboardShell.tabEarnings);
        break;
      case 'profile':
        _toTab(nav, DashboardShell.tabProfile);
        break;
      case 'notifications':
        nav.push(slideRoute(const NotificationsScreen()));
        break;
      case 'new_follower':
      case 'followers':
        nav.push(slideRoute(const FollowersScreen()));
        break;
      case 'storefront':
        nav.push(slideRoute(const StorefrontScreen()));
        break;
      case 'live':
        nav.push(slideRoute(const GoLiveSetupScreen()));
        break;
      case 'settings':
        nav.push(slideRoute(const AstroSettingsScreen()));
        break;
      default:
        // Unknown route → just open the app.
        break;
    }
  }

  /// Open the full-screen ring for an incoming request tapped from a
  /// notification. Recovers the seeker alias + service type from the backend
  /// (the session detail returns the alias) and presents the ring.
  static Future<void> _openIncoming(String link) async {
    final uri = Uri.tryParse(link);
    final sessionId = uri?.queryParameters['sessionId'];
    final stype = uri?.queryParameters['stype'] ?? 'chat';
    final ctx = navigatorKey.currentContext;
    if (sessionId == null || sessionId.isEmpty || ctx == null) return;
    final session = ctx.read<SessionProvider>();
    final api = ctx.read<SessionApi>();
    var alias = 'Seeker';
    try {
      final detail = await api.detail(sessionId);
      final seeker = detail['seeker'];
      alias = (seeker is Map ? seeker['alias'] : null)?.toString() ?? detail['seekerAlias']?.toString() ?? 'Seeker';
    } catch (_) {/* fall back to generic alias */}
    IncomingRing.present(session, {'sessionId': sessionId, 'type': stype, 'alias': alias});
  }

  /// Map the link's stype to the astrologer's ServiceKind.
  static ServiceKind _kindOf(String? stype) => switch (stype) {
        'call' => ServiceKind.call,
        'video' => ServiceKind.video,
        _ => ServiceKind.chat,
      };

  /// Complete an accept that originated from the native CallKit screen (the
  /// astrologer already tapped Accept there). Runs the SAME path as the in-app
  /// Accept button: REST accept → join the socket room → mark the session active
  /// → navigate into the session screen. Without this, a CallKit accept on a
  /// cold start just dropped the astrologer on the dashboard and left the seeker
  /// stuck on "requesting" (the backend never saw the accept, so 'request-accepted'
  /// and 'session-started' never fired → both sides hung, timer stayed at 0).
  static Future<void> _acceptIncoming(String link) async {
    final uri = Uri.tryParse(link);
    final sessionId = uri?.queryParameters['sessionId'];
    final kind = _kindOf(uri?.queryParameters['stype']);
    final ctx = navigatorKey.currentContext;
    final nav = navigatorKey.currentState;
    if (sessionId == null || sessionId.isEmpty || ctx == null || nav == null) return;

    final session = ctx.read<SessionProvider>();
    final api = ctx.read<SessionApi>();
    final socket = ctx.read<SocketService>();

    // Pull the alias for the session header (best-effort).
    var alias = 'Seeker';
    try {
      final detail = await api.detail(sessionId);
      final seeker = detail['seeker'];
      alias = (seeker is Map ? seeker['alias'] : null)?.toString() ?? detail['seekerAlias']?.toString() ?? 'Seeker';
    } catch (_) {/* generic alias */}

    RtcToken? token;
    try {
      token = await api.accept(sessionId); // backend → 'request-accepted' to the seeker
      socket.joinSession(sessionId); // astrologer side of markJoined → unblocks 'session-started'
    } catch (_) {
      // Accept failed (e.g. the ring already expired / was cancelled): fall back
      // to ringing so the astrologer sees the current state instead of a dead end.
      _openIncoming(link);
      return;
    }

    session.startActive(sessionId: sessionId, kind: kind, alias: alias);
    session.clearIncoming();
    // Poll the authoritative startedAt in case the 'session-started' socket event
    // is missed on a cold start (covers the timer-stuck-at-0 case).
    session.syncStartedAt(api);

    final next = kind == ServiceKind.chat
        ? const ActiveSessionScreen(kind: ServiceKind.chat)
        : CallScreen(kind: kind, token: token);
    nav.push(MaterialPageRoute(builder: (_) => next));
  }

  /// Replay a deep-link that arrived before the navigator was ready (cold-start
  /// tap). Call once the dashboard has mounted. No-op if nothing is pending.
  static void flushPending() {
    final link = _pending;
    if (link == null) return;
    _pending = null;
    open(link);
  }

  /// Cold-start safety net: complete a CallKit accept that the live event race
  /// may have dropped (the "sometimes stuck on homepage when fully killed" bug).
  /// Asks the OS which call it considers accepted and finishes the accept.
  static Future<void> resumePendingAccept() async {
    final pending = await CallKitService.consumePendingAccept();
    if (pending == null) return;
    final sid = pending['sessionId']!;
    final stype = pending['serviceType'] ?? 'chat';
    _acceptIncoming('rudraganga://astro/incoming?sessionId=$sid&stype=$stype&accepted=1');
  }

  /// RESUME an already-active consultation after an app kill. The session is
  /// still accepted/ongoing server-side (billing the seeker), but the astrologer
  /// app lost its in-memory session on the kill and stranded them on the
  /// dashboard. Ask the backend for the live session and re-enter its screen.
  /// No-op if there's nothing live, or if a ring/accept is already being routed.
  static Future<void> resumeActiveSession() async {
    final ctx = navigatorKey.currentContext;
    final nav = navigatorKey.currentState;
    if (ctx == null || nav == null) return;

    final session = ctx.read<SessionProvider>();
    if (session.activeSessionId != null) return; // already in a session

    final api = ctx.read<SessionApi>();
    final socket = ctx.read<SocketService>();
    final res = await api.active();
    if (res == null) return;

    final s = res.session;
    final sessionId = (s['sessionId'] ?? '').toString();
    if (sessionId.isEmpty) return;
    final kind = _kindOf((s['type'] ?? 'chat').toString());
    final seeker = s['seeker'];
    final alias = (seeker is Map ? seeker['alias'] : null)?.toString() ?? s['seekerAlias']?.toString() ?? 'Seeker';

    socket.joinSession(sessionId); // rejoin the room → resumes live events + timer
    session.startActive(sessionId: sessionId, kind: kind, alias: alias);
    session.syncStartedAt(api); // adopt the authoritative startedAt for the timer

    final next = kind == ServiceKind.chat
        ? const ActiveSessionScreen(kind: ServiceKind.chat)
        : CallScreen(kind: kind, token: res.token);
    nav.push(MaterialPageRoute(builder: (_) => next));
  }

  /// Switch to a bottom-nav tab: drop any pushed screens, then select the tab.
  static void _toTab(NavigatorState nav, int index) {
    DashboardShell.goToTab(index);
    nav.popUntil((r) => r.isFirst);
  }

  /// Extract the route segment from a deep-link. Handles
  /// `rudraganga://astro/<route>?bid=...`, `astro/<route>`, and bare `<route>`.
  /// Strips a leading user-app-style host too (so `rudraganga://notifications`
  /// from an "All apps" send still maps to the astrologer notifications screen).
  static String? _route(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    // rudraganga://astro/<route>  → host 'astro', path '/<route>'
    // rudraganga://<route>        → host '<route>'
    final segments = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    // Drop the 'astro' namespace if present.
    final parts = segments.first == 'astro' ? segments.sublist(1) : segments;
    if (parts.isEmpty) return null;
    return parts.first.toLowerCase();
  }
}
