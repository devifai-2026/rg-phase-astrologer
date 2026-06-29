import 'package:flutter/foundation.dart';

import '../api/notification_api.dart';

/// Owns the astrologer's notification inbox: list, unread count, and the
/// mark-read / mark-all-read / delete / clear actions. The home bell badge and
/// the Notifications screen both watch `items` + `unread`. Backed by the real
/// /notifications API (the same endpoints the user app uses).
class NotificationsProvider extends ChangeNotifier {
  final NotificationApi _api;
  NotificationsProvider(this._api);

  List<AppNotification> _items = [];
  int _unread = 0;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<AppNotification> get items => _items;
  int get unread => _unread;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  /// Fetch the latest notifications. Call on app start (after login), when the
  /// Notifications screen opens, on pull-to-refresh, and on a socket event.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _api.list(limit: 50);
      _items = page.items;
      _unread = page.unread;
      _loaded = true;
    } catch (e) {
      _error = 'Could not load notifications';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Lightweight refresh of just the unread count (e.g. on a socket event when
  /// the screen isn't open).
  Future<void> refreshUnread() async {
    try {
      final page = await _api.list(limit: 1);
      _unread = page.unread;
      notifyListeners();
    } catch (_) {/* keep last known */}
  }

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    n.isRead = true; // optimistic
    if (_unread > 0) _unread--;
    notifyListeners();
    try {
      await _api.markRead(n.id);
    } catch (_) {/* keep optimistic state */}
  }

  Future<void> markAllRead() async {
    if (_unread == 0) return;
    for (final n in _items) {
      n.isRead = true;
    }
    _unread = 0;
    notifyListeners();
    try {
      await _api.markAllRead();
    } catch (_) {/* keep optimistic state */}
  }

  Future<void> delete(AppNotification n) async {
    final wasUnread = !n.isRead;
    _items.remove(n); // optimistic
    if (wasUnread && _unread > 0) _unread--;
    notifyListeners();
    try {
      await _api.delete(n.id);
    } catch (_) {
      _items.add(n); // re-insert on failure
      if (wasUnread) _unread++;
      notifyListeners();
    }
  }

  Future<void> clearAll() async {
    final backup = List<AppNotification>.from(_items);
    final backupUnread = _unread;
    _items = [];
    _unread = 0;
    notifyListeners();
    try {
      await _api.clearAll();
    } catch (_) {
      _items = backup;
      _unread = backupUnread;
      notifyListeners();
    }
  }

  /// Clear local state on logout.
  void reset() {
    _items = [];
    _unread = 0;
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
