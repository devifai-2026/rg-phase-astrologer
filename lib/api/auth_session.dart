import 'package:dio/dio.dart';

import 'api_config.dart';
import 'token_store.dart';

/// Owns the access-token refresh, SHARED by everything that needs a live token:
/// the REST client and the socket connection state machine.
///
/// Why it is shared: the refresh endpoint ROTATES the refresh token, so two
/// independent refreshes race — the loser presents a token that was already
/// rotated away, gets a 401, and the app logs the user out spuriously. Previously
/// ApiClient owned a private `_refresh()` single-flight and the socket had no
/// refresh path at all (it just gave up silently), so a socket that needed a
/// fresh token could never get one.
class AuthSession {
  AuthSession(this._tokens, {Dio? dio, String Function()? apiBase})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          // Let us inspect 4xx rather than throwing, so a 401 is distinguishable
          // from a network failure — the difference between "log out" and "retry".
          validateStatus: (s) => s != null && s < 500,
        )),
        _apiBase = apiBase ?? (() => ApiConfig.apiBase);

  final TokenStore _tokens;
  final Dio _dio;
  final String Function() _apiBase;

  /// Called when the session is definitively dead (refresh rejected, not merely
  /// unreachable) so the app can clear tokens and route to login.
  void Function()? onSessionExpired;

  /// True when the last refresh failed because the SERVER rejected our identity,
  /// as opposed to a network problem. The state machine uses this to choose
  /// between `fatal(authRejected)` (stop, show sign-in) and `backoff` (retry).
  bool lastRefreshWasRejected = false;

  Future<bool>? _inFlight;

  /// Ensure `tokens.accessUsable` is true on return.
  ///
  /// Returns false when it could not be achieved. Callers must then check
  /// [lastRefreshWasRejected] to tell a dead session from a flaky network.
  Future<bool> ensureFreshAccessToken({bool force = false}) {
    if (!force && _tokens.accessUsable) return Future.value(true);
    return _inFlight ??= _run(force).whenComplete(() => _inFlight = null);
  }

  Future<bool> _run(bool force) async {
    lastRefreshWasRejected = false;

    // Another isolate (the FCM presence-ping handler) may have refreshed while we
    // were backgrounded, leaving our in-memory copy stale. Pick that up before
    // spending a network call — and before risking a rotated-away refresh token.
    if (await _tokens.diskRevisionChanged()) {
      await _tokens.reloadFromDisk();
      if (!force && _tokens.accessUsable) return true;
    }

    if (!_tokens.hasRefresh) {
      lastRefreshWasRejected = true; // nothing to refresh WITH → session is dead
      return false;
    }

    final ok = await _attempt(_tokens.refreshToken!);
    if (ok) return true;

    // Rejected. The most common benign cause is that a background isolate rotated
    // the refresh token out from under us between our read and our request, so
    // re-read the disk and retry ONCE with whatever is there now.
    if (lastRefreshWasRejected) {
      final usedToken = _tokens.refreshToken;
      await _tokens.reloadFromDisk();
      final onDisk = _tokens.refreshToken;
      if (_tokens.accessUsable) { lastRefreshWasRejected = false; return true; }
      if (onDisk != null && onDisk.isNotEmpty && onDisk != usedToken) {
        lastRefreshWasRejected = false;
        if (await _attempt(onDisk)) return true;
      }
    }

    if (lastRefreshWasRejected) onSessionExpired?.call();
    return false;
  }

  /// One refresh round-trip. Sets [lastRefreshWasRejected] only when the server
  /// actually said no (401/403) — a timeout or DNS failure leaves it false so the
  /// caller retries instead of logging the user out.
  Future<bool> _attempt(String refreshToken) async {
    try {
      final res = await _dio.post(
        '${_apiBase()}/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = res.data;
      if (res.statusCode == 200 && data is Map && data['success'] == true) {
        final d = data['data'] as Map;
        await _tokens.save(
          access: d['accessToken'] as String,
          refresh: (d['refreshToken'] ?? refreshToken) as String,
        );
        return true;
      }
      if (res.statusCode == 401 || res.statusCode == 403) lastRefreshWasRejected = true;
      return false;
    } on DioException catch (_) {
      // Network-class failure → NOT a rejection. Retryable.
      return false;
    } catch (_) {
      return false;
    }
  }
}
