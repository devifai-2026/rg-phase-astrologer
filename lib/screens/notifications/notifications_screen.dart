import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/notification_api.dart';
import '../../i18n/strings.dart';
import '../../providers/notifications_provider.dart';
import '../../theme/rg_colors.dart';

/// Notifications inbox — bound to the backend /notifications API via
/// [NotificationsProvider]. Shows admin/system notifications (e.g. a storefront
/// pooja/product approved), withdrawals, gifts, reviews, etc. Pull to refresh;
/// tap a row to mark it read; swipe to delete.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh on open so the inbox is current (and the bell badge clears stale).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsProvider>().load();
    });
  }

  Future<void> _confirmClearAll(BuildContext context, RgColors c) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final prov = context.read<NotificationsProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.ground,
        title: Text(s.deleteAllNotifications, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        content: Text(s.thisClearsYourEntireInboxThis, style: TextStyle(color: c.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel, style: TextStyle(color: c.muted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.deleteAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await prov.clearAll();
      messenger.showSnackBar(SnackBar(content: Text(s.allNotificationsCleared)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.couldNotClearNotifications)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = Strings.of(context);
    final prov = context.watch<NotificationsProvider>();
    final items = prov.items;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Text(s.notifications, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        actions: [
          if (prov.unread > 0)
            TextButton(
              onPressed: () => context.read<NotificationsProvider>().markAllRead(),
              child: Text(s.markAllRead, style: TextStyle(color: c.red, fontWeight: FontWeight.w700)),
            ),
          // Overflow: delete all (confirmed). Only shown when there's something.
          if (items.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: c.ink),
              onSelected: (v) { if (v == 'clear') _confirmClearAll(context, c); },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'clear',
                  child: Row(children: [
                    Icon(Icons.delete_sweep_outlined, size: 19, color: c.red),
                    const SizedBox(width: 10),
                    Text(s.deleteAll, style: TextStyle(color: c.red, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        color: c.red,
        onRefresh: () => context.read<NotificationsProvider>().load(),
        child: _body(context, c, prov, items),
      ),
    );
  }

  Widget _body(BuildContext context, RgColors c, NotificationsProvider prov, List<AppNotification> items) {
    // Initial load (nothing cached yet) → spinner.
    if (prov.loading && !prov.loaded) {
      return Center(child: CircularProgressIndicator(color: c.red));
    }
    // Error on first load with nothing to show → retry affordance.
    if (prov.error != null && items.isEmpty) {
      return _Message(
        icon: Icons.wifi_off,
        title: prov.error!,
        hint: 'Pull down to retry.',
        c: c,
      );
    }
    // Loaded but empty.
    if (items.isEmpty) {
      return _Message(
        icon: Icons.notifications_none,
        title: Strings.of(context).noNotificationsYet,
        hint: Strings.of(context).approvalsWithdrawalsAndUpdatesWillShow,
        c: c,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final n = items[i];
        return Dismissible(
          key: ValueKey(n.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => context.read<NotificationsProvider>().delete(n),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: c.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.delete_outline, color: c.red),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.read<NotificationsProvider>().markRead(n),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: n.isRead ? c.ground2 : c.redSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: n.isRead ? c.line : c.red.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                Container(
                  height: 42, width: 42,
                  decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: c.line)),
                  child: Icon(n.icon, color: c.gold, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(n.title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14))),
                      Text(n.when, style: TextStyle(color: c.muted, fontSize: 11)),
                    ]),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(n.body, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3)),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Centered empty/error state that still scrolls (so pull-to-refresh works).
class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final RgColors c;
  const _Message({required this.icon, required this.title, required this.hint, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Icon(icon, size: 48, color: c.muted),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(hint, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}
