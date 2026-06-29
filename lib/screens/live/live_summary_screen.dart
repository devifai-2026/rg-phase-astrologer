import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../theme/rg_colors.dart';

/// AI Live Summary — the recap shown when a live session ends.
class LiveSummaryScreen extends StatelessWidget {
  final LiveSummary summary;
  const LiveSummaryScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = Strings.of(context);
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          Icon(Icons.auto_awesome, color: c.violet, size: 20),
          const SizedBox(width: 8),
          Text(s.aiLiveSummary, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.done, style: TextStyle(color: c.red, fontWeight: FontWeight.w700))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            _stat(c, Icons.visibility, '${summary.peakViewers}', s.peakViewers, c.blue),
            const SizedBox(width: 10),
            _stat(c, Icons.help_outline, '${summary.totalQuestions}', s.questions, c.violet),
            const SizedBox(width: 10),
            _stat(c, Icons.bolt, '₹${summary.superchatEarnings}', s.superchats, c.gold),
          ]),
          const SizedBox(height: 22),

          Text(s.highlights, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          ...summary.highlights.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle_outline, size: 18, color: c.green),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.4))),
                ]),
              )),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.violet.withValues(alpha: 0.4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.tips_and_updates_outlined, size: 18, color: c.violet), const SizedBox(width: 8), Text(s.aiSuggestion, style: TextStyle(color: c.violet, fontWeight: FontWeight.w800, fontSize: 13))]),
              const SizedBox(height: 8),
              Text(summary.suggestedNextTopic, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.45)),
            ]),
          ),
          const SizedBox(height: 18),

          Text(s.promoteNext, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(s.rudraMallItemsTheAiMatched, style: TextStyle(color: c.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: summary.followUpProducts.map((p) => Chip(
                avatar: Icon(Icons.storefront, size: 16, color: c.gold),
                label: Text(p, style: TextStyle(color: c.ink, fontSize: 12.5)),
                backgroundColor: c.ground2,
                side: BorderSide(color: c.line),
              )).toList()),
          const SizedBox(height: 26),

          ElevatedButton.icon(
            icon: const Icon(Icons.share_outlined),
            label: Text(s.shareRecapWithFollowers),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.recapSharedWithYourFollowers)));
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _stat(RgColors c, IconData icon, String value, String label, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(children: [
            Icon(icon, color: tint, size: 22),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
          ]),
        ),
      );
}
