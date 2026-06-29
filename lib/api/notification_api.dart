import 'package:flutter/material.dart';

import 'api_client.dart';

/// One notification as returned by GET /notifications (mirrors the backend
/// Notification model: _id, type, title, body, data, isRead, createdAt).
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  bool isRead;
  final DateTime? createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.isRead = false,
    this.createdAt,
  });

  /// Optional broadcast id (push tap attribution) tucked into `data`.
  String? get broadcastId => data['broadcastId']?.toString();

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['_id'] ?? j['id']).toString(),
        type: (j['type'] ?? 'system').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        data: (j['data'] is Map) ? Map<String, dynamic>.from(j['data']) : const {},
        isRead: j['isRead'] == true,
        createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'].toString()) : null,
      );

  /// An icon to show for this notification, derived from its backend `type`.
  IconData get icon {
    switch (type) {
      case 'gift_received':
        return Icons.card_giftcard;
      case 'withdrawal_status':
        return Icons.payments_outlined;
      case 'order_status':
      case 'pooja_status':
        return Icons.storefront;
      case 'incoming_request':
        return Icons.call_received;
      case 'missed_call':
        return Icons.call_missed;
      case 'escalation':
        return Icons.report_gmailerrorred;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  /// Short relative timestamp ("5m ago", "2d ago") for the row.
  String get when {
    final t = createdAt;
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}

class NotificationPage {
  final List<AppNotification> items;
  final int total;
  final int unread;
  final int page;
  const NotificationPage({required this.items, required this.total, required this.unread, required this.page});
}

/// Wraps the /notifications endpoints (list, mark read, delete, clear). The
/// endpoints are role-agnostic (any authenticated user), so the astrologer
/// account uses the same ones as the user app.
class NotificationApi {
  final ApiClient _api;
  NotificationApi(this._api);

  Future<NotificationPage> list({int page = 1, int limit = 30, bool unreadOnly = false}) async {
    final data = await _api.get('/notifications', query: {
      'page': page,
      'limit': limit,
      if (unreadOnly) 'unread': 'true',
    });
    final map = data as Map<String, dynamic>;
    final raw = (map['items'] as List?) ?? [];
    return NotificationPage(
      items: raw.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList(),
      total: (map['total'] as num?)?.toInt() ?? raw.length,
      unread: (map['unread'] as num?)?.toInt() ?? 0,
      page: (map['page'] as num?)?.toInt() ?? page,
    );
  }

  Future<void> markRead(String id) => _api.patch('/notifications/$id/read');
  Future<void> markAllRead() => _api.patch('/notifications/read-all');
  Future<void> delete(String id) => _api.delete('/notifications/$id');
  Future<void> clearAll() => _api.delete('/notifications');
}
