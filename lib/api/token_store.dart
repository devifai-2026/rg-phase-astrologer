import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the access + refresh token pair in platform secure storage
/// (Keychain / Keystore), with an in-memory cache so the Dio interceptor can
/// read the access token synchronously. Mirrors the user app's TokenStore.
///
/// ── Why `hasSession` was dangerous ──
/// It tested the REFRESH token only, so `hasSession == true` while
/// `accessToken == null` is reachable (a killed app between a save and a
/// refresh, or a background-isolate rotation). `main.dart` used it to gate
/// `socket.connect()`, and connect() returns silently when the access token is
/// empty — so the socket never connected, nothing retried, and the UI sat on
/// "Connecting…" forever. That is the bug this split fixes: callers must now say
/// whether they mean "can we log in?" (hasRefresh) or "can we call right now?"
/// (accessUsable).
class TokenStore {
  static const _kAccess = 'rg_astro_access';
  static const _kRefresh = 'rg_astro_refresh';

  /// Monotonic counter in SharedPreferences, bumped on every write from ANY
  /// isolate. The main isolate compares it on resume to decide whether its
  /// in-memory cache is stale — see [diskRevisionChanged].
  static const _kRevision = 'rg_token_rev';

  final FlutterSecureStorage _storage;
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  String? _access;
  String? _refresh;
  int _seenRevision = -1;

  /// Bumped whenever the tokens change, so the connection state machine can
  /// react to a rotation instead of polling.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String? get accessToken => _access;
  String? get refreshToken => _refresh;

  /// A refresh token exists → we can probably OBTAIN an access token. Says
  /// nothing about whether we currently hold a usable one.
  bool get hasRefresh => _refresh != null && _refresh!.isNotEmpty;

  /// A non-empty access token is cached. Says nothing about expiry.
  bool get hasAccess => _access != null && _access!.isNotEmpty;

  /// Locally decoded `exp`, or null when the token isn't a decodable JWT.
  /// Cheap (no network), which lets us refresh PROACTIVELY rather than waiting
  /// for a 401 — and, for the socket, instead of silently doing nothing.
  DateTime? get accessExpiresAt {
    final t = _access;
    if (t == null || t.isEmpty) return null;
    try {
      final parts = t.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final map = jsonDecode(utf8.decode(base64.decode(payload)));
      final exp = map is Map ? map['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    } catch (_) {
      // Not a JWT (or an unexpected shape) → treat expiry as unknown rather
      // than assuming expired, so a non-JWT token can't brick the app.
      return null;
    }
  }

  /// We hold an access token that is good for at least another 60s. The skew
  /// avoids handing a token to the socket handshake moments before it expires.
  bool get accessUsable {
    if (!hasAccess) return false;
    final exp = accessExpiresAt;
    if (exp == null) return true; // unknown expiry → assume usable
    return exp.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 60)));
  }

  @Deprecated('Ambiguous. Use hasRefresh (can we log in?) or accessUsable (can we call now?)')
  bool get hasSession => hasRefresh;

  /// Load tokens from disk into the in-memory cache (call once at startup).
  Future<void> load() async {
    _access = await _storage.read(key: _kAccess);
    _refresh = await _storage.read(key: _kRefresh);
    _seenRevision = await _readDiskRevision();
    revision.value++;
  }

  /// Re-read from disk. Needed because the FCM background isolate has its OWN
  /// TokenStore: when it refreshes, it writes new tokens to the Keystore while
  /// this isolate's in-memory copy still holds the old pair. The main isolate
  /// then 401s, tries to refresh with a refresh token that was already rotated
  /// away, gets rejected, and logs the user out — a real, silent, user-visible
  /// bug. Call this on app resume (cheap: two Keystore reads).
  Future<void> reloadFromDisk() async {
    final a = await _storage.read(key: _kAccess);
    final r = await _storage.read(key: _kRefresh);
    final changed = a != _access || r != _refresh;
    _access = a;
    _refresh = r;
    _seenRevision = await _readDiskRevision();
    if (changed) revision.value++;
  }

  /// True when another isolate has written tokens since we last looked. Lets the
  /// caller skip the Keystore reads when nothing changed.
  Future<bool> diskRevisionChanged() async {
    final disk = await _readDiskRevision();
    return disk != _seenRevision;
  }

  Future<int> _readDiskRevision() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload(); // defeat the per-isolate cache
      return p.getInt(_kRevision) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _bumpDiskRevision() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final next = (p.getInt(_kRevision) ?? 0) + 1;
      await p.setInt(_kRevision, next);
      _seenRevision = next;
    } catch (_) {/* best-effort: staleness detection only */}
  }

  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
    await _bumpDiskRevision();
    revision.value++;
  }

  Future<void> updateAccess(String access) async {
    _access = access;
    await _storage.write(key: _kAccess, value: access);
    await _bumpDiskRevision();
    revision.value++;
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _bumpDiskRevision();
    revision.value++;
  }
}
