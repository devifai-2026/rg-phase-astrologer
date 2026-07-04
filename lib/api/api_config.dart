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

  /// Multi-tenant: the tenant slug this build belongs to, stamped by the build
  /// factory (`--dart-define=TENANT=<slug>`). Sent as `X-Tenant` on every REST
  /// call + the socket handshake so the backend routes to the right tenant DB.
  /// Empty in single-tenant/dev builds.
  static const String tenant = String.fromEnvironment('TENANT', defaultValue: '');

  /// Per-tenant deep-link URI scheme (e.g. `acme://...`). Stamped by the build
  /// factory (`--dart-define=DEEPLINK_SCHEME=<scheme>`), matches the
  /// AndroidManifest intent-filter (manifestPlaceholder `deepLinkScheme`).
  static const String deepLinkScheme =
      String.fromEnvironment('DEEPLINK_SCHEME', defaultValue: 'astroapp');
}
