import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/live_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/how_it_works_button.dart';
import '../onboarding/module_onboarding.dart';
import 'go_live_setup_screen.dart';
import 'live_recap_screen.dart';

/// Shown before going live: a "How it works" entry, the astrologer's REAL
/// previous live sessions (fetched from the backend), and the button to start a
/// new one. Tapping a past session shows its AI recap (generated once, cached).
class PreLiveScreen extends StatefulWidget {
  const PreLiveScreen({super.key});

  @override
  State<PreLiveScreen> createState() => _PreLiveScreenState();
}

class _PreLiveScreenState extends State<PreLiveScreen> {
  List<LiveHistoryItem> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<LiveApi>().mine();
      if (!mounted) return;
      setState(() { _history = items; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _totalEarned => _history.fold(0, (s, h) => s + h.superchatTotal);

  @override
  Widget build(BuildContext context) {
    final c = context.rg;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.sensors, color: c.indigo, size: 20),
          const SizedBox(width: 8),
          Text(Strings.of(context).live2, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        actions: const [HowItWorksButton(moduleKey: 'live', compact: true)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: c.indigo,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Hero + start.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(colors: [c.violet, c.indigo], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.sensors, color: Colors.white, size: 30),
                const SizedBox(height: 10),
                Text(Strings.of(context).startALiveSession, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text(Strings.of(context).hostAQATakeGifts, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.4)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: c.indigo, minimumSize: const Size.fromHeight(46)),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(Strings.of(context).setUpGoLive, style: const TextStyle(fontWeight: FontWeight.w800)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoLiveSetupScreen())),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // "How it works" entry.
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => ModuleOnboarding.show(context, 'live'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.gold.withValues(alpha: 0.4))),
                child: Row(children: [
                  Icon(Icons.play_circle_outline, color: c.gold, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Strings.of(context).howLiveAiWork, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(Strings.of(context).replayTheWalkthroughGiftsQuestionsAi, style: TextStyle(color: c.muted, fontSize: 12, height: 1.3)),
                  ])),
                  Icon(Icons.chevron_right, color: c.muted),
                ]),
              ),
            ),
            const SizedBox(height: 22),

            // Previous lives (real).
            Row(children: [
              Text(Strings.of(context).yourPreviousLives, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              if (_history.isNotEmpty) Text(Strings.of(context).totalearnedEarned(_totalEarned), style: TextStyle(color: c.gold, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),

            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator()))
            else if (_history.isEmpty)
              _emptyHistory(c)
            else
              ..._history.map((h) => _LiveHistoryCard(h: h, onTap: () => _showSummary(h))),
          ],
        ),
      ),
    );
  }

  Widget _emptyHistory(RgColors c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(children: [
          Icon(Icons.videocam_off_outlined, color: c.muted, size: 40),
          const SizedBox(height: 10),
          Text(Strings.of(context).noLiveSessionsYet, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(Strings.of(context).yourPastBroadcastsAndTheirAi,
              textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4)),
        ]),
      );

  void _showSummary(LiveHistoryItem h) {
    // Tapping a past broadcast opens the full recap: audience metrics, the AI
    // moderator scorecard (spam/abusive removed), every poll with its vote
    // tallies, and the AI recap text.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LiveRecapScreen(liveSessionId: h.id),
    ));
  }
}

class _SummarySheet extends StatefulWidget {
  final LiveHistoryItem item;
  const _SummarySheet({required this.item});
  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  String? _summary;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final s = await context.read<LiveApi>().summary(widget.item.id);
      if (!mounted) return;
      setState(() { _summary = s; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final h = widget.item;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.auto_awesome, color: c.violet, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(h.title.isEmpty ? 'Live recap' : h.title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16))),
        ]),
        const SizedBox(height: 4),
        Text(Strings.of(context).aiRecap, style: TextStyle(color: c.violet, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 14),

        // Stats strip.
        Row(children: [
          _stat(c, Icons.visibility, '${h.peakViewers}', Strings.of(context).peakViewers2, c.blue),
          _stat(c, Icons.chat_bubble_outline, '${h.commentCount}', 'comments', c.violet),
          _stat(c, Icons.bolt, '₹${h.superchatTotal}', 'gifts', c.gold),
        ]),
        const SizedBox(height: 16),

        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()))
        else if (_error)
          Text(Strings.of(context).couldNotLoadTheRecapPull, style: TextStyle(color: c.muted))
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
            child: Text(_summary ?? '', style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.5)),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _stat(RgColors c, IconData icon, String v, String l, Color tint) => Expanded(
        child: Row(children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 5),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(v, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Text(l, style: TextStyle(color: c.muted, fontSize: 9.5)),
          ]),
        ]),
      );
}

class _LiveHistoryCard extends StatelessWidget {
  final LiveHistoryItem h;
  final VoidCallback onTap;
  const _LiveHistoryCard({required this.h, required this.onTap});

  String get _when {
    final d = h.startedAt;
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final mins = (h.durationSec / 60).round();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              height: 42, width: 42,
              decoration: BoxDecoration(color: c.indigo.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
              child: Icon(Icons.videocam, color: c.indigo, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.title.isEmpty ? Strings.of(context).liveSession : h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text([if (_when.isNotEmpty) _when, if (mins > 0) Strings.of(context).minsMin(mins), if (h.status == 'live') Strings.of(context).liveNow].join(' · '),
                  style: TextStyle(color: h.status == 'live' ? c.red : c.muted, fontSize: 11.5, fontWeight: h.status == 'live' ? FontWeight.w800 : FontWeight.w500)),
            ])),
            Icon(Icons.auto_awesome, color: c.violet, size: 18),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _stat(c, Icons.visibility, '${h.peakViewers}', 'viewers', c.blue),
            _stat(c, Icons.chat_bubble_outline, '${h.commentCount}', 'comments', c.violet),
            _stat(c, Icons.bolt, '₹${h.superchatTotal}', 'gifts', c.gold),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(RgColors c, IconData icon, String v, String l, Color tint) => Expanded(
        child: Row(children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 5),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Text(l, style: TextStyle(color: c.muted, fontSize: 9.5)),
          ])),
        ]),
      );
}
