import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Google Analytics for Firebase — astrologer app. One instance app-wide.
///
/// Events flow to the Firebase/GA4 dashboard (project: astro-phase-2). Screen
/// views are tracked automatically via [observer]; call the typed helpers at
/// key actions. All calls are best-effort — analytics never throws into the app.
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  final FirebaseAnalytics _fa = FirebaseAnalytics.instance;

  /// Attach to MaterialApp.navigatorObservers for automatic `screen_view`.
  FirebaseAnalyticsObserver get observer => FirebaseAnalyticsObserver(analytics: _fa);

  Future<void> setUser(String? userId) async {
    try { await _fa.setUserId(id: userId); } catch (e) { _warn('setUser', e); }
  }

  Future<void> setProp(String name, String? value) async {
    try { await _fa.setUserProperty(name: name, value: value); } catch (e) { _warn('setProp', e); }
  }

  Future<void> log(String name, [Map<String, Object?>? params]) async {
    try {
      final clean = <String, Object>{};
      params?.forEach((k, v) { if (v != null) clean[k] = v is num ? v : v.toString(); });
      await _fa.logEvent(name: name, parameters: clean.isEmpty ? null : clean);
    } catch (e) { _warn(name, e); }
  }

  // ── Typed helpers for the astrologer funnel ──
  Future<void> login(String method) => _fa.logLogin(loginMethod: method);

  Future<void> setAvailability(bool online) =>
      log('set_availability', {'online': online ? 'online' : 'offline'});

  Future<void> goLive() => log('go_live');

  Future<void> consultStarted(String type) => log('consult_started', {'consult_type': type});
  Future<void> consultEnded(String type, int minutes) =>
      log('consult_ended', {'consult_type': type, 'minutes': minutes});

  Future<void> withdrawalRequested(num amount) =>
      log('withdrawal_requested', {'value': amount, 'currency': 'INR'});

  Future<void> storefrontItemAdded(String kind) =>
      log('storefront_item_added', {'kind': kind});

  void _warn(String where, Object e) {
    if (kDebugMode) debugPrint('[analytics] $where failed: $e');
  }
}
