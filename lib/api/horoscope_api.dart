import 'api_client.dart';

/// One zodiac sign's daily prediction (VedicAstroAPI `prediction/daily-moon`,
/// served from the backend's global per-(date,sign,lang) cache). Same shape as
/// the user app — both hit the shared `/horoscope` endpoint.
class Horoscope {
  final int totalScore;
  final String luckyColor;
  final String luckyColorCode; // hex, e.g. "#8A0303"
  final List<int> luckyNumber;
  final String botResponse; // narrative reading
  final String zodiac; // provider display name, e.g. "Cancer"
  final Map<String, int> areas; // per-life-area scores (0..100), display order

  const Horoscope({
    required this.totalScore,
    required this.luckyColor,
    required this.luckyColorCode,
    required this.luckyNumber,
    required this.botResponse,
    required this.zodiac,
    required this.areas,
  });

  static int _int(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  static const areaKeys = <String>[
    'career', 'finances', 'health', 'relationship',
    'family', 'friends', 'travel', 'physique', 'status',
  ];

  factory Horoscope.fromJson(Map<String, dynamic> j) {
    final areas = <String, int>{};
    for (final k in areaKeys) {
      if (j[k] != null) areas[k] = _int(j[k]);
    }
    final nums = (j['lucky_number'] as List?)?.map(_int).toList() ?? const <int>[];
    return Horoscope(
      totalScore: _int(j['total_score']),
      luckyColor: (j['lucky_color'] ?? '').toString(),
      luckyColorCode: (j['lucky_color_code'] ?? '').toString(),
      luckyNumber: nums,
      botResponse: (j['bot_response'] ?? '').toString(),
      zodiac: (j['zodiac'] ?? '').toString(),
      areas: areas,
    );
  }
}

/// REST surface for the daily horoscope.
class HoroscopeApi {
  final ApiClient _api;
  HoroscopeApi(this._api);

  /// GET /horoscope/:sign — one sign's prediction. [date] is 'YYYY-MM-DD'
  /// (default: server today); [lang] overrides the app-language header.
  Future<Horoscope> daily(String sign, {String? date, String? lang}) async {
    final data = await _api.get('/horoscope/${sign.toLowerCase()}', query: {
      if (date != null) 'date': date,
      if (lang != null) 'lang': lang,
    });
    return Horoscope.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
