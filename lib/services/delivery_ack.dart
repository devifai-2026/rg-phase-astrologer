import 'package:dio/dio.dart';

import '../api/api_config.dart';
import '../api/token_store.dart';

/// Fire-and-forget "this device received the push" ACK to the backend, used to
/// power TRUE device-confirmed delivery analytics (vs FCM's accept-only count).
/// This is what makes the admin "Delivered" graph move past 0.
///
/// Built to work from the HEADLESS background/terminated isolate too: it can't
/// reach the app's DI graph, so it constructs its own tiny Dio and reads the
/// access token straight from secure storage (Keychain/Keystore is shared
/// across isolates). On a 401 it does a one-shot refresh and replays once.
///
/// Always best-effort: any failure is swallowed (a missed ACK just means the
/// delivery undercounts slightly; it must never crash the receive handler).
/// Mirrors the user app's DeliveryAck.
class DeliveryAck {
  /// POST /notifications/delivered { broadcastId }. No-op without a session or
  /// a broadcastId.
  static Future<void> send(String? broadcastId) async {
    if (broadcastId == null || broadcastId.isEmpty) return;

    final tokens = TokenStore();
    await tokens.load();
    if (!tokens.hasSession) return; // not logged in → nothing to attribute

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

    Future<Response> post(String? access) => dio.post(
          '/notifications/delivered',
          data: {'broadcastId': broadcastId},
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
      // Best-effort: offline / transient error → drop it.
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
