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

  /// Fallback backend host, used ONLY when the primary [host] can't be reached
  /// (DNS/connection failure). Defaults to the IP-encoded sslip.io host, which
  /// is DETERMINISTIC (sslip.io decodes the IP from the name), so it never flaps
  /// the way api.devifai.in can on public resolvers. Lets the app self-heal.
  static const String fallbackHost = String.fromEnvironment(
    'RG_API_FALLBACK',
    defaultValue: 'https://34-93-133-182.sslip.io',
  );

  /// True when a distinct, non-empty fallback host is configured.
  static bool get hasFallback => fallbackHost.isNotEmpty && fallbackHost != host;

  /// REST base — every endpoint is relative to this.
  static String get apiBase => '$host/api';
  static String get fallbackApiBase => '$fallbackHost/api';

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
