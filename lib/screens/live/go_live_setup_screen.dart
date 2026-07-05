import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/live_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import 'live_broadcast_screen.dart';

/// Pre-live setup: the astrologer names the session (title) and picks a topic.
/// "Go Live now" creates the broadcast on the backend (which pushes a
/// notification to users and returns the Agora broadcaster token) and opens the
/// live room. AI moderation + AI polls run automatically once live — there are
/// no toggles to configure.
class GoLiveSetupScreen extends StatefulWidget {
  const GoLiveSetupScreen({super.key});

  @override
  State<GoLiveSetupScreen> createState() => _GoLiveSetupScreenState();
}

class _GoLiveSetupScreenState extends State<GoLiveSetupScreen> {
  final _title = TextEditingController(text: 'Evening Q&A — Career & Marriage');
  String _topic = 'Career & money';
  bool _starting = false;

  static const _topics = ['Career & money', 'Love & marriage', 'Health & remedies', 'Daily horoscope', 'General Q&A'];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _goLive() async {
    if (_starting) return;

    // Going live requires being ONLINE with a live socket — the broadcast is
    // socket-driven, and attempting it while offline/connecting is what caused
    // the "could not go live" failure. Gate on presence + socket; if not ready,
    // offer to go online first (or cancel) instead of failing mid-way.
    final session = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    if (!session.isOnline || !socket.connected) {
      final proceed = await _confirmGoOnlineFirst();
      if (proceed != true || !mounted) return;
      // Go online, then wait (bounded) for the socket to actually connect.
      try {
        await context.read<AstrologerApi>().setOnline(true);
        session.setOnline(true);
        socket.connect();
      } catch (_) {/* setOnline failure surfaces below as a not-connected timeout */}
      final ok = await _waitForSocket(socket);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.of(context).couldNotConnectTryAgain)),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _starting = true);
    try {
      final result = await context.read<LiveApi>().goLive(title: _title.text.trim(), topic: _topic);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LiveBroadcastScreen(
          liveSessionId: result.liveSessionId,
          title: _title.text.trim(),
          topic: _topic,
          token: result.token,
          startedAt: result.startedAt,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not go live: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  /// Modal shown when the astrologer taps Go Live while offline / not connected:
  /// Cancel, or "Go Online & Live" (which flips them online, then proceeds).
  Future<bool?> _confirmGoOnlineFirst() {
    final c = context.rg;
    final s = Strings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(s.youreOffline, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        content: Text(s.goOnlineToStartLive, style: TextStyle(color: c.muted, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.cancel, style: TextStyle(color: c.muted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.goOnlineAndLive, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// Wait (bounded) for the socket to actually connect after going online.
  Future<bool> _waitForSocket(SocketService socket, {Duration timeout = const Duration(seconds: 8)}) async {
    if (socket.connected) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (socket.connected) return true;
    }
    return socket.connected;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(title: Text(Strings.of(context).goLive, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Preview banner.
          Container(
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [c.redDeep, c.red, c.gold], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam, color: Colors.white, size: 40),
                const SizedBox(height: 8),
                Text(Strings.of(context).livePreview, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          _label(c, Strings.of(context).sessionTitle),
          const SizedBox(height: 8),
          TextField(controller: _title, decoration: const InputDecoration()),
          const SizedBox(height: 18),

          _label(c, Strings.of(context).topic),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _topics.map((tp) {
            final on = tp == _topic;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _topic = tp),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: on ? c.redSoft : c.ground2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: on ? c.red : c.line, width: on ? 1.3 : 1),
                ),
                child: Text(tp, style: TextStyle(color: on ? c.red : c.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13.5)),
              ),
            );
          }).toList()),
          const SizedBox(height: 18),

          // What happens automatically when you go live (no toggles).
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _autoRow(c, Icons.campaign_outlined, Strings.of(context).viewersAreNotifiedInstantlyWhenYou),
              const SizedBox(height: 10),
              _autoRow(c, Icons.smart_toy_outlined, Strings.of(context).aiModerationIsAlwaysOnSpam),
              const SizedBox(height: 10),
              _autoRow(c, Icons.poll_outlined, Strings.of(context).aiAutoRunsPollsForYour),
              const SizedBox(height: 10),
              _autoRow(c, Icons.card_giftcard_outlined, Strings.of(context).freeToWatchViewersSupportYou),
            ]),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            icon: _starting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sensors),
            style: ElevatedButton.styleFrom(backgroundColor: c.red),
            label: Text(_starting ? Strings.of(context).goingLive : Strings.of(context).goLiveNow),
            onPressed: _starting ? null : _goLive,
          ),
        ],
      ),
    );
  }

  Widget _label(RgColors c, String t) => Text(t, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13));

  Widget _autoRow(RgColors c, IconData icon, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c.gold, size: 19),
        const SizedBox(width: 11),
        Expanded(child: Text(text, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35))),
      ]);
}
