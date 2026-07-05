import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/birth_details_form.dart';

/// Marriage matching (aggregate match) for the astrologer — instant, VedicAstro.
/// Two birth-detail forms → Guna Milan + doshas + overall score. Used by the
/// Matrimony + Kundli Matching home tools.
class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key});
  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  BirthDetails? _girl;
  BirthDetails? _boy;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _r;

  Map<String, dynamic> _birth(BirthDetails b) => {
        'dob': b.dob, 'tob': b.tob, if (b.lat != null) 'lat': b.lat, if (b.lon != null) 'lon': b.lon,
      };

  Future<void> _run() async {
    final s = Strings.of(context);
    if (_girl == null || _boy == null || !_girl!.isComplete || !_boy!.isComplete) {
      setState(() => _error = s.fillBothPartners);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final res = await context.read<AstrologerApi>().matching(girl: _birth(_girl!), boy: _birth(_boy!));
      if (!mounted) return;
      setState(() { _r = res; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.statusCode == null ? s.couldNotConnectTryAgain : e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = s.somethingWentWrong; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = Strings.of(context);
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: c.ground, elevation: 0, title: Text(s.compatibility, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          BirthDetailsForm(title: s.partner1, showName: true, onChanged: (b) => _girl = b),
          const SizedBox(height: 12),
          BirthDetailsForm(title: s.partner2, showName: true, onChanged: (b) => _boy = b),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: c.red, minimumSize: const Size.fromHeight(50)),
            onPressed: _loading ? null : _run,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.favorite),
            label: Text(_loading ? '…' : s.checkCompatibility, style: const TextStyle(fontWeight: FontWeight.w800)),
          )),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: c.red, fontSize: 13))],
          if (_r != null) ...[const SizedBox(height: 20), _result(c, s, _r!)],
        ],
      ),
    );
  }

  Widget _result(RgColors c, Strings s, Map<String, dynamic> r) {
    final score = ((r['score'] as num?)?.toInt() ?? 0).clamp(0, 100);
    final tint = score >= 60 ? c.green : score >= 35 ? c.gold : c.red;
    final ashtakoot = (r['ashtakoot_score'] ?? '').toString();
    final dashkoot = (r['dashkoot_score'] ?? '').toString();
    final summary = (r['bot_response'] ?? r['extended_response'] ?? '').toString();
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(18), border: Border.all(color: tint.withValues(alpha: 0.5))),
        child: Column(children: [
          Text(s.overallScore, style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text('$score', style: TextStyle(color: tint, fontSize: 46, fontWeight: FontWeight.w900, height: 1)),
          Text('/ 100', style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: score / 100, minHeight: 8, backgroundColor: c.line, valueColor: AlwaysStoppedAnimation(tint))),
          if (summary.isNotEmpty) ...[const SizedBox(height: 12), Text(summary, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.4))],
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        if (ashtakoot.isNotEmpty) Expanded(child: _mini(c, 'Ashtakoot', ashtakoot)),
        if (ashtakoot.isNotEmpty && dashkoot.isNotEmpty) const SizedBox(width: 10),
        if (dashkoot.isNotEmpty) Expanded(child: _mini(c, 'Dashkoot', dashkoot)),
      ]),
      const SizedBox(height: 12),
      ..._doshaRows(c, r),
    ]);
  }

  Widget _mini(RgColors c, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(children: [
          Text(value, style: TextStyle(color: c.gold, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );

  List<Widget> _doshaRows(RgColors c, Map<String, dynamic> r) {
    const keys = ['mangaldosh', 'pitradosh', 'kaalsarpdosh', 'manglikdosh_saturn', 'manglikdosh_rahuketu'];
    final rows = <Widget>[];
    for (final k in keys) {
      final v = r[k];
      if (v is String && v.trim().isNotEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 15, color: c.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(v, style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.4))),
            ]),
          ),
        ));
      }
    }
    return rows;
  }
}
