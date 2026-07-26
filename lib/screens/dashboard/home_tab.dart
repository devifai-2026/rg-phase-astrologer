import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../models/astrologer.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import '../ai/profile_optimizer_screen.dart';
import '../tools/birth_chart_screen.dart';
import '../tools/matching_screen.dart';
import '../tools/manglik_screen.dart';
import '../ai/recap_list_screen.dart';
import '../common/coming_soon_screen.dart';
import '../followers/followers_screen.dart';
import '../horoscope/horoscope_screen.dart';
import '../panchang/panchang_screen.dart';
import '../live/pre_live_screen.dart';
import '../notifications/notifications_screen.dart';
import '../storefront/storefront_screen.dart';
import 'widgets/status_toggle.dart';

/// Astrologer dashboard home: status, earnings, consultation stats segregated
/// by chat/call/video, reputation (gifts/reviews/followers). Balance +
/// consultation stats are fetched live from the backend on open.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  int? _optimizerLeft; // remaining profile-optimizer runs this month (null = loading)
  int _pendingRecaps = 0; // chat recaps awaiting review → home badge

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { _loadDashboard(); _loadOptimizerUsage(); _loadRecapCount(); });
  }

  Future<void> _loadOptimizerUsage() async {
    try {
      final u = await context.read<AstrologerApi>().optimizerUsage();
      if (mounted) setState(() => _optimizerLeft = u.remaining);
    } catch (_) {/* leave null — CTA just omits the badge */}
  }

  Future<void> _loadRecapCount() async {
    try {
      final n = await context.read<AstrologerApi>().recapCount();
      if (mounted) setState(() => _pendingRecaps = n);
    } catch (_) {/* leave 0 on failure */}
  }

  /// Fetch the profile (name/avatar/reputation), wallet balance and
  /// consultation stats, and apply them to the session so the header binds to
  /// the real backend record instead of the demo placeholder. Best-effort —
  /// failures leave the existing values in place.
  Future<void> _loadDashboard() async {
    final api = context.read<AstrologerApi>();
    final session = context.read<SessionProvider>();
    try {
      final results = await Future.wait([api.myProfile(), api.walletBalance(), api.myStats()]);
      if (!mounted) return;
      session.applyServerProfile(results[0]); // header name/avatar + reputation
      final bal = results[1];
      session.applyBalance(
        available: (bal['available'] as num?)?.toInt() ?? (bal['balance'] as num?)?.toInt() ?? 0,
        locked: (bal['lockedBalance'] as num?)?.toInt() ?? 0,
      );
      session.applyStats(results[2]);
    } catch (_) {/* keep current values on failure */}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();
    final p = session.profile;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── Header row ──
          Row(
            children: [
              // Hamburger → opens the side drawer (attached to the shell Scaffold).
              IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: Icon(Icons.menu, color: c.ink),
                tooltip: Strings.of(context).menu,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 22,
                backgroundColor: c.redSoft,
                backgroundImage: _avatarImg(p),
                child: _avatarImg(p) == null
                    ? Text(p.displayName.isNotEmpty ? p.displayName[0] : 'A', style: TextStyle(color: c.red, fontWeight: FontWeight.w800, fontSize: 18))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Strings.of(context).namaste, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
                ]),
              ),
              _NotifBell(unread: context.watch<NotificationsProvider>().unread),
            ],
          ),
          const SizedBox(height: 18),

          // ── Availability ──
          Text(Strings.of(context).availability, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          const StatusToggle(),
          // While on a self-requested break we show the astrologer they're
          // marked busy to seekers (the break banner self-hides when it ends).
          if (session.onBreak) ...[
            const SizedBox(height: 12),
            _BreakBanner(until: session.breakUntil),
          ],
          const SizedBox(height: 16),

          // ── Go Live banner ──
          _GoLiveBanner(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PreLiveScreen()))),
          const SizedBox(height: 16),

          // ── Quick actions (AI Optimizer · Storefront) ──
          Row(children: [
            _QuickAction(
              icon: Icons.auto_fix_high, label: Strings.of(context).aiProfileOptimizer2, tint: c.violet,
              // Show the monthly quota: "1 left this month" (or "0 left" when used up).
              badge: _optimizerLeft == null ? null : Strings.of(context).optimizerleftLeftThisMonth(_optimizerLeft!),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileOptimizerScreen()));
                _loadOptimizerUsage(); // refresh the count after a run
              },
            ),
            const SizedBox(width: 12),
            _QuickAction(
              // Reuses the already-translated myStorefront key. The newline that
              // used to be hardcoded is applied here instead, so translations
              // don't each have to carry a literal \n.
              icon: Icons.storefront,
              label: Strings.of(context).myStorefront.replaceFirst(' ', '\n'),
              tint: c.gold,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorefrontScreen())),
            ),
          ]),
          const SizedBox(height: 12),
          // ── AI Recaps (chat-end summaries awaiting review) ──
          Row(children: [
            _QuickAction(
              icon: Icons.auto_awesome, label: Strings.of(context).aiChatRecaps, tint: c.blue,
              badge: _pendingRecaps > 0 ? Strings.of(context).pendingrecapsPending(_pendingRecaps) : Strings.of(context).allReviewed,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecapListScreen()));
                _loadRecapCount(); // refresh the badge after reviewing
              },
            ),
          ]),
          const SizedBox(height: 18),

          // ── Earnings summary ──
          _EarningsCard(session: session),
          const SizedBox(height: 18),

          // ── Consultations by service ──
          Text(Strings.of(context).consultations, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(Strings.of(context).totalPTotalsessionsSessionsPTotalminutes(p.totalSessions, (p.totalMinutes / 60).round()), style: TextStyle(color: c.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          _ServiceStatRow(label: Strings.of(context).chat, icon: Icons.chat_bubble_outline, stats: p.chatStats, tint: c.blue),
          const SizedBox(height: 10),
          _ServiceStatRow(label: Strings.of(context).call, icon: Icons.call_outlined, stats: p.callStats, tint: c.green),
          const SizedBox(height: 10),
          _ServiceStatRow(label: Strings.of(context).video, icon: Icons.videocam_outlined, stats: p.videoStats, tint: c.violet),
          const SizedBox(height: 20),

          // ── Reputation ──
          Text(Strings.of(context).reputation, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            _RepCell(icon: Icons.favorite, value: _fmt(p.followers), label: Strings.of(context).followers, tint: c.red,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowersScreen()))),
            const SizedBox(width: 10),
            _RepCell(icon: Icons.card_giftcard, value: '${p.giftCount}', label: Strings.of(context).gifts2, tint: c.gold),
            const SizedBox(width: 10),
            _RepCell(icon: Icons.star, value: '${p.rating}', label: Strings.of(context).pReviewcountReviews(p.reviewCount), tint: c.green),
          ]),
          const SizedBox(height: 22),

          // ── Tools (same set the user app offers) ──
          Text(Strings.of(context).tools, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
            children: [
              _ToolTile(
                icon: Icons.nightlight_outlined,
                label: Strings.of(context).dailyHoroscope,
                tintKey: _Tint.gold,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HoroscopeScreen())),
              ),
              _ToolTile(icon: Icons.bubble_chart_outlined, label: Strings.of(context).birthChart, tintKey: _Tint.violet,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BirthChartScreen()))),
              _ToolTile(
                icon: Icons.calendar_month_outlined,
                label: Strings.of(context).panchang,
                tintKey: _Tint.blue,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PanchangScreen())),
              ),
              _ToolTile(icon: Icons.diversity_3_outlined, label: Strings.of(context).matrimony, tintKey: _Tint.green,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchingScreen()))),
              _ToolTile(icon: Icons.menu_book_outlined, label: Strings.of(context).brihatKundli, tintKey: _Tint.gold),
              _ToolTile(icon: Icons.favorite_border, label: Strings.of(context).kundliMatching, tintKey: _Tint.red,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchingScreen()))),
              _ToolTile(icon: Icons.warning_amber_rounded, label: Strings.of(context).manglikDosh, tintKey: _Tint.violet,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManglikScreen()))),
            ],
          ),
        ],
      ),
    );
  }

  ImageProvider? _avatarImg(Astrologer p) {
    final a = p.avatar;
    if (a == null) return null;
    return a.startsWith('http') ? NetworkImage(a) : FileImage(File(a)) as ImageProvider;
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

class _NotifBell extends StatelessWidget {
  final int unread;
  const _NotifBell({required this.unread});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
        child: Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.notifications_outlined, color: c.ink, size: 22),
          if (unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: c.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text('$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final SessionProvider session;
  const _EarningsCard({required this.session});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [c.redDeep, c.red], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Strings.of(context).availableBalance, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
        const SizedBox(height: 4),
        Text('₹${_fmt(session.availableBalance)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32)),
        const SizedBox(height: 14),
        Row(children: [
          _mini(Strings.of(context).thisMonth, '₹${_fmt(session.thisMonthEarnings)}'),
          const SizedBox(width: 24),
          _mini(Strings.of(context).pending, '₹${_fmt(session.pendingBalance)}'),
          const SizedBox(width: 24),
          _mini(Strings.of(context).lifetime, '₹${_fmt(session.lifetimeEarnings)}'),
        ]),
        // Zero-balance nudge: motivate the astrologer to start (or keep) earning.
        if (session.availableBalance == 0) ...[
          const SizedBox(height: 16),
          _BoostTips(freshStart: session.lifetimeEarnings == 0),
        ],
      ]),
    );
  }

  Widget _mini(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
      ]);

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Shown inside the earnings card when the available balance is ₹0 — a short
/// one-line nudge to go online and start earning.
class _BoostTips extends StatelessWidget {
  /// True when the astrologer has never earned (lifetime 0) vs has earned before.
  final bool freshStart;
  const _BoostTips({required this.freshStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Icon(Icons.rocket_launch, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            Strings.of(context).goOnlineSoSeekersCanReach,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.3),
          ),
        ),
      ]),
    );
  }
}

class _ServiceStatRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final ServiceStats stats;
  final Color tint;
  const _ServiceStatRow({required this.label, required this.icon, required this.stats, required this.tint});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Row(children: [
        Container(
          height: 40, width: 40,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: tint, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(Strings.of(context).statsSessionsSessionsStatsMinutesMin(stats.sessions, stats.minutes), style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        ),
        Text('₹${_fmt(stats.earnings)}', style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _RepCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color tint;
  final VoidCallback? onTap;
  const _RepCell({required this.icon, required this.value, required this.label, required this.tint, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final cell = Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(children: [
        Icon(icon, color: tint, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 11)),
      ]),
    );
    return Expanded(
      child: onTap == null
          ? cell
          : InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: cell),
    );
  }
}

/// Shown on the home tab while the astrologer is on a self-requested break.
/// Reassures them we've marked them BUSY to seekers, counts down the remaining
/// break time, and offers a quick "End break" so they can go back online.
class _BreakBanner extends StatefulWidget {
  final DateTime? until;
  const _BreakBanner({required this.until});

  @override
  State<_BreakBanner> createState() => _BreakBannerState();
}

class _BreakBannerState extends State<_BreakBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refresh the countdown every second; self-stops once the break ends.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!context.read<SessionProvider>().onBreak) { _tick?.cancel(); }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _remaining {
    final until = widget.until;
    if (until == null) return '';
    var s = until.difference(DateTime.now()).inSeconds;
    if (s < 0) s = 0;
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString()}:${sec.toString().padLeft(2, '0')}';
  }

  void _endBreak() {
    final s = context.read<SessionProvider>();
    s.setBreakUntil(null); // optimistic — banner hides immediately
    context.read<SocketService>().setBreak(0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: c.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.coffee_rounded, color: c.gold, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.of(context).youReOnABreakWe,
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.until != null
                      ? Strings.of(context).seekersCanTReachYouFor(_remaining)
                      : Strings.of(context).seekersCanTReachYouWhile,
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _endBreak,
            style: TextButton.styleFrom(
              foregroundColor: c.gold,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Text(Strings.of(context).endBreak, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _GoLiveBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _GoLiveBanner({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: [c.violet, c.indigo], begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
        child: Row(children: [
          Container(
            height: 44, width: 44,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.sensors, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Strings.of(context).goLive, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(Strings.of(context).hostALiveQASuperchats, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
  final String? badge; // optional sub-line, e.g. "1 left this month"
  const _QuickAction({required this.icon, required this.label, required this.tint, required this.onTap, this.badge});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final out = badge != null && badge!.startsWith('0'); // "0 left" → muted/used-up
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Row(children: [
            Container(
              height: 42, width: 42,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.15)),
              if (badge != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (out ? c.muted : tint).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge!, style: TextStyle(color: out ? c.muted : tint, fontSize: 9.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ])),
          ]),
        ),
      ),
    );
  }
}

/// Brand tint key for tool tiles (resolved against the theme at build).
enum _Tint { red, gold, green, blue, violet }

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final _Tint tintKey;
  final VoidCallback? onTap; // overrides the default Coming-Soon navigation
  const _ToolTile({required this.icon, required this.label, required this.tintKey, this.onTap});

  Color _tint(BuildContext context) {
    final c = context.rg;
    return switch (tintKey) {
      _Tint.red => c.red,
      _Tint.gold => c.gold,
      _Tint.green => c.green,
      _Tint.blue => c.blue,
      _Tint.violet => c.violet,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final tint = _tint(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap ??
          () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ComingSoonScreen(title: label.replaceAll('\n', ' '), icon: icon)),
              ),
      child: Column(
        children: [
          Container(
            height: 52, width: 52,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: tint, size: 24),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(color: c.ink, fontSize: 11, height: 1.15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

