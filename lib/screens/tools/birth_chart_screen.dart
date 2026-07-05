import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// Birth Chart (D1 Lagna) — instant, VedicAstro-backed. Astrologer enters dob/
/// tob + birthplace (searched → lat/lon), and the D1 SVG renders inline. Re-run
/// with new details; recent charts are kept in an in-session history list.
class BirthChartScreen extends StatefulWidget {
  const BirthChartScreen({super.key});
  @override
  State<BirthChartScreen> createState() => _BirthChartScreenState();
}

class _HistoryEntry {
  final String label; // "12/08/1998 · 06:32 · Pune"
  final String svg;
  const _HistoryEntry(this.label, this.svg);
}

class _BirthChartScreenState extends State<BirthChartScreen> {
  final _placeCtrl = TextEditingController();
  DateTime? _dob;
  TimeOfDay? _tob;
  double? _lat;
  double? _lon;
  List<PlaceHit> _places = [];
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  String? _svg;
  final List<_HistoryEntry> _history = [];

  @override
  void dispose() {
    _placeCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  String get _dobStr => _dob == null ? '' : '${_two(_dob!.day)}/${_two(_dob!.month)}/${_dob!.year}';
  String get _tobStr => _tob == null ? '' : '${_two(_tob!.hour)}:${_two(_tob!.minute)}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final p = await showDatePicker(context: context, initialDate: _dob ?? DateTime(now.year - 25), firstDate: DateTime(1920), lastDate: now);
    if (p != null) setState(() => _dob = p);
  }

  Future<void> _pickTime() async {
    final p = await showTimePicker(context: context, initialTime: _tob ?? const TimeOfDay(hour: 6, minute: 30));
    if (p != null) setState(() => _tob = p);
  }

  void _onPlaceQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _places = []); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final res = await context.read<AstrologerApi>().searchPlaces(q.trim());
        if (mounted) setState(() => _places = res);
      } catch (_) { if (mounted) setState(() => _places = []); }
    });
  }

  Future<void> _run() async {
    final s = Strings.of(context);
    if (_dob == null || _tob == null) { setState(() => _error = s.enterBirthDetails); return; }
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final svg = await context.read<AstrologerApi>().birthChartSvg(dob: _dobStr, tob: _tobStr, lat: _lat, lon: _lon);
      if (!mounted) return;
      setState(() {
        _svg = svg;
        _loading = false;
        final label = '$_dobStr · $_tobStr${_placeCtrl.text.trim().isEmpty ? '' : ' · ${_placeCtrl.text.trim()}'}';
        _history.insert(0, _HistoryEntry(label, svg));
        if (_history.length > 10) _history.removeLast();
      });
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
    InputDecoration dec(String label, IconData icon) => InputDecoration(
          labelText: label, prefixIcon: Icon(icon, color: c.muted, size: 20), isDense: true,
          filled: true, fillColor: c.ground2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.gold)),
        );

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: c.ground, elevation: 0, title: Text(s.birthChart, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(children: [
            Expanded(child: InkWell(onTap: _pickDate, child: IgnorePointer(child: TextField(controller: TextEditingController(text: _dobStr), enabled: false, style: TextStyle(color: c.ink), decoration: dec(s.dateOfBirth, Icons.calendar_today_outlined))))),
            const SizedBox(width: 10),
            Expanded(child: InkWell(onTap: _pickTime, child: IgnorePointer(child: TextField(controller: TextEditingController(text: _tobStr), enabled: false, style: TextStyle(color: c.ink), decoration: dec(s.timeOfBirth, Icons.access_time))))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _placeCtrl, onChanged: _onPlaceQuery, style: TextStyle(color: c.ink), decoration: dec(s.birthPlace, Icons.place_outlined)),
          if (_places.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
              child: Column(children: _places.take(5).map((p) => ListTile(
                    dense: true, title: Text(p.name, style: TextStyle(color: c.ink, fontSize: 13)),
                    onTap: () { setState(() { _placeCtrl.text = p.name; _lat = p.lat; _lon = p.lon; _places = []; }); FocusScope.of(context).unfocus(); },
                  )).toList()),
            ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: c.red, minimumSize: const Size.fromHeight(50)),
            onPressed: _loading ? null : _run,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.grid_on_rounded),
            label: Text(_loading ? '…' : (_svg == null ? s.generateChart : s.regenerate), style: const TextStyle(fontWeight: FontWeight.w800)),
          )),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: c.red, fontSize: 13))],
          if (_svg != null) ...[
            const SizedBox(height: 20),
            _chartBox(c, _svg!),
          ],
          if (_history.length > 1) ...[
            const SizedBox(height: 22),
            Text(s.history, style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ..._history.skip(_svg == null ? 0 : 1).map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => setState(() => _svg = h.svg),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                      child: Row(children: [
                        Icon(Icons.history, size: 18, color: c.muted),
                        const SizedBox(width: 10),
                        Expanded(child: Text(h.label, style: TextStyle(color: c.ink, fontSize: 13))),
                        Icon(Icons.chevron_right, size: 18, color: c.muted),
                      ]),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // White-background box so the black-stroke provider SVG is always visible
  // (the app theme may be dark).
  Widget _chartBox(RgColors c, String svg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
        child: AspectRatio(
          aspectRatio: 1,
          child: SvgPicture.string(svg, fit: BoxFit.contain, placeholderBuilder: (_) => const Center(child: CircularProgressIndicator())),
        ),
      );
}
