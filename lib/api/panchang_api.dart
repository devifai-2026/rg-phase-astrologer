import 'api_client.dart';

/// One day's Panchang (VedicAstroAPI `panchang/panchang`, served from the
/// backend's global per-(date,location,lang) cache). Same shape as the user
/// app — both hit the shared `/panchang` endpoint.
class Panchang {
  final Map<String, dynamic> raw;
  const Panchang(this.raw);

  factory Panchang.fromJson(Map<String, dynamic> j) => Panchang(j);

  Map<String, dynamic> _m(String k) {
    final v = raw[k];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  String get dayName => (_m('day')['name'] ?? '').toString();

  PanchangElement get tithi => PanchangElement.from(_m('tithi'));
  PanchangElement get nakshatra => PanchangElement.from(_m('nakshatra'));
  PanchangElement get yoga => PanchangElement.from(_m('yoga'));
  PanchangElement get karana => PanchangElement.from(_m('karana'));

  TimeWindow get rahukaal => TimeWindow.from(_m('rahukaal'));
  TimeWindow get gulika => TimeWindow.from(_m('gulika'));
  TimeWindow get yamakanta => TimeWindow.from(_m('yamakanta'));
}

class PanchangElement {
  final String name;
  final String start;
  final String end;
  final String meaning;
  final String special;
  const PanchangElement({required this.name, required this.start, required this.end, required this.meaning, required this.special});

  factory PanchangElement.from(Map<String, dynamic> m) => PanchangElement(
        name: (m['name'] ?? '').toString(),
        start: (m['start'] ?? '').toString(),
        end: (m['end'] ?? '').toString(),
        meaning: (m['meaning'] ?? '').toString(),
        special: (m['special'] ?? '').toString(),
      );

  bool get isEmpty => name.isEmpty || name == '—';
}

class TimeWindow {
  final String start;
  final String end;
  const TimeWindow({required this.start, required this.end});
  factory TimeWindow.from(Map<String, dynamic> m) =>
      TimeWindow(start: (m['start'] ?? '').toString(), end: (m['end'] ?? '').toString());
  bool get isEmpty => start.isEmpty && end.isEmpty;
}

/// REST surface for the daily panchang.
class PanchangApi {
  final ApiClient _api;
  PanchangApi(this._api);

  /// GET /panchang — one day's panchang for a location.
  Future<Panchang> daily({String? date, double? lat, double? lon, String? lang}) async {
    final data = await _api.get('/panchang', query: {
      if (date != null) 'date': date,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (lang != null) 'lang': lang,
    });
    return Panchang.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
