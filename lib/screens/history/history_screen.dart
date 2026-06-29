import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/session_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/how_it_works_button.dart';
import '../requests/requests_screen.dart' show SessionHistoryTile;

/// Consultation history (chat / audio / video) backed by the real session API
/// (GET /sessions via [SessionApi.history]). Each row shows the anonymous
/// seeker alias, duration and the ₹ the astrologer earned. Non-completed
/// terminal sessions (missed / declined / cancelled) render greyed with no
/// earning. A service filter re-fetches scoped to a single type.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _filter; // null = All, else backend type: 'chat' | 'call' | 'video'
  List<SessionItem>? _items;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final strings = Strings.of(context);
    try {
      final list = await context.read<SessionApi>().history(limit: 50, type: _filter);
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = strings.couldNotLoadHistory;
        _loading = false;
      });
    }
  }

  void _selectFilter(String? type) {
    if (_filter == type) return;
    setState(() => _filter = type);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(children: [
              Text(Strings.of(context).history, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 22)),
              const Spacer(),
              const HowItWorksButton(moduleKey: 'chat', compact: true),
            ]),
          ),
          // Filter chips. "Audio" maps to backend type 'call'; "All" = null.
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(c, Strings.of(context).all, _filter == null, () => _selectFilter(null)),
                _chip(c, Strings.of(context).chat, _filter == 'chat', () => _selectFilter('chat')),
                _chip(c, Strings.of(context).audio, _filter == 'call', () => _selectFilter('call')),
                _chip(c, Strings.of(context).video, _filter == 'video', () => _selectFilter('video')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(RgColors c) {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
          child: Column(children: [
            Icon(Icons.error_outline, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(Strings.of(context).pullDownToRetry,
                textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
          ]),
        ),
      ]);
    }
    final items = _items ?? const <SessionItem>[];
    if (items.isEmpty) {
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
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _HistoryRow(item: items[i]),
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

/// A history row: reuses [SessionHistoryTile] for the shared look, and appends a
/// subtle "chat available" hint for completed chats still within retention.
/// No chat viewer exists in this app, so the hint is informational only.
class _HistoryRow extends StatelessWidget {
  final SessionItem item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final showChatHint = item.type == 'chat' && item.isCompleted && item.canViewChat;
    if (!showChatHint) return SessionHistoryTile(item: item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SessionHistoryTile(item: item),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 0, 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chat_bubble_outline, size: 12, color: c.blue),
            const SizedBox(width: 4),
            Text(Strings.of(context).chatAvailable, style: TextStyle(color: c.blue, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    );
  }
}
