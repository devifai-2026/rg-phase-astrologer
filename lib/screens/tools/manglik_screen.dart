import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/birth_details_form.dart';

/// Manglik (Mangal) Dosha check for the astrologer — instant, VedicAstro-backed.
/// One birth-detail form → present/absent (Mars/Saturn/Rahu-Ketu), % + factors.
class ManglikScreen extends StatefulWidget {
  const ManglikScreen({super.key});
  @override
  State<ManglikScreen> createState() => _ManglikScreenState();
}

class _ManglikScreenState extends State<ManglikScreen> {
  BirthDetails? _birth;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _r;

  Future<void> _run() async {
    final s = Strings.of(context);
    if (_birth == null || !_birth!.isComplete) { setState(() => _error = s.enterBirthDetails); return; }
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final res = await context.read<AstrologerApi>().manglik(dob: _birth!.dob, tob: _birth!.tob, lat: _birth!.lat, lon: _birth!.lon);
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
      appBar: AppBar(backgroundColor: c.ground, elevation: 0, title: Text(s.manglikDosh, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          BirthDetailsForm(title: s.manglikDosh, showName: false, onChanged: (b) => _birth = b),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: c.red, minimumSize: const Size.fromHeight(50)),
            onPressed: _loading ? null : _run,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.search),
            label: Text(_loading ? '…' : s.checkManglik, style: const TextStyle(fontWeight: FontWeight.w800)),
          )),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: c.red, fontSize: 13))],
          if (_r != null) ...[const SizedBox(height: 20), _result(c, _r!)],
        ],
      ),
    );
  }

  Widget _result(RgColors c, Map<String, dynamic> r) {
    final byMars = r['manglik_by_mars'] == true;
    final bySaturn = r['manglik_by_saturn'] == true;
    final byRahuKetu = r['manglik_by_rahuketu'] == true;
    final present = byMars || bySaturn || byRahuKetu;
    final score = (r['score'] as num?)?.toDouble() ?? 0;
    final summary = (r['bot_response'] ?? '').toString();
    final factors = ((r['factors'] as List?) ?? const []).map((e) => e.toString()).toList();
    final tint = present ? c.red : c.green;
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(18), border: Border.all(color: tint.withValues(alpha: 0.5))),
        child: Column(children: [
          Icon(present ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: tint, size: 40),
          const SizedBox(height: 8),
          Text(present ? 'Manglik' : 'Non-Manglik', style: TextStyle(color: tint, fontSize: 22, fontWeight: FontWeight.w900)),
          if (score > 0) ...[const SizedBox(height: 4), Text('${score % 1 == 0 ? score.toInt() : score}%', style: TextStyle(color: c.muted, fontSize: 14, fontWeight: FontWeight.w700))],
          if (summary.isNotEmpty) ...[const SizedBox(height: 10), Text(summary, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.4))],
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _flag(c, 'Mars', byMars), const SizedBox(width: 8),
        _flag(c, 'Saturn', bySaturn), const SizedBox(width: 8),
        _flag(c, 'Rahu-Ketu', byRahuKetu),
      ]),
      if (factors.isNotEmpty) ...[
        const SizedBox(height: 14),
        ...factors.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.circle, size: 7, color: c.gold),
                  const SizedBox(width: 10),
                  Expanded(child: Text(f, style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.4))),
                ]),
              ),
            )),
      ],
    ]);
  }

  Widget _flag(RgColors c, String label, bool on) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: on ? c.red.withValues(alpha: 0.1) : c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? c.red.withValues(alpha: 0.4) : c.line)),
          child: Column(children: [
            Icon(on ? Icons.close : Icons.check, size: 16, color: on ? c.red : c.green),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
