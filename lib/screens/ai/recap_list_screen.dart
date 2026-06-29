import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/recap_models.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/slide_route.dart';
import 'recap_review_screen.dart';

/// The astrologer's queue of AI chat recaps awaiting review (Feature 1).
/// Real backend data — replaces the MockAi chat-summary demo path.
class RecapListScreen extends StatefulWidget {
  /// When opened from a notification tap we may already know the recap id — jump
  /// straight into its review screen once the list loads.
  final String? openRecapId;
  const RecapListScreen({super.key, this.openRecapId});

  @override
  State<RecapListScreen> createState() => _RecapListScreenState();
}

class _RecapListScreenState extends State<RecapListScreen> {
  List<Recap> _items = const [];
  bool _loading = true;
  String? _error;
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<AstrologerApi>().listRecaps(status: 'pending');
      if (!mounted) return;
      setState(() {
        _items = _dedupeBySession(items);
        _loading = false;
      });
      _maybeJump();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = Strings.of(context).couldNotLoadRecaps; _loading = false; });
    }
  }

  // Collapse any recaps that belong to the SAME session into one card. The
  // backend already keeps one recap per session (unique index), so this is a
  // safety net for older/duplicate data — the first (newest, list is sorted
  // desc) wins, and the seeker never sees two cards for a single consultation.
  List<Recap> _dedupeBySession(List<Recap> items) {
    final seen = <String>{};
    final out = <Recap>[];
    for (final r in items) {
      final key = r.sessionId.isNotEmpty ? r.sessionId : r.id;
      if (seen.add(key)) out.add(r);
    }
    return out;
  }

  // Deep-link: open the named recap once, if it's in the queue.
  void _maybeJump() {
    if (_jumped || widget.openRecapId == null) return;
    _jumped = true;
    final exists = _items.any((r) => r.id == widget.openRecapId);
    if (exists) _openReview(widget.openRecapId!);
  }

  Future<void> _openReview(String recapId) async {
    final changed = await Navigator.of(context).push<bool>(
      slideRoute(RecapReviewScreen(recapId: recapId)),
    );
    if (changed == true) _load(); // reviewed → drop it from the pending queue
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
          Text(Strings.of(context).aiRecaps, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(c),
      ),
    );
  }

  Widget _buildBody(RgColors c) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _centered(c, Icons.error_outline, _error!, action: TextButton(onPressed: _load, child: const Text('Retry')));
    }
    if (_items.isEmpty) {
      return _centered(c, Icons.inbox_outlined,
          Strings.of(context).noRecapsToReviewWhenA);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _RecapTile(recap: _items[i], onTap: () => _openReview(_items[i].id)),
    );
  }

  Widget _centered(RgColors c, IconData icon, String text, {Widget? action}) {
    return ListView(
      // ListView so RefreshIndicator works even when empty.
      padding: const EdgeInsets.fromLTRB(28, 120, 28, 28),
      children: [
        Icon(icon, size: 48, color: c.muted),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 12), Center(child: action)],
      ],
    );
  }
}

class _RecapTile extends StatelessWidget {
  final Recap recap;
  final VoidCallback onTap;
  const _RecapTile({required this.recap, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final topics = recap.keyTopics.take(3).toList();
    final sugCount = recap.suggestions.length;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.ground2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.summarize_outlined, size: 16, color: c.violet),
            const SizedBox(width: 6),
            // Stable title for every recap so they read as one consistent type
            // (not two different-looking cards). The AI sentiment, if any, shows
            // as a small sub-label chip below, not as the title.
            Text(Strings.of(context).consultationRecap, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const Spacer(),
            Icon(Icons.chevron_right, color: c.muted, size: 20),
          ]),
          if (recap.sentiment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(recap.sentiment, style: TextStyle(color: c.violet, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Text(
            recap.summary.isEmpty ? Strings.of(context).tapToReviewTheAiSummary : recap.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
          ),
          if (topics.isNotEmpty || sugCount > 0) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ...topics.map((t) => _pill(c, t)),
              if (sugCount > 0)
                _pill(c, '$sugCount ${sugCount == 1 ? 'suggestion' : 'suggestions'}', accent: true),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _pill(RgColors c, String text, {bool accent = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: accent ? c.redSoft : c.ground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent ? c.red : c.line),
        ),
        child: Text(text, style: TextStyle(color: accent ? c.red : c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
      );
}
