import 'package:dio/dio.dart';

import '../api/api_config.dart';
import '../api/token_store.dart';

/// Fire-and-forget "this device still has working internet" ACK to the backend.
/// It's the signal that keeps an astrologer shown ONLINE even when the app is
/// killed/backgrounded: the backend periodically sends a silent FCM
/// `presence_ping`, the (possibly headless) FCM isolate wakes, and this ACK
/// refreshes lastReachableAt server-side. A phone with NO internet can't reach
/// here, so its reachability window lapses and the backend flips it offline.
///
/// Built to work from the HEADLESS background/terminated isolate too: it can't
/// reach the app's DI graph, so it constructs its own tiny Dio and reads the
/// access token straight from secure storage (shared across isolates). On a 401
/// it does a one-shot refresh and replays once. Always best-effort — a missed
/// ACK just means one skipped heartbeat; the next probe (or a foreground resume)
/// refreshes it. Mirrors [DeliveryAck].
class PresenceAck {
  /// POST /astrologers/me/presence-ack. No-op when not logged in.
  static Future<void> send() async {
    final tokens = TokenStore();
    await tokens.load();
    if (!tokens.hasSession) return; // not logged in → nothing to prove

    final dio = Dio(BaseOptions(
      baseUrl: ApiConfig.apiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'Content-Type': 'application/json',
        // This Dio is built inside the headless FCM isolate and does NOT go
        // through ApiClient, so the tenant header has to be set by hand or the
        // request lands on the default tenant.
        if (ApiConfig.tenant.isNotEmpty) 'X-Tenant': ApiConfig.tenant,
      },
    ));

    // Send an explicit empty JSON object. Posting NO body with
    // `Content-Type: application/json` made express.json() reject the request
    // with a 400 before it reached the handler, so every ACK was discarded and
    // the astrologer was swept offline while genuinely reachable.
    Future<Response> post(String? access) => dio.post(
          '/astrologers/me/presence-ack',
          data: const <String, dynamic>{},
          options: Options(headers: {
            if (access != null && access.isNotEmpty) 'Authorization': 'Bearer $access',
          }),
        );

    try {
      var res = await post(tokens.accessToken);
      // Access token expired in the background → refresh once and replay.
      if (res.statusCode == 401) {
        final access = await _refresh(dio, tokens);
        if (access != null) res = await post(access);
      }
    } catch (_) {
      // Best-effort: offline / transient error → drop it. (If we're offline the
      // ACK SHOULD fail — that's exactly what marks the astrologer unreachable.)
    }
  }

  /// One-shot refresh against /auth/refresh; persists and returns the new access
  /// token, or null if the session is truly dead.
  static Future<String?> _refresh(Dio dio, TokenStore tokens) async {
    final rt = tokens.refreshToken;
    if (rt == null || rt.isEmpty) return null;
    try {
      final res = await dio.post('/auth/refresh', data: {'refreshToken': rt});
      if (res.data is Map && res.data['success'] == true) {
        final d = res.data['data'] as Map;
        final access = d['accessToken'] as String;
        await tokens.save(access: access, refresh: (d['refreshToken'] ?? rt) as String);
        return access;
      }
    } catch (_) {/* dead session */}
    return null;
  }
}
