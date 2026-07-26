import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/horoscope_api.dart';
import '../../i18n/strings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rg_colors.dart';

/// Daily horoscope: pick a zodiac sign + a day (yesterday/today/tomorrow) + a
/// content language, and read the prediction. Content is fetched from the shared
/// backend `/horoscope` endpoint (global cache; a real provider call only on a
/// genuine miss). Mirrors the user app's screen.
class HoroscopeScreen extends StatefulWidget {
  const HoroscopeScreen({super.key});
  @override
  State<HoroscopeScreen> createState() => _HoroscopeScreenState();
}

const _signs = <String>[
  'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
  'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
];

class _HoroscopeScreenState extends State<HoroscopeScreen> {
  String _sign = 'aries';
  int _dayOffset = 0; // -1 yesterday · 0 today · +1 tomorrow
  late String _lang;

  bool _loading = true;
  String? _error;
  Horoscope? _data;

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
      final h = await context.read<HoroscopeApi>().daily(_sign, date: _dateStr, lang: _lang);
      if (!mounted) return;
      setState(() {
        _data = h;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Strings.of(context).couldNotLoadHoroscope;
      });
    }
  }

  // Localized sign name for a slug ('aries'…'pisces').
  String _signLabel(String s) {
    final t = Strings.of(context);
    switch (s) {
      case 'aries': return t.signAries;
      case 'taurus': return t.signTaurus;
      case 'gemini': return t.signGemini;
      case 'cancer': return t.signCancer;
      case 'leo': return t.signLeo;
      case 'virgo': return t.signVirgo;
      case 'libra': return t.signLibra;
      case 'scorpio': return t.signScorpio;
      case 'sagittarius': return t.signSagittarius;
      case 'capricorn': return t.signCapricorn;
      case 'aquarius': return t.signAquarius;
      case 'pisces': return t.signPisces;
      default: return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
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
        title: Text(t.dailyHoroscope, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: t.language,
            onPressed: _pickLanguage,
            icon: Icon(Icons.translate_rounded, color: c.gold),
          ),
        ],
      ),
      body: Column(
        children: [
          _signBar(c, t),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _daySegment(c, t),
          ),
          Expanded(child: _body(c, t)),
        ],
      ),
    );
  }

  Widget _signBar(RgColors c, Strings t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _pickSign,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.ground2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Row(children: [
              Icon(Icons.auto_awesome, color: c.gold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _signLabel(_sign),
                  style: TextStyle(color: c.ink, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text(t.chooseSign, style: TextStyle(color: c.muted, fontSize: 12.5)),
              Icon(Icons.expand_more_rounded, color: c.muted),
            ]),
          ),
        ),
      );

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
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? Colors.white : c.muted),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.red : c.ground2),
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
    final h = _data;
    if (h == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _scoreHeader(c, t, h),
        const SizedBox(height: 14),
        _luckyRow(c, t, h),
        const SizedBox(height: 18),
        if (h.areas.isNotEmpty) ...[
          _sectionLabel(c, t.lifeAreas),
          const SizedBox(height: 10),
          ...h.areas.entries.map((e) => _areaBar(c, t, e.key, e.value)),
          const SizedBox(height: 18),
        ],
        if (h.botResponse.trim().isNotEmpty) ...[
          _sectionLabel(c, t.todaysReading),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Text(h.botResponse, style: TextStyle(color: c.ink, fontSize: 14, height: 1.5)),
          ),
        ],
      ],
    );
  }

  Widget _scoreHeader(RgColors c, Strings t, Horoscope h) => Container(
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
        child: Row(children: [
          SizedBox(
            height: 66,
            width: 66,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                height: 66,
                width: 66,
                child: CircularProgressIndicator(
                  value: (h.totalScore.clamp(0, 100)) / 100,
                  strokeWidth: 6,
                  backgroundColor: c.line,
                  valueColor: AlwaysStoppedAnimation(c.gold),
                ),
              ),
              Text('${h.totalScore}', style: TextStyle(color: c.ink, fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_signLabel(_sign), style: TextStyle(color: c.ink, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(t.totalScore, style: TextStyle(color: c.muted, fontSize: 12.5)),
            ]),
          ),
        ]),
      );

  Widget _luckyRow(RgColors c, Strings t, Horoscope h) {
    final swatch = _parseHex(h.luckyColorCode);
    return Row(children: [
      Expanded(
        child: _luckyCard(c, t.luckyColor, child: Row(children: [
          Container(
            height: 22,
            width: 22,
            decoration: BoxDecoration(
              color: swatch ?? c.muted,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              h.luckyColor.isEmpty ? '—' : h.luckyColor,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ])),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _luckyCard(c, t.luckyNumber, child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: (h.luckyNumber.isEmpty ? const <int>[] : h.luckyNumber)
              .map((n) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.redSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$n', style: TextStyle(color: c.red, fontWeight: FontWeight.w800, fontSize: 13)),
                  ))
              .toList(),
        )),
      ),
    ]);
  }

  Widget _luckyCard(RgColors c, String label, {required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.ground2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _areaBar(RgColors c, Strings t, String key, int value) {
    final v = value.clamp(0, 100);
    final tint = v >= 66 ? c.green : (v >= 40 ? c.gold : c.red);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_areaLabel(t, key), style: TextStyle(color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w600))),
          Text('$v', style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: v / 100,
            minHeight: 8,
            backgroundColor: c.line,
            valueColor: AlwaysStoppedAnimation(tint),
          ),
        ),
      ]),
    );
  }

  Widget _sectionLabel(RgColors c, String s) =>
      Text(s, style: TextStyle(color: c.ink, fontSize: 15.5, fontWeight: FontWeight.w800));

  String _areaLabel(Strings t, String key) {
    switch (key) {
      case 'career':
        return t.career;
      case 'finances':
        return t.finances;
      case 'health':
        return t.health;
      case 'relationship':
        return t.relationship;
      case 'family':
        return t.family;
      case 'friends':
        return t.friends;
      case 'travel':
        return t.travel;
      case 'physique':
        return t.physique;
      case 'status':
        return t.statusLabel;
      default:
        return key;
    }
  }

  Color? _parseHex(String hex) {
    var s = hex.trim().replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }

  Future<void> _pickSign() async {
    final c = context.rg;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.ground2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            for (final s in _signs)
              ListTile(
                leading: Icon(Icons.auto_awesome, color: c.gold, size: 20),
                title: Text(_signLabel(s), style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                trailing: _sign == s ? Icon(Icons.check_circle, color: c.red) : null,
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (picked != null && picked != _sign) {
      setState(() => _sign = picked);
      _load();
    }
  }

  Future<void> _pickLanguage() async {
    final c = context.rg;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.ground2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // 9 languages exceed the default 50%-of-screen cap on shorter devices.
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Flexible(child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
          for (final locale in SettingsProvider.supportedLocales)
            ListTile(
              title: Text(
                SettingsProvider.languageNames[locale.languageCode] ?? locale.languageCode,
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
              ),
              trailing: _lang == locale.languageCode ? Icon(Icons.check_circle, color: c.red) : null,
              onTap: () => Navigator.of(ctx).pop(locale.languageCode),
            ),
          ])),
          const SizedBox(height: 8),
        ]),
        ),
      ),
    );
    if (picked != null && picked != _lang) {
      setState(() => _lang = picked);
      _load();
    }
  }
}
