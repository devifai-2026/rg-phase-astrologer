import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/session_api.dart';
import '../providers/session_provider.dart';
import '../screens/ai/recap_list_screen.dart';
import '../screens/dashboard/dashboard_shell.dart';
import '../screens/followers/followers_screen.dart';
import '../screens/live/go_live_setup_screen.dart';
import '../screens/notifications/notifications_screen.dart';
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
    if (route == 'incoming') {
      _openIncoming(link);
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

  /// Replay a deep-link that arrived before the navigator was ready (cold-start
  /// tap). Call once the dashboard has mounted. No-op if nothing is pending.
  static void flushPending() {
    final link = _pending;
    if (link == null) return;
    _pending = null;
    open(link);
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
