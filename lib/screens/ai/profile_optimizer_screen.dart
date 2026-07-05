import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../providers/session_provider.dart';
import '../../services/mock_ai.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/how_it_works_button.dart';

/// AI Profile Optimizer — analyses the astrologer's photo, bio, pricing,
/// languages, expertise and availability cycle, scores the profile, and offers
/// one-tap suggestions. (Mock AI: instant, realistic, offline.)
class ProfileOptimizerScreen extends StatefulWidget {
  const ProfileOptimizerScreen({super.key});

  @override
  State<ProfileOptimizerScreen> createState() => _ProfileOptimizerScreenState();
}

class _ProfileOptimizerScreenState extends State<ProfileOptimizerScreen> with SingleTickerProviderStateMixin {
  OptimizerReport? _report;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    final api = context.read<AstrologerApi>();
    final p = context.read<SessionProvider>().profile;
    OptimizerReport report;
    try {
      // Real backend: server-side score + (when configured) an AI-rewritten bio.
      report = OptimizerReport.fromJson(await api.optimizeProfile());
    } catch (_) {
      // Offline / backend unavailable → deterministic local report (mock).
      await Future.delayed(const Duration(milliseconds: 600));
      report = MockAi.optimizeProfile(p);
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final report = _report;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.auto_awesome, color: c.violet, size: 20),
          const SizedBox(width: 8),
          Text(Strings.of(context).aiProfileOptimizer, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        actions: const [HowItWorksButton(moduleKey: 'optimizer', compact: true)],
      ),
      body: report == null ? _intro(c) : _results(c, report),
    );
  }

  Widget _intro(RgColors c) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Container(
            height: 72, width: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.violet, c.indigo]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_fix_high, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text(Strings.of(context).makeYourProfileIrresistible, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 10),
          Text(
            Strings.of(context).theOptimizerReviewsYourPhotoBio,
            style: TextStyle(color: c.muted, fontSize: 14.5, height: 1.5),
          ),
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in [Strings.of(context).photo, Strings.of(context).bio2, Strings.of(context).pricing, Strings.of(context).languages, Strings.of(context).expertise2, Strings.of(context).availability])
              Chip(
                label: Text(x, style: TextStyle(color: c.ink, fontSize: 12.5)),
                backgroundColor: c.ground2,
                side: BorderSide(color: c.line),
              ),
          ]),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _running
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_running ? Strings.of(context).analysingYourProfile : Strings.of(context).runOptimizer),
              onPressed: _running ? null : _run,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _results(RgColors c, OptimizerReport report) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _ScoreCard(report: report),
        // The ONLY actionable item: the AI-rewritten bio can be applied to the
        // profile in one tap. Everything else is advice (read-only).
        if (report.aiBio != null) ...[
          const SizedBox(height: 18),
          _AiBioCard(bio: report.aiBio!),
        ],
        if (report.aiTips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _TipsCard(tips: report.aiTips),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Text(Strings.of(context).howToImprove, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 4),
        Text(Strings.of(context).coachingSuggestionsBasedOnYourProfile,
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 12),
        // Group suggestions by area so the SAME area (e.g. "Bio") shows as ONE
        // card with its points listed underneath, instead of duplicate cards.
        ..._groupByArea(report.suggestions).map((g) => _SuggestionGroupCard(group: g)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(Strings.of(context).reRunOptimizer),
          onPressed: _run,
        ),
      ],
    );
  }
}

/// AI coaching tips (e.g. "politely ask satisfied clients to leave a review").
class _TipsCard extends StatelessWidget {
  final List<String> tips;
  const _TipsCard({required this.tips});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.tips_and_updates_outlined, size: 16, color: c.gold),
          const SizedBox(width: 7),
          Text(Strings.of(context).coachingTips, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ]),
        const SizedBox(height: 10),
        ...tips.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: TextStyle(color: c.gold, fontSize: 13.5, height: 1.4)),
                Expanded(child: Text(t, style: TextStyle(color: c.ink, fontSize: 13, height: 1.4))),
              ]),
            )),
      ]),
    );
  }
}

/// The AI-rewritten bio (present only when the backend LLM ran). This is the ONE
/// thing that can be applied directly: "Use this bio" saves it to the profile in
/// one tap (no separate apply flow). The astrologer can also just copy it.
class _AiBioCard extends StatefulWidget {
  final String bio;
  const _AiBioCard({required this.bio});
  @override
  State<_AiBioCard> createState() => _AiBioCardState();
}

class _AiBioCardState extends State<_AiBioCard> {
  bool _saving = false;
  bool _applied = false;

  Future<void> _useBio() async {
    if (_saving || _applied) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = Strings.of(context);
    final api = context.read<AstrologerApi>();
    final session = context.read<SessionProvider>();
    try {
      final res = await api.updateMyProfile({'bio': widget.bio});
      // Reflect the saved bio in the in-memory profile immediately.
      try { session.applyServerProfile(res); } catch (_) {}
      if (!mounted) return;
      setState(() { _saving = false; _applied = true; });
      messenger.showSnackBar(SnackBar(content: Text(s.bioUpdatedOnYourProfile)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(s.couldNotUpdateBioPleaseTry)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.violet.withValues(alpha: 0.14), c.indigo.withValues(alpha: 0.10)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.violet.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 16, color: c.violet),
          const SizedBox(width: 7),
          Text(Strings.of(context).aiRewrittenBio, style: TextStyle(color: c.violet, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ]),
        const SizedBox(height: 10),
        Text(widget.bio, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 15),
            label: Text(Strings.of(context).copy),
            style: TextButton.styleFrom(foregroundColor: c.muted, minimumSize: const Size(0, 38)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.bio));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).bioCopied)));
            },
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_applied ? Icons.check : Icons.auto_fix_high, size: 16),
            label: Text(_applied ? Strings.of(context).appliedToProfile : Strings.of(context).useThisBio),
            style: FilledButton.styleFrom(backgroundColor: _applied ? c.green : c.violet, minimumSize: const Size(0, 38)),
            onPressed: (_saving || _applied) ? null : _useBio,
          ),
        ]),
      ]),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final OptimizerReport report;
  const _ScoreCard({required this.report});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final score = report.score;
    final col = score >= 85 ? c.green : (score >= 65 ? c.gold : c.red);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
      child: Row(children: [
        SizedBox(
          height: 84, width: 84,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              height: 84, width: 84,
              child: CircularProgressIndicator(value: score / 100, strokeWidth: 7, backgroundColor: c.line, valueColor: AlwaysStoppedAnimation(col)),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$score', style: TextStyle(color: c.ink, fontWeight: FontWeight.w900, fontSize: 26)),
              Text('/100', style: TextStyle(color: c.muted, fontSize: 10)),
            ]),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Strings.of(context).profileScore, style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(report.headline, style: TextStyle(color: c.ink, fontSize: 14, height: 1.35, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

/// One area's worth of suggestions, merged. Keeps every point but shares a
/// single header/icon and shows the highest impact across the grouped points.
class _SuggestionGroup {
  final String area;
  final IconData icon;
  final int impact; // max impact across the group's points
  final List<OptimizerSuggestion> points;
  _SuggestionGroup({required this.area, required this.icon, required this.impact, required this.points});
}

/// Group suggestions by `area`, preserving order (first-seen area first), so the
/// same area is one card. Within a group, points keep their given order.
List<_SuggestionGroup> _groupByArea(List<OptimizerSuggestion> suggestions) {
  final order = <String>[];
  final byArea = <String, List<OptimizerSuggestion>>{};
  for (final s in suggestions) {
    if (!byArea.containsKey(s.area)) { order.add(s.area); byArea[s.area] = []; }
    byArea[s.area]!.add(s);
  }
  return order.map((area) {
    final pts = byArea[area]!;
    final maxImpact = pts.fold<int>(0, (m, p) => p.impact > m ? p.impact : m);
    return _SuggestionGroup(area: area, icon: pts.first.icon, impact: maxImpact, points: pts);
  }).toList();
}

/// A read-only coaching card for ONE area. If the area has several points they
/// are listed underneath a single header (no duplicate area cards). Each point
/// shows its issue + the recommended fix.
class _SuggestionGroupCard extends StatelessWidget {
  final _SuggestionGroup group;
  const _SuggestionGroupCard({required this.group});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.ground2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            height: 38, width: 38,
            decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(group.icon, color: c.violet, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.area, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 14)),
              Row(children: [
                ...List.generate(5, (i) => Icon(i < group.impact ? Icons.bolt : Icons.bolt_outlined, size: 12, color: c.gold)),
                const SizedBox(width: 6),
                Text(Strings.of(context).impact, style: TextStyle(color: c.muted, fontSize: 10.5)),
              ]),
            ]),
          ),
        ]),
        // Each point under this area: issue + its fix, separated by a divider.
        for (var i = 0; i < group.points.length; i++) ...[
          if (i == 0) const SizedBox(height: 10) else Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: c.line),
          ),
          Text(group.points[i].issue, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.ground, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, size: 15, color: c.gold),
              const SizedBox(width: 8),
              Expanded(child: Text(group.points[i].fix, style: TextStyle(color: c.ink, fontSize: 13, height: 1.4))),
            ]),
          ),
        ],
      ]),
    );
  }
}
