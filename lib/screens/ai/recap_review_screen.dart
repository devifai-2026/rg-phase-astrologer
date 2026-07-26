import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/recap_models.dart';
import '../../theme/rg_colors.dart';

/// Review one AI chat recap (Feature 1). READ-ONLY: the astrologer sees the AI
/// summary, sentiment, key topics, suggested products and the proposed reminders
/// exactly as generated — nothing is editable. They give a single verdict with a
/// thumbs-up (approve & share with the seeker) or thumbs-down (discard).
///
/// Pops `true` when the recap was approved or discarded (so the queue refreshes).
class RecapReviewScreen extends StatefulWidget {
  final String recapId;
  const RecapReviewScreen({super.key, required this.recapId});

  @override
  State<RecapReviewScreen> createState() => _RecapReviewScreenState();
}

class _RecapReviewScreenState extends State<RecapReviewScreen> {
  Recap? _recap;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AstrologerApi>().getRecap(widget.recapId);
      if (!mounted) return;
      setState(() {
        _recap = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = Strings.of(context).couldNotLoadThisRecap; _loading = false; });
    }
  }

  /// Thumbs up → approve & share with the seeker. All AI suggestions are kept
  /// (read-only flow — no per-item toggle), and the reminders go as-generated.
  Future<void> _approve() async {
    final r = _recap;
    if (r == null) return;
    final s = Strings.of(context);
    setState(() => _busy = true);
    try {
      final api = context.read<AstrologerApi>();
      final keep = r.suggestions.map((s) => s.id).toList(); // keep all (no editing)
      await api.approveRecap(r.id, keepSuggestionIds: keep);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.recapSharedWithTheSeeker)),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _toast(e.message);
      setState(() => _busy = false);
    } catch (_) {
      _toast(s.couldNotPublishPleaseTryAgain);
      setState(() => _busy = false);
    }
  }

  /// Thumbs down → discard (the seeker never sees it).
  Future<void> _reject() async {
    final r = _recap;
    if (r == null) return;
    final api = context.read<AstrologerApi>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.of(context).discardThisRecap),
        content: Text(Strings.of(context).theSeekerWonTSeeIt),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Strings.of(context).cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(Strings.of(context).discard)),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final s = Strings.of(context);
    setState(() => _busy = true);
    try {
      await api.rejectRecap(r.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _toast(s.couldNotDiscardPleaseTryAgain);
      setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.auto_awesome, color: c.violet, size: 19),
          const SizedBox(width: 8),
          Text(Strings.of(context).consultationRecap, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: c.muted)))
              : _buildView(c, _recap!),
      bottomNavigationBar: (_loading || _error != null) ? null : _buildActions(c),
    );
  }

  Widget _buildView(RgColors c, Recap r) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (r.generatedByMock)
          _banner(c, Strings.of(context).aiIsInDemoModeConfigure),

        // Sentiment (read-only).
        if (r.sentiment.isNotEmpty) ...[
          Text(Strings.of(context).seekerSentiment, style: _label(c)),
          const SizedBox(height: 6),
          _readBox(c, r.sentiment),
          const SizedBox(height: 16),
        ],

        // Topics (read-only chips).
        if (r.keyTopics.isNotEmpty) ...[
          Text(Strings.of(context).keyTopics, style: _label(c)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ...r.keyTopics.map((t) => Chip(
                  label: Text(t, style: TextStyle(color: c.ink, fontSize: 12)),
                  backgroundColor: c.ground2,
                  side: BorderSide(color: c.line),
                )),
          ]),
          const SizedBox(height: 16),
        ],

        // Summary (read-only).
        Text(Strings.of(context).summary, style: _label(c)),
        const SizedBox(height: 6),
        _readBox(c, r.summary.isEmpty ? Strings.of(context).noSummaryWasGenerated : r.summary),
        const SizedBox(height: 20),

        // Suggested products (read-only — no toggles).
        Row(children: [
          Text(Strings.of(context).suggestedProducts, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          if (r.suggestions.isNotEmpty)
            Text('${r.suggestions.length}', style: TextStyle(color: c.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 4),
        Text(
          r.suggestions.isEmpty
              ? Strings.of(context).theAiDidnTSuggestAny
              : Strings.of(context).theseAreSharedWithTheSeeker,
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...r.suggestions.map((s) => _SuggestionCard(s: s)),

        // Reminders (read-only content view — no toggle, no edit, no pickers).
        if (r.reminders.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.notifications_active_outlined, color: c.ink, size: 18),
            const SizedBox(width: 6),
            Text(Strings.of(context).reminders, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 4),
          Text(
            Strings.of(context).followUpsTheAiWillSchedule,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...r.reminders.map((m) => _ReminderCard(m: m)),
        ],
      ],
    );
  }

  Widget _buildActions(RgColors c) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(children: [
          // Thumbs DOWN → discard.
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.thumb_down_alt_outlined),
              label: Text(Strings.of(context).discard, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.muted,
                side: BorderSide(color: c.line),
                minimumSize: const Size(0, 52),
              ),
              onPressed: _busy ? null : _reject,
            ),
          ),
          const SizedBox(width: 12),
          // Thumbs UP → approve & share.
          Expanded(
            child: ElevatedButton.icon(
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.thumb_up_alt_outlined),
              // Constrained to ONE line. This is a half-width button with a
              // leading icon, and the label runs 15 chars in English and 24-27 in
              // Hindi/Bengali — it wrapped to two lines and stretched the button.
              label: Text(
                _busy ? Strings.of(context).sharing : Strings.of(context).approveShare,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 52),
              ),
              onPressed: _busy ? null : _approve,
            ),
          ),
        ]),
      ),
    );
  }

  TextStyle _label(RgColors c) => TextStyle(color: c.violet, fontWeight: FontWeight.w800, fontSize: 13);

  Widget _readBox(RgColors c, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
        child: Text(text, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.5)),
      );

  Widget _banner(RgColors c, String text) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.gold.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: c.gold),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: c.ink, fontSize: 12.5))),
        ]),
      );
}

/// Read-only product suggestion card (no include/exclude toggle).
class _SuggestionCard extends StatelessWidget {
  final RecapSuggestion s;
  const _SuggestionCard({required this.s});

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
        Text(s.title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
        if (s.reason != null && s.reason!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(s.reason!, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.ground, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
          child: Row(children: [
            _thumb(c),
            const SizedBox(width: 10),
            Expanded(child: Text(s.productName, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: 13))),
            Text('₹${s.price}', style: TextStyle(color: c.gold, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  Widget _thumb(RgColors c) {
    final img = s.image;
    if (img != null && img.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.network(img, height: 34, width: 34, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(c)),
      );
    }
    return _placeholder(c);
  }

  Widget _placeholder(RgColors c) => Container(
        height: 34,
        width: 34,
        decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
        child: Icon(Icons.inventory_2_outlined, color: c.gold, size: 18),
      );
}

/// Read-only reminder card. Mantra reminders are a recurring 14-day daily course
/// (fired 5 min before [timeOfDay]); event reminders are one-off on a [date].
/// Pure content view — nothing here is editable or toggleable.
class _ReminderCard extends StatelessWidget {
  final RecapReminder m;
  const _ReminderCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final accent = m.isMantra ? c.violet : c.blue;
    final explainer = m.isMantra
        ? 'Daily reminder, 5 min before ${m.timeOfDay ?? 'the set time'}, for 14 days'
        : 'One-time reminder on ${m.date ?? 'the set date'}';
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
            height: 30,
            width: 30,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
            child: Icon(m.isMantra ? Icons.self_improvement : Icons.event_outlined, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              m.isMantra ? Strings.of(context).mantraReminder : Strings.of(context).eventReminder,
              style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.2),
            ),
          ),
          // The mantra time / event date, shown as a plain (non-tappable) chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: c.ground, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.isMantra ? Icons.schedule : Icons.calendar_today_outlined, size: 13, color: c.gold),
              const SizedBox(width: 5),
              Text(
                m.isMantra ? (m.timeOfDay ?? '—') : (m.date ?? '—'),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(m.title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
        if (m.reason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(m.reason, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.info_outline, size: 14, color: c.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(explainer, style: TextStyle(color: c.muted, fontSize: 12))),
        ]),
      ]),
    );
  }
}
