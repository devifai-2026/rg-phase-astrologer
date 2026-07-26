import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../providers/session_provider.dart';
import '../../services/astro_deep_link.dart';
import '../../theme/rg_colors.dart';
import '../earnings/earnings_screen.dart';
import '../history/history_screen.dart';
import '../requests/active_session_screen.dart';
import '../requests/call_screen.dart';
import '../requests/requests_screen.dart';
import 'astro_drawer.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

/// Post-onboarding app shell: 5-tab bottom nav
/// (Home · Requests · History · Earnings · Profile).
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  /// Tab indices, used by deep-link routing to jump to a tab.
  static const int tabHome = 0;
  static const int tabRequests = 1;
  static const int tabHistory = 2;
  static const int tabEarnings = 3;
  static const int tabProfile = 4;

  /// A deep-link request to switch the active bottom-nav tab. The mounted shell
  /// listens and selects the tab; set before/while the shell is on screen.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  /// Convenience for deep-link routing — ask the shell to show [index].
  static void goToTab(int index) => tabRequest.value = index;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> with WidgetsBindingObserver {
  int _index = 0;

  late final List<Widget> _tabs = const [
    HomeTab(),
    RequestsScreen(),
    HistoryScreen(),
    EarningsScreen(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DashboardShell.tabRequest.addListener(_onTabRequest);
    // After this shell is on screen, replay any deep-link/tab request queued
    // before the navigator was ready (e.g. a terminated-state notification tap).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onTabRequest();
      AstroDeepLink.flushPending();
      // Cold-start safety net: if the astrologer tapped Accept on the native
      // CallKit screen while the app was fully killed, the live event may have
      // been lost to a startup race. Recover it from the OS and complete the
      // accept; if there was no pending accept, fall back to resuming any session
      // that is STILL live server-side (app killed mid-consultation).
      AstroDeepLink.resumePendingAccept().then((_) => AstroDeepLink.resumeActiveSession());
      _bindPresenceSync();
    });
  }

  // NOTE: no didChangeAppLifecycleState here on purpose. AppLifecycleBinder is
  // the single owner of resume/pause for the link (it nudges the socket and
  // reloads tokens). This class used to ALSO call socket.connect() on resume,
  // racing the binder's nudge() and producing two competing attempts. Intent
  // re-assertion now lives in SocketService.onConnect, so it is covered on every
  // reconnect rather than only while this screen is mounted.

  /// Keep the availability toggle mirrored to the SERVER's true presence in
  /// every scenario: live `my-presence` events (manual toggle, auto-busy on
  /// call start/end, disconnect, admin change) + a re-fetch on socket reconnect.
  void _bindPresenceSync() {
    final socket = context.read<SocketService>();
    // Mirror the socket's live state into the provider so the displayed status
    // can't show "Online" while the socket is dead (it would lie — users see the
    // astrologer as offline since the backend derives presence from the socket).
    void syncLive() {
      if (!mounted) return;
      context.read<SessionProvider>().setSocketLive(socket.connected);
    }
    socket.addListener(syncLive);
    _unbindLive = () => socket.removeListener(syncLive);
    syncLive(); // seed from the current state
    socket.onPresence = (d) {
      if (!mounted) return;
      final session = context.read<SessionProvider>();
      session.syncPresence(
            availabilityPreference: d['availabilityPreference'] as bool?,
            isOnline: d['isOnline'] as bool?,
            currentCallStatus: d['currentCallStatus'] as String?,
          );
      // Break end time (null clears it).
      final bu = d['breakUntil'];
      session.setBreakUntil(bu == null ? null : DateTime.tryParse(bu.toString())?.toLocal());
    };
    socket.onConnected = () async {
      // On every (re)connect: if the astrologer's saved intent is ONLINE,
      // re-assert it over the fresh socket so the server marks them online
      // immediately (don't rely solely on the backend's connect-time recompute,
      // which can race the socket join). This fixes the case where the astro app
      // shows "online" locally but users saw "offline" until a manual toggle.
      if (!mounted) return;
      final session = context.read<SessionProvider>();
      session.setSocketLive(true);
      if (session.isOnline) socket.setOnline(true);
      // Re-pull the authoritative presence from the profile.
      try {
        final p = await context.read<AstrologerApi>().myProfile();
        if (mounted) context.read<SessionProvider>().applyServerProfile(p);
      } catch (_) {/* keep current on failure */}
    };
  }

  // Detaches the socket-liveness listener bound in _bindPresenceSync.
  VoidCallback? _unbindLive;

  void _onTabRequest() {
    final req = DashboardShell.tabRequest.value;
    if (req == null || !mounted) return;
    if (req >= 0 && req < _tabs.length) setState(() => _index = req);
    DashboardShell.tabRequest.value = null; // consume
  }

  /// Re-pull /me/profile so the Profile tab's reputation (followers/gifts/
  /// reviews/rating) reflects the latest server state. Best-effort.
  Future<void> _refreshProfile() async {
    try {
      final p = await context.read<AstrologerApi>().myProfile();
      if (mounted) context.read<SessionProvider>().applyServerProfile(p);
    } catch (_) {/* keep current on failure */}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DashboardShell.tabRequest.removeListener(_onTabRequest);
    _unbindLive?.call();
    // Drop our presence hooks so a disposed shell isn't called back.
    final socket = context.read<SocketService>();
    socket.onPresence = null;
    socket.onConnected = null;
    super.dispose();
  }

  static String _fmt(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();

    // Floating "Resume" pill when a consultation is live but minimized.
    final hasActive = session.activeSessionId != null;

    // Back at the dashboard root confirms before exiting (Stay emphasized).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmExit(context);
        if (leave == true) SystemNavigator.pop();
      },
      child: Scaffold(
      backgroundColor: c.ground,
      drawer: const AstroDrawer(),
      floatingActionButton: hasActive
          ? FloatingActionButton.extended(
              onPressed: () {
                final kind = session.activeKind ?? ServiceKind.chat;
                final screen = kind == ServiceKind.chat
                    ? const ActiveSessionScreen(kind: ServiceKind.chat)
                    : CallScreen(kind: kind);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
              },
              backgroundColor: c.green,
              icon: Icon(session.activeKind == ServiceKind.chat ? Icons.chat_bubble : Icons.call, color: Colors.white),
              label: Text(
                session.sessionStarted ? Strings.of(context).resumeFmtSessionElapsedsec(_fmt(session.elapsedSec)) : Strings.of(context).resumeSession,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_index), child: _tabs[_index]),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: c.ground2,
          indicatorColor: c.redSoft,
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: states.contains(WidgetState.selected) ? c.red : c.muted,
              )),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? c.red : c.muted,
              )),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            // Opening the Profile tab (index 4) → re-pull /me/profile so the live
            // followers / gifts / reviews counts are current (a new follow, gift,
            // or review updates server-side; the cached profile would be stale).
            if (i == 4) _refreshProfile();
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: Strings.of(context).home),
            NavigationDestination(
              icon: _BadgeIcon(icon: Icons.call_received, count: session.incomingKind != null ? 1 : 0),
              selectedIcon: const Icon(Icons.call_received),
              label: Strings.of(context).requests,
            ),
            NavigationDestination(icon: const Icon(Icons.history_outlined), selectedIcon: const Icon(Icons.history), label: Strings.of(context).history),
            NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: Strings.of(context).earnings),
            NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: Strings.of(context).profile),
          ],
        ),
      ),
      ), // Scaffold
    ); // PopScope
  }

  Future<bool?> _confirmExit(BuildContext context) {
    final c = context.rg;
    final s = Strings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(s.exitAppTitle, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        content: Text(s.exitAppBody, style: TextStyle(color: c.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.exitAppConfirm, style: TextStyle(color: c.muted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.red),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.stay, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgeIcon({required this.icon, required this.count});
  @override
  Widget build(BuildContext context) {
    if (count == 0) return Icon(icon);
    final c = context.rg;
    return Stack(clipBehavior: Clip.none, children: [
      Icon(icon),
      Positioned(
        right: -6,
        top: -4,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: c.red, shape: BoxShape.circle),
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }
}
