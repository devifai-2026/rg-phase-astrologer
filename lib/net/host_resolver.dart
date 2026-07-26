import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';

/// THE single source of truth for which backend host to talk to.
///
/// Before this there were THREE independent fallback implementations that could
/// disagree with each other:
///   - ApiClient._useFallback  — retried once, one-way, never returned to primary
///   - SocketService._socketHost — needed 3 connect_errors, one-way AND one-shot
///   - PresenceAck (FCM isolate) — no fallback at all, hardcoded to ApiConfig
///
/// That last one was the worst: on a network where the primary host is
/// unresolvable, background presence ACKs failed exactly when the fallback was
/// needed, so `lastReachableAt` went stale and the server swept the astrologer
/// offline while the foreground app still showed "Online".
///
/// It also never recovered. Once switched to the sslip.io fallback, the process
/// stayed there for its whole lifetime even after the primary domain came back.
class HostResolver {
  HostResolver({List<String>? candidates})
      : candidates = (candidates ?? ApiConfig.candidateHosts)
            .where((h) => h.isNotEmpty)
            .toList();

  static const _kHost = 'rg_active_host_v1';
  static const _kStamp = 'rg_active_host_at';

  /// How long a fallback choice is honoured on a COLD start before we go back to
  /// trying the primary. Without this, an app restarted the next day would still
  /// be talking to the fallback host for no reason.
  static const stickyTtl = Duration(hours: 6);

  /// Minimum gap between primary re-probes while on a fallback.
  static const reprobeAfter = Duration(minutes: 30);

  final List<String> candidates;
  int _index = 0;
  DateTime? _pinnedAt;
  DateTime? _lastProbeAt;

  /// Fires whenever the active host changes, so ApiClient can update its baseUrl
  /// and the socket can rebuild on the new host.
  final ValueNotifier<String> hostChanges = ValueNotifier<String>(ApiConfig.host);

  String get activeHost => candidates.isEmpty ? ApiConfig.host : candidates[_index];
  String get apiBase => '$activeHost/api';
  String get socketUrl => activeHost;
  bool get isOnFallback => _index != 0;
  bool get hasAlternate => candidates.length > 1;

  /// Restore the sticky choice written by a previous run OR by the FCM isolate.
  /// Expired pins reset to the primary so a stale fallback never persists.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final host = p.getString(_kHost);
      final at = p.getInt(_kStamp);
      if (host == null || at == null) return;
      final age = DateTime.now().millisecondsSinceEpoch - at;
      if (age > stickyTtl.inMilliseconds) return; // expired → stay on primary
      final i = candidates.indexOf(host);
      if (i > 0) {
        _index = i;
        _pinnedAt = DateTime.fromMillisecondsSinceEpoch(at);
        hostChanges.value = activeHost;
      }
    } catch (_) {/* best-effort */}
  }

  /// Move to the next candidate. Returns false when every candidate has been
  /// tried since the last success, so the caller can go `fatal` instead of
  /// looping forever.
  Future<bool> rotate({required String reason}) async {
    if (candidates.length < 2) return false;
    final next = (_index + 1) % candidates.length;
    if (next == 0) return false; // wrapped back to primary → exhausted
    _index = next;
    await _persist();
    hostChanges.value = activeHost;
    return true;
  }

  /// Called on every successful request/connect. Pins the working host.
  Future<void> markHealthy() async {
    if (_index == 0) {
      // Primary is working — drop any persisted fallback so the next cold start
      // doesn't begin on the fallback.
      if (_pinnedAt != null) { _pinnedAt = null; await _clear(); }
      return;
    }
    await _persist();
  }

  /// Non-disruptive probe of the PRIMARY while we're on a fallback. This is the
  /// recovery half that the old one-way switch never had.
  Future<bool> probePrimary({bool force = false}) async {
    if (!isOnFallback || candidates.isEmpty) return false;
    final now = DateTime.now();
    if (!force && _lastProbeAt != null && now.difference(_lastProbeAt!) < reprobeAfter) {
      return false;
    }
    _lastProbeAt = now;
    final primary = candidates[0];
    try {
      final probe = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
        validateStatus: (s) => s != null && s < 500,
      ));
      final res = await probe.get('$primary/healthz');
      if (res.statusCode == 200) {
        _index = 0;
        _pinnedAt = null;
        await _clear();
        hostChanges.value = activeHost;
        return true;
      }
    } catch (_) {/* still unreachable */}
    return false;
  }

  Future<void> _persist() async {
    _pinnedAt = DateTime.now();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kHost, activeHost);
      await p.setInt(_kStamp, _pinnedAt!.millisecondsSinceEpoch);
    } catch (_) {/* best-effort */}
  }

  Future<void> _clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kHost);
      await p.remove(_kStamp);
    } catch (_) {/* best-effort */}
  }

  /// Isolate-safe read for headless code (PresenceAck / DeliveryAck), which runs
  /// when the main isolate may be dead. Disk is the only reliable channel — an
  /// IsolateNameServer port would not exist.
  ///
  /// `reload()` matters: SharedPreferences caches per isolate, so a long-lived
  /// FCM isolate would otherwise serve a stale host for its whole life.
  static Future<String> activeHostForIsolate() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final host = p.getString(_kHost);
      final at = p.getInt(_kStamp);
      if (host == null || at == null) return ApiConfig.host;
      final age = DateTime.now().millisecondsSinceEpoch - at;
      if (age > stickyTtl.inMilliseconds) return ApiConfig.host;
      return host;
    } catch (_) {
      return ApiConfig.host;
    }
  }

  /// Persist a working host from a background isolate so the main isolate adopts
  /// it on next resume.
  static Future<void> persistFromIsolate(String host) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kHost, host);
      await p.setInt(_kStamp, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {/* best-effort */}
  }

  /// Every candidate, primary first — for an isolate that wants to retry the
  /// other host itself.
  static List<String> candidatesForIsolate() => ApiConfig.candidateHosts;
}
