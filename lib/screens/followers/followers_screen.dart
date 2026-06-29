import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// The astrologer's followers — name, photo, and when they followed. Opened from
/// the "New follower" notification and the profile/reputation section.
class FollowersScreen extends StatefulWidget {
  const FollowersScreen({super.key});

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  List<Follower>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final strings = Strings.of(context);
    try {
      final list = await context.read<AstrologerApi>().myFollowers(limit: 100);
      if (mounted) setState(() => _items = list);
    } catch (_) {
      if (mounted) setState(() => _error = strings.couldNotLoadFollowers);
    }
  }

  /// "2h ago", "3d ago", or a date for older.
  String _since(BuildContext context, DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return Strings.of(context).justNow;
    if (d.inMinutes < 60) return Strings.of(context).dInminutesMAgo(d.inMinutes);
    if (d.inHours < 24) return Strings.of(context).dInhoursHAgo(d.inHours);
    if (d.inDays < 30) return Strings.of(context).dIndaysDAgo(d.inDays);
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final items = _items;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        title: Text(Strings.of(context).followers2, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_error!, style: TextStyle(color: c.muted))))])
            : items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
                          child: Column(children: [
                            Icon(Icons.group_outlined, size: 48, color: c.muted),
                            const SizedBox(height: 12),
                            Text(Strings.of(context).noFollowersYet, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(Strings.of(context).goOnlineAndHostLiveSessions,
                                textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
                          ]),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final f = items[i];
                          final hasPhoto = f.avatar != null && f.avatar!.isNotEmpty;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: c.card,
                                backgroundImage: hasPhoto ? NetworkImage(f.avatar!) : null,
                                child: hasPhoto ? null : Text(f.name.isNotEmpty ? f.name[0].toUpperCase() : '?',
                                    style: TextStyle(color: c.gold, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                              ),
                              Text(_since(context, f.since), style: TextStyle(color: c.muted, fontSize: 11.5)),
                            ]),
                          );
                        },
                      ),
      ),
    );
  }
}
