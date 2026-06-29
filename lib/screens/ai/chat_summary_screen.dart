import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../providers/session_provider.dart'; // ServiceKindX (.label)
import '../../services/mock_ai.dart';
import '../../theme/rg_colors.dart';

/// AI summary of one consultation: key topics, narrative summary, sentiment,
/// and AI-suggested remedies. The astrologer confirms / edits each remedy and
/// can swap the linked Rudra Mall product, then publishes to the user app.
class ChatSummaryScreen extends StatefulWidget {
  final ChatSummary summary;
  const ChatSummaryScreen({super.key, required this.summary});

  @override
  State<ChatSummaryScreen> createState() => _ChatSummaryScreenState();
}

class _ChatSummaryScreenState extends State<ChatSummaryScreen> {
  late final ChatSummary s = widget.summary;

  void _publish() {
    setState(() => s.published = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Strings.of(context).publishedSRemediesWhereRR(s.remedies.where((r) => r.confirmed).length))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final confirmedCount = s.remedies.where((r) => r.confirmed).length;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.auto_awesome, color: c.violet, size: 19),
          const SizedBox(width: 8),
          Text(Strings.of(context).aiSummary, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Session header.
          Row(children: [
            CircleAvatar(radius: 20, backgroundColor: c.redSoft, child: Text(s.userName[0], style: TextStyle(color: c.red, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.userName, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${s.kind.label} · ${s.when}', style: TextStyle(color: c.muted, fontSize: 12.5)),
            ])),
            if (s.published)
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: c.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)), child: Text(Strings.of(context).published, style: TextStyle(color: c.green, fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 18),

          // Sentiment + topics.
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(avatar: Icon(Icons.mood, size: 15, color: c.gold), label: Text(s.sentiment, style: TextStyle(color: c.ink, fontSize: 12)), backgroundColor: c.ground2, side: BorderSide(color: c.line)),
            ...s.keyTopics.map((t) => Chip(label: Text(t, style: TextStyle(color: c.ink, fontSize: 12)), backgroundColor: c.ground2, side: BorderSide(color: c.line))),
          ]),
          const SizedBox(height: 18),

          // Narrative summary.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.summarize_outlined, size: 16, color: c.violet), const SizedBox(width: 6), Text(Strings.of(context).summary, style: TextStyle(color: c.violet, fontWeight: FontWeight.w800, fontSize: 13))]),
              const SizedBox(height: 8),
              Text(s.summary, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 20),

          // Remedies.
          Row(children: [
            Text(Strings.of(context).suggestedRemedies, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            Text(Strings.of(context).confirmedcountSRemediesLengthConfirmed(confirmedCount, s.remedies.length), style: TextStyle(color: c.muted, fontSize: 12.5)),
          ]),
          const SizedBox(height: 4),
          Text(Strings.of(context).confirmOrEditBeforePublishingTo, style: TextStyle(color: c.muted, fontSize: 12)),
          const SizedBox(height: 12),
          ...s.remedies.asMap().entries.map((e) => _RemedyCard(
                remedy: e.value,
                onChanged: () => setState(() {}),
              )),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            icon: const Icon(Icons.publish),
            label: Text(confirmedCount == 0 ? Strings.of(context).confirmARemedyToPublish : Strings.of(context).publishToUserApp),
            onPressed: confirmedCount == 0 ? null : _publish,
          ),
        ],
      ),
    );
  }
}

class _RemedyCard extends StatelessWidget {
  final RemedySuggestion remedy;
  final VoidCallback onChanged;
  const _RemedyCard({required this.remedy, required this.onChanged});

  void _edit(BuildContext context) {
    final c = context.rg;
    final titleCtrl = TextEditingController(text: remedy.title);
    final detailCtrl = TextEditingController(text: remedy.detail);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.ground2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(Strings.of(context).editRemedy, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 14),
            TextField(controller: titleCtrl, decoration: InputDecoration(labelText: Strings.of(context).remedy)),
            const SizedBox(height: 12),
            TextField(controller: detailCtrl, maxLines: 3, decoration: InputDecoration(labelText: Strings.of(context).detailInstructions)),
            const SizedBox(height: 14),
            Text(Strings.of(context).linkARudraMallProductOptional, style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _prodChip(c, null, remedy, setSheet),
              ...MockAi.mall.map((p) => _prodChip(c, p, remedy, setSheet)),
            ]),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () {
              remedy.title = titleCtrl.text.trim();
              remedy.detail = detailCtrl.text.trim();
              Navigator.of(ctx).pop();
              onChanged();
            }, child: Text(Strings.of(context).save2))),
          ]),
        );
      }),
    );
  }

  static Widget _prodChip(RgColors c, MallProduct? p, RemedySuggestion remedy, void Function(void Function()) setSheet) {
    final selected = remedy.product?.id == p?.id;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setSheet(() => remedy.product = p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.redSoft : c.ground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c.red : c.line, width: selected ? 1.3 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(p?.icon ?? Icons.block, size: 15, color: p?.color ?? c.muted),
          const SizedBox(width: 6),
          Text(p?.name ?? 'No product', style: TextStyle(color: selected ? c.red : c.ink, fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final p = remedy.product;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: remedy.confirmed ? c.green.withValues(alpha: 0.08) : c.ground2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: remedy.confirmed ? c.green.withValues(alpha: 0.5) : c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(remedy.title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5))),
          if (remedy.confirmed) Icon(Icons.check_circle, color: c.green, size: 20),
        ]),
        const SizedBox(height: 6),
        Text(remedy.detail, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
        if (p != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.ground, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
            child: Row(children: [
              Container(height: 34, width: 34, decoration: BoxDecoration(color: p.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)), child: Icon(p.icon, color: p.color, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text(p.name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: 13))),
              Text('₹${p.price}', style: TextStyle(color: c.gold, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(Strings.of(context).edit),
            style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size(0, 38)),
            onPressed: () => _edit(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: remedy.confirmed
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: c.muted, side: BorderSide(color: c.line), minimumSize: const Size(0, 38)),
                    onPressed: () { remedy.confirmed = false; onChanged(); },
                    child: Text(Strings.of(context).unconfirm),
                  )
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(backgroundColor: c.green.withValues(alpha: 0.15), foregroundColor: c.green, minimumSize: const Size(0, 38)),
                    onPressed: () { remedy.confirmed = true; onChanged(); },
                    child: Text(Strings.of(context).confirm),
                  ),
          ),
        ]),
      ]),
    );
  }
}
