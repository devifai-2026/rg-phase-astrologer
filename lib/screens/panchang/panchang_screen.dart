import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/panchang_api.dart';
import '../../i18n/strings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rg_colors.dart';

/// Daily Panchang for the astrologer app. Same content as the user app (shared
/// backend `/panchang`). This app has no location plugin, so it uses a fixed
/// default location (New Delhi); panchang varies little across nearby places.
class PanchangScreen extends StatefulWidget {
  const PanchangScreen({super.key});
  @override
  State<PanchangScreen> createState() => _PanchangScreenState();
}

// Fixed default location (New Delhi) — the astrologer app has no geolocator.
const _defaultLat = 28.6139;
const _defaultLon = 77.2090;

class _PanchangScreenState extends State<PanchangScreen> {
  int _dayOffset = 0;
  late String _lang;

  bool _loading = true;
  String? _error;
  Panchang? _data;

  @override
  void initState() {
    super.initState();
    _lang = context.read<SettingsProvider>().effectiveLangCode;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _dateStr {
    final d = DateTime.now().add(Duration(days: _dayOffset));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await context.read<PanchangApi>().daily(date: _dateStr, lat: _defaultLat, lon: _defaultLon, lang: _lang);
      if (!mounted) return;
      setState(() {
        _data = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Strings.of(context).couldNotLoadPanchang;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        elevation: 0,
        foregroundColor: c.ink,
        title: Text(t.dailyPanchang, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: t.language, onPressed: _pickLanguage, icon: Icon(Icons.translate_rounded, color: c.gold)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _daySegment(c, t),
          ),
          Expanded(child: _body(c, t)),
        ],
      ),
    );
  }

  Widget _daySegment(RgColors c, Strings t) => SegmentedButton<int>(
        segments: [
          ButtonSegment(value: -1, label: Text(t.yesterday)),
          ButtonSegment(value: 0, label: Text(t.today)),
          ButtonSegment(value: 1, label: Text(t.tomorrow)),
        ],
        selected: {_dayOffset},
        showSelectedIcon: false,
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.muted),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.red : c.ground2),
          side: WidgetStatePropertyAll(BorderSide(color: c.line)),
        ),
        onSelectionChanged: (s) {
          setState(() => _dayOffset = s.first);
          _load();
        },
      );

  Widget _body(RgColors c, Strings t) {
    if (_loading) return Center(child: CircularProgressIndicator(color: c.red));
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: c.muted, size: 48),
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: c.muted, fontSize: 14)),
          const SizedBox(height: 18),
          ElevatedButton(onPressed: _load, child: Text(t.retry)),
        ]),
      );
    }
    final p = _data;
    if (p == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (p.dayName.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.gold.withValues(alpha: 0.22), c.gold.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.gold.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.weekday, style: TextStyle(color: c.muted, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(p.dayName, style: TextStyle(color: c.ink, fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        _element(c, t.tithi, p.tithi),
        _element(c, t.nakshatra, p.nakshatra),
        _element(c, t.yoga, p.yoga),
        _element(c, t.karana, p.karana),
        if (!p.rahukaal.isEmpty || !p.gulika.isEmpty || !p.yamakanta.isEmpty) ...[
          const SizedBox(height: 8),
          Text(t.inauspiciousTimes, style: TextStyle(color: c.ink, fontSize: 15.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (!p.rahukaal.isEmpty) _window(c, t.rahuKaal, p.rahukaal),
          if (!p.gulika.isEmpty) _window(c, t.gulikaKaal, p.gulika),
          if (!p.yamakanta.isEmpty) _window(c, t.yamaganda, p.yamakanta),
        ],
      ],
    );
  }

  Widget _element(RgColors c, String label, PanchangElement e) {
    if (e.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Flexible(child: Text(e.name, textAlign: TextAlign.right, style: TextStyle(color: c.gold, fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
          if (e.start.isNotEmpty || e.end.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_span(e.start, e.end), style: TextStyle(color: c.muted, fontSize: 11.5)),
          ],
          if (e.meaning.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(e.meaning, style: TextStyle(color: c.ink, fontSize: 13, height: 1.4)),
          ],
        ]),
      ),
    );
  }

  Widget _window(RgColors c, String label, TimeWindow w) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.red.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(Icons.schedule, color: c.red, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w700))),
            Flexible(child: Text(_span(w.start, w.end), textAlign: TextAlign.right, style: TextStyle(color: c.muted, fontSize: 11.5))),
          ]),
        ),
      );

  String _span(String start, String end) {
    String clock(String s) {
      final m = RegExp(r'(\d{1,2}:\d{2})(?::\d{2})?\s*([AP]M)?', caseSensitive: false).firstMatch(s);
      if (m == null) return s.trim();
      return '${m.group(1)}${m.group(2) != null ? ' ${m.group(2)!.toUpperCase()}' : ''}';
    }
    final a = start.isNotEmpty ? clock(start) : '';
    final b = end.isNotEmpty ? clock(end) : '';
    if (a.isNotEmpty && b.isNotEmpty) return '$a → $b';
    return a.isNotEmpty ? a : b;
  }

  Future<void> _pickLanguage() async {
    final c = context.rg;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.ground2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          for (final locale in SettingsProvider.supportedLocales)
            ListTile(
              title: Text(
                SettingsProvider.languageNames[locale.languageCode] ?? locale.languageCode,
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
              ),
              trailing: _lang == locale.languageCode ? Icon(Icons.check_circle, color: c.red) : null,
              onTap: () => Navigator.of(ctx).pop(locale.languageCode),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null && picked != _lang) {
      setState(() => _lang = picked);
      _load();
    }
  }
}
