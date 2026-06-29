/// Where the astrologer app finds the backend. Mirrors the user app's config.
///
/// Override at build time without editing code:
///   flutter run --dart-define=RG_API_BASE=http://192.168.1.5:5050
///
/// Defaults to the Android-emulator alias for the host machine (10.0.2.2). On a
/// real device pass your machine's LAN IP via --dart-define (see below).
class ApiConfig {
  /// Backend host root (NO trailing /api).
  static const String host = String.fromEnvironment(
    'RG_API_BASE',
    defaultValue: 'http://10.0.2.2:5050',
  );

  /// REST base — every endpoint is relative to this.
  static String get apiBase => '$host/api';

  /// Socket.io connects to the host root, not /api.
  static String get socketUrl => host;
}
