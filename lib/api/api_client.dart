import 'package:dio/dio.dart';

import 'api_config.dart';
import 'token_store.dart';

/// Thrown for any non-success response. `message` is backend-friendly;
/// `errors` holds field-level validation messages.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final List<String> errors;
  ApiException(this.message, {this.statusCode, this.errors = const []});
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// One Dio instance for the astrologer app. Attaches the Bearer token, unwraps
/// the `{ success, data }` envelope, and transparently refreshes the access
/// token on a 401 (then retries once). Mirrors the user app's ApiClient.
class ApiClient {
  final Dio dio;
  final TokenStore tokens;

  /// Called when refresh fails (session truly dead) so the app can log out.
  void Function()? onSessionExpired;

  /// The astrologer's current UI language (e.g. 'hi'). Sent as the `x-lang`
  /// header on every request so the backend localizes dynamic content to this
  /// language regardless of the saved profile field. Kept in sync by
  /// SettingsProvider. Defaults to 'en'.
  String langCode = 'en';

  ApiClient(this.tokens)
      : dio = Dio(BaseOptions(
          baseUrl: ApiConfig.apiBase,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          // Handle non-2xx ourselves so we can read the error envelope.
          validateStatus: (s) => s != null && s < 500,
          headers: {
            'Content-Type': 'application/json',
            // Multi-tenant routing (see api_config.dart). Omitted in dev builds.
            if (ApiConfig.tenant.isNotEmpty) 'X-Tenant': ApiConfig.tenant,
          },
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = tokens.accessToken;
        if (t != null && t.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        // Tell the backend which language to return dynamic content in.
        options.headers['x-lang'] = langCode;
        handler.next(options);
      },
    ));
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => dio.get(path, queryParameters: query), path);

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => dio.post(path, data: body), path);

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => dio.put(path, data: body), path);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => dio.patch(path, data: body), path);

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(() => dio.delete(path, data: body), path);

  Future<dynamic> _send(Future<Response> Function() run, String path) async {
    Response res;
    try {
      res = await run();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw ApiException('No connection to the server', statusCode: null);
      }
      throw ApiException(e.message ?? 'Request failed');
    }

    // Access token expired → single refresh, then replay ONCE.
    // 401 = expired/invalid token (refresh fixes it). 403 may be an expired
    // token on some endpoints too, so we attempt the same refresh+retry — but
    // strictly once: if the replay still returns 403 it's a real permission/
    // block error (refresh can't help), and we surface it via _unwrap below.
    final authStatus = res.statusCode == 401 || res.statusCode == 403;
    if (authStatus && tokens.hasSession && !path.contains('/auth/refresh')) {
      final refreshed = await _refresh();
      if (refreshed) {
        try {
          res = await run(); // single replay with the fresh token
        } on DioException catch (e) {
          throw ApiException(e.message ?? 'Request failed');
        }
      } else if (res.statusCode == 401) {
        // Couldn't refresh and the token is invalid → session is dead.
        onSessionExpired?.call();
        throw ApiException('Session expired', statusCode: 401);
      }
      // 403 with no refresh available falls through to _unwrap as a real error.
    }

    return _unwrap(res);
  }

  dynamic _unwrap(Response res) {
    final data = res.data;
    final ok = res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    if (ok && data is Map && data['success'] == true) return data['data'];
    final msg = (data is Map ? data['message'] : null)?.toString() ?? 'Request failed';
    final errs = (data is Map && data['errors'] is List)
        ? (data['errors'] as List).map((e) => e.toString()).toList()
        : <String>[];
    throw ApiException(ok ? 'Unexpected response' : msg, statusCode: res.statusCode, errors: errs);
  }

  // Single-flight refresh: concurrent 401s share one refresh call.
  Future<bool>? _refreshing;
  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = tokens.refreshToken;
    if (rt == null || rt.isEmpty) return false;
    try {
      final res = await dio.post('/auth/refresh', data: {'refreshToken': rt});
      if (res.data is Map && res.data['success'] == true) {
        final d = res.data['data'] as Map;
        await tokens.save(
          access: d['accessToken'] as String,
          refresh: (d['refreshToken'] ?? rt) as String,
        );
        return true;
      }
    } catch (_) {/* fall through */}
    return false;
  }
}
