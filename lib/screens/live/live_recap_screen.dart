import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/live_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../feedback/service_feedback_sheet.dart';

/// Full recap analytics for one broadcast, backed by GET /live/:id/detail:
///   • audience metrics (peak viewers, joins, comments, gifts)
///   • the AI-MODERATOR scorecard — how many spam/contact comments it blocked
///     and how many abusive/spam comments it muted (so the astrologer sees the
///     value the AI added)
///   • every POLL with its question + per-option vote tallies
///   • the cached AI recap (if generated)
///
/// Shown both when a live ends and when tapping a past-live card. After a live
/// ends ([showFeedback] true) it offers the multi-dimension feedback sheet.
class LiveRecapScreen extends StatefulWidget {
  final String liveSessionId;
  final bool showFeedback; // true right after a live ends (prompt for feedback)
  const LiveRecapScreen({super.key, required this.liveSessionId, this.showFeedback = false});

  @override
  State<LiveRecapScreen> createState() => _LiveRecapScreenState();
}

class _LiveRecapScreenState extends State<LiveRecapScreen> {
  LiveDetail? _d;
  String? _error;
  bool _feedbackDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<LiveApi>().detail(widget.liveSessionId);
      if (!mounted) return;
      setState(() => _d = d);
      // Right after a live ends, gently prompt for feedback once the recap shows.
      if (widget.showFeedback && !_feedbackDone) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _askFeedback());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _askFeedback() async {
    if (_feedbackDone || !mounted) return;
    _feedbackDone = true;
    await ServiceFeedbackSheet.show(context, kind: 'live', sourceId: widget.liveSessionId, serviceType: 'live');
  }

  String _dur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        elevation: 0,
        title: Text(Strings.of(context).liveRecap, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(Strings.of(context).done, style: TextStyle(color: c.red, fontWeight: FontWeight.w700))),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.muted))))
          : _d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(c, _d!),
    );
  }

  Widget _body(RgColors c, LiveDetail d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        if (d.title.isNotEmpty)
          Text(d.title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
        if (d.topic.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(d.topic, style: TextStyle(color: c.muted, fontSize: 13)),
        ],
        const SizedBox(height: 16),

        // Audience metrics.
        Row(children: [
          _stat(c, Icons.timer_outlined, _dur(d.durationSec), Strings.of(context).duration, c.blue),
          const SizedBox(width: 10),
          _stat(c, Icons.visibility, '${d.peakViewers}', Strings.of(context).peakViewers, c.violet),
          const SizedBox(width: 10),
          _stat(c, Icons.login, '${d.totalJoins}', Strings.of(context).totalJoins, c.green),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _stat(c, Icons.chat_bubble_outline, '${d.commentCount}', Strings.of(context).comments, c.blue),
          const SizedBox(width: 10),
          _stat(c, Icons.card_giftcard, '${d.giftCount}', Strings.of(context).gifts2, c.gold),
          const SizedBox(width: 10),
          _stat(c, Icons.bolt, '₹${d.superchatTotal}', Strings.of(context).earned, c.gold),
        ]),
        const SizedBox(height: 22),

        // ── AI moderator scorecard ──
        _section(c, Icons.shield_moon_outlined, Strings.of(context).aiModerator2, c.violet),
        const SizedBox(height: 4),
        Text(Strings.of(context).whatTheAiKeptYourLive, style: TextStyle(color: c.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        Row(children: [
          _modCard(c, Icons.link_off, '${d.blockedCount}', Strings.of(context).spamContactLinksRemoved, c.red),
          const SizedBox(width: 10),
          _modCard(c, Icons.block, '${d.mutedCount}', Strings.of(context).abusiveSpamMessagesMuted, c.red),
          const SizedBox(width: 10),
          _modCard(c, Icons.verified_outlined, '${d.shownCount}', Strings.of(context).cleanCommentsShown, c.green),
        ]),
        if (d.moderationNote.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.violet.withValues(alpha: 0.35))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome, size: 16, color: c.violet),
              const SizedBox(width: 8),
              Expanded(child: Text(d.moderationNote, style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.4))),
            ]),
          ),
        ],
        const SizedBox(height: 22),

        // ── Polls + voting results ──
        _section(c, Icons.poll_outlined, Strings.of(context).pollsResults, c.gold),
        const SizedBox(height: 4),
        Text(d.polls.isEmpty ? Strings.of(context).noPollsRanInThisLive : '${d.polls.length} poll${d.polls.length == 1 ? '' : 's'} · AI-generated every 5 min', style: TextStyle(color: c.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        ...d.polls.map((p) => _pollCard(c, p)),

        // ── AI recap (if cached) ──
        if (d.aiSummary.isNotEmpty) ...[
          const SizedBox(height: 12),
          _section(c, Icons.summarize_outlined, Strings.of(context).aiRecap, c.blue),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Text(d.aiSummary, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.5)),
          ),
        ],

        const SizedBox(height: 24),
        // Manual entry point to the feedback sheet (also auto-prompted on end).
        OutlinedButton.icon(
          icon: const Icon(Icons.rate_review_outlined),
          label: Text(_feedbackDone ? Strings.of(context).editYourFeedback : Strings.of(context).rateThisLiveSession),
          style: OutlinedButton.styleFrom(foregroundColor: c.red, side: BorderSide(color: c.red), padding: const EdgeInsets.symmetric(vertical: 13)),
          onPressed: () => ServiceFeedbackSheet.show(context, kind: 'live', sourceId: widget.liveSessionId, serviceType: 'live')
              .then((v) { if (v == true) setState(() => _feedbackDone = true); }),
        ),
      ],
    );
  }

  Widget _section(RgColors c, IconData icon, String title, Color tint) => Row(children: [
        Icon(icon, color: tint, size: 20),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
      ]);

  Widget _stat(RgColors c, IconData icon, String value, String label, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: 7),
            Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: c.muted, fontSize: 10.5)),
          ]),
        ),
      );

  Widget _modCard(RgColors c, IconData icon, String value, String label, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: 7),
            Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w900, fontSize: 19)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 10.5, height: 1.25)),
          ]),
        ),
      );

  Widget _pollCard(RgColors c, LivePollResult p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(Strings.of(context).pollPNo(p.no), style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          if (p.source == 'ai')
            Row(children: [Icon(Icons.auto_awesome, size: 12, color: c.violet), const SizedBox(width: 3), Text(Strings.of(context).ai, style: TextStyle(color: c.violet, fontSize: 10.5, fontWeight: FontWeight.w700))]),
          const Spacer(),
          Text('${p.totalVotes} vote${p.totalVotes == 1 ? '' : 's'}', style: TextStyle(color: c.muted, fontSize: 11.5)),
        ]),
        const SizedBox(height: 10),
        Text(p.question, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 12),
        ...p.options.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(o.text, style: TextStyle(color: c.ink, fontSize: 12.5))),
                  Text('${o.pct}%  ·  ${o.votes}', style: TextStyle(color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: o.pct / 100.0,
                    minHeight: 7,
                    backgroundColor: c.line,
                    valueColor: AlwaysStoppedAnimation(c.gold),
                  ),
                ),
              ]),
            )),
      ]),
    );
  }
}
