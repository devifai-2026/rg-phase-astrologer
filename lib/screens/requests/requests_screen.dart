import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/session_api.dart';
import '../../i18n/strings.dart';
import '../../models/astrologer.dart';
import '../../providers/session_provider.dart';
import '../../screens/onboarding/module_onboarding.dart';
import '../../theme/rg_colors.dart';
import 'incoming_call_screen.dart';

/// The "Requests" tab. Two segments:
///  • Live — the incoming-request queue + go-online prompt (unchanged flow).
///  • History — the astrologer's completed/terminal sessions (GET /sessions),
///    each with the anonymous seeker alias, duration and the ₹ earned.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();
    final offline = session.status == AvailabilityStatus.offline;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Strings.of(context).requests, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 22)),
                const SizedBox(height: 4),
                Text(
                  offline ? Strings.of(context).youReOfflineGoOnlineTo : Strings.of(context).liveSessionStatusLabel(session.status.label),
                  style: TextStyle(color: offline ? c.muted : c.green, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Live | History segment.
          TabBar(
            controller: _tabs,
            labelColor: c.red,
            unselectedLabelColor: c.muted,
            indicatorColor: c.red,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [Tab(text: Strings.of(context).live), Tab(text: Strings.of(context).history)],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _LiveTab(),
                _HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live segment (the original incoming-request queue) ──

class _LiveTab extends StatelessWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();
    final offline = session.status == AvailabilityStatus.offline;
    final incoming = session.incomingKind;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Per-service "how it works" cards.
          Row(children: [
            _howChip(context, Strings.of(context).chat, Icons.chat_bubble_outline, c.blue, 'chat'),
            const SizedBox(width: 8),
            _howChip(context, Strings.of(context).call, Icons.call_outlined, c.green, 'call'),
            const SizedBox(width: 8),
            _howChip(context, Strings.of(context).video, Icons.videocam_outlined, c.violet, 'video'),
          ]),
          const SizedBox(height: 18),
          Expanded(
            child: incoming != null
                ? _PendingRequest(kind: incoming, user: session.incomingUser)
                : _EmptyState(offline: offline),
          ),
        ],
      ),
    );
  }

  Widget _howChip(BuildContext context, String label, IconData icon, Color tint, String moduleKey) {
    final c = context.rg;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ModuleOnboarding.show(context, moduleKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
          child: Column(children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(color: c.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.play_circle_outline, size: 10, color: c.muted),
              const SizedBox(width: 3),
              Text(Strings.of(context).howItWorks, style: TextStyle(color: c.muted, fontSize: 8.5)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PendingRequest extends StatelessWidget {
  final ServiceKind kind;
  final String user;
  const _PendingRequest({required this.kind, required this.user});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final tint = switch (kind) {
      ServiceKind.call => c.green,
      ServiceKind.chat => c.blue,
      ServiceKind.video => c.violet,
    };
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: tint, width: 1.4)),
          child: Row(children: [
            CircleAvatar(radius: 26, backgroundColor: tint.withValues(alpha: 0.18), child: Text(user[0], style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 22))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(kind.icon, size: 14, color: tint),
                  const SizedBox(width: 5),
                  Text(Strings.of(context).kindLabelRinging(kind.label), style: TextStyle(color: tint, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: tint, minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IncomingCallScreen(kind: kind))),
              child: Text(Strings.of(context).open),
            ),
          ]),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool offline;
  const _EmptyState({required this.offline});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 88, width: 88,
            decoration: BoxDecoration(color: c.ground2, shape: BoxShape.circle, border: Border.all(color: c.line)),
            child: Icon(offline ? Icons.toggle_off_outlined : Icons.inbox_outlined, size: 42, color: c.muted),
          ),
          const SizedBox(height: 18),
          Text(offline ? Strings.of(context).youAreOffline : Strings.of(context).noPendingRequests, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              offline
                  ? Strings.of(context).switchToOnlineOnTheHome
                  : Strings.of(context).newRequestsWillRingHereTry,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── History segment (GET /sessions) ──

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();
  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> with AutomaticKeepAliveClientMixin {
  String? _filter; // null = all, else 'chat' | 'call' | 'video'
  List<SessionItem>? _items;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<SessionApi>().history(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = Strings.of(context).couldNotLoadHistory);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.rg;
    final all = _items;
    final filtered = all?.where((s) => _filter == null || s.type == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        // Filter chips.
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip(c, Strings.of(context).all, _filter == null, () => setState(() => _filter = null)),
              _chip(c, Strings.of(context).chat, _filter == 'chat', () => setState(() => _filter = 'chat')),
              _chip(c, Strings.of(context).audio, _filter == 'call', () => setState(() => _filter = 'call')),
              _chip(c, Strings.of(context).video, _filter == 'video', () => setState(() => _filter = 'video')),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(c, filtered),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(RgColors c, List<SessionItem>? filtered) {
    if (_error != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
          child: Center(child: Text(_error!, style: TextStyle(color: c.muted))),
        ),
      ]);
    }
    if (filtered == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filtered.isEmpty) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
          child: Column(children: [
            Icon(Icons.history, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(Strings.of(context).noSessionsYet, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(Strings.of(context).yourCompletedConsultationsWillAppearHere,
                textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
          ]),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => SessionHistoryTile(item: filtered[i]),
    );
  }

  Widget _chip(RgColors c, String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: on ? c.redSoft : c.ground2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? c.red : c.line, width: on ? 1.3 : 1),
            ),
            child: Text(label, style: TextStyle(color: on ? c.red : c.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13.5)),
          ),
        ),
      );
}

/// A single session-history row: service-type icon, seeker alias, duration and
/// the ₹ the astrologer earned. Terminal non-completed statuses (missed /
/// rejected / cancelled) render greyed with a status label and no earning.
/// Reused by the Earnings tab's recent-earnings list.
class SessionHistoryTile extends StatelessWidget {
  final SessionItem item;
  const SessionHistoryTile({super.key, required this.item});

  static Color tintFor(RgColors c, String type) => switch (type) {
        'call' => c.green,
        'chat' => c.blue,
        'video' => c.violet,
        _ => c.muted,
      };

  static IconData iconFor(String type) => switch (type) {
        'call' => Icons.call_outlined,
        'chat' => Icons.chat_bubble_outline,
        'video' => Icons.videocam_outlined,
        _ => Icons.history,
      };

  static String labelFor(String type) => switch (type) {
        'call' => 'Audio',
        'chat' => 'Chat',
        'video' => 'Video',
        _ => type,
      };

  /// "Today, 2:14 PM" / "Yesterday, 7:02 PM" / "12 Jun, 3:18 PM".
  static String whenLabel(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:$m $ap';
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final completed = item.isCompleted;
    final tint = tintFor(c, item.type);
    final when = whenLabel(item.endedAt ?? item.createdAt);
    final subtitle = completed
        ? '${labelFor(item.type)} · ${item.minutes} min${when.isEmpty ? '' : ' · $when'}'
        : '${labelFor(item.type)} · ${_statusLabel(item.status)}${when.isEmpty ? '' : ' · $when'}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Row(children: [
        Container(
          height: 42, width: 42,
          decoration: BoxDecoration(color: (completed ? tint : c.muted).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
          child: Icon(completed ? iconFor(item.type) : Icons.call_missed_outgoing, color: completed ? tint : c.muted, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.seekerAlias, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          completed ? '₹${item.astrologerEarning}' : '—',
          style: TextStyle(color: completed ? c.green : c.muted, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ]),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'missed' => 'Missed',
        'rejected' => 'Declined',
        'cancelled' => 'Cancelled',
        'failed' => 'Failed',
        _ => status.isEmpty ? '—' : '${status[0].toUpperCase()}${status.substring(1)}',
      };
}
