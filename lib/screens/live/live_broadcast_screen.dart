import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/live_api.dart';
import '../../api/session_api.dart' show RtcToken;
import '../../api/socket_service.dart';
import '../../providers/session_provider.dart';
import '../../i18n/strings.dart';
import '../../services/agora_live.dart';
import '../../theme/rg_colors.dart';
import 'live_recap_screen.dart';

/// The astrologer's REAL live broadcast. Publishes camera + mic via Agora
/// (broadcaster role), shows the live comment stream, superchats and the AI
/// poll (all arriving over the socket room `live:<id>`), and ends the broadcast.
class LiveBroadcastScreen extends StatefulWidget {
  final String liveSessionId;
  final String title;
  final String topic;
  final RtcToken token;
  final DateTime? startedAt; // broadcast start → elapsed timer (defaults to now)
  const LiveBroadcastScreen({
    super.key,
    required this.liveSessionId,
    required this.title,
    required this.topic,
    required this.token,
    this.startedAt,
  });

  @override
  State<LiveBroadcastScreen> createState() => _LiveBroadcastScreenState();
}

class _LiveBroadcastScreenState extends State<LiveBroadcastScreen> with WidgetsBindingObserver {
  final _agora = AgoraLive();
  final _scroll = ScrollController();
  final _comments = <Map<String, dynamic>>[];

  int _viewers = 0;
  int _superTotal = 0;
  bool _mediaReady = false;
  bool _ending = false;
  Map<String, dynamic>? _poll; // {id, question, options:[{id,text,votes}], totalVotes}

  // App-minimize grace: when the astrologer backgrounds the app we pause for 10s;
  // if they don't return, the broadcast auto-ends (backend also auto-ends if the
  // socket fully drops, e.g. the app is killed or the internet is cut).
  Timer? _bgTimer;
  static const _bgGrace = Duration(seconds: 10);

  // Live elapsed timer (shown to the broadcaster, matching the audience view).
  late final DateTime _startedAt;
  Timer? _ticker;

  SocketService get _socket => context.read<SocketService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = widget.startedAt ?? DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_ending) setState(() {});
    });
    _start();
  }

  /// Elapsed since the broadcast started, as m:ss (or h:mm:ss past an hour).
  String get _elapsed {
    var s = DateTime.now().difference(_startedAt).inSeconds;
    if (s < 0) s = 0;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ending) return;
    if (state == AppLifecycleState.resumed) {
      // Came back in time → cancel the pending auto-end.
      _bgTimer?.cancel();
      _bgTimer = null;
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Minimized/backgrounded → start the 10s grace, then auto-end if still away.
      _bgTimer ??= Timer(_bgGrace, () {
        if (mounted && !_ending) _end(auto: true);
      });
    }
  }

  Future<void> _start() async {
    final ok = await _agora.startBroadcast(widget.token);
    if (mounted) setState(() => _mediaReady = ok);

    // Join the socket room + attach live listeners.
    final s = _socket.raw;
    if (s != null) {
      s.emit('join-live', {'liveSessionId': widget.liveSessionId});
      s.on('live-comment', _onComment);
      s.on('live-gift', _onGift);
      s.on('live-viewers', _onViewers);
      s.on('live-poll', _onPoll);
      s.on('live-poll-tally', _onPoll);
    }
  }

  void _onComment(dynamic d) {
    final m = _unwrap(d);
    if (m['liveSessionId'] != widget.liveSessionId) return;
    setState(() => _comments.add(m));
    _autoscroll();
  }

  void _onGift(dynamic d) {
    final m = _unwrap(d);
    if (m['liveSessionId'] != widget.liveSessionId) return;
    setState(() {
      _superTotal = (m['superchatTotal'] as num?)?.toInt() ?? _superTotal;
      _comments.add({...m, '_kind': 'gift'});
    });
    _autoscroll();
  }

  void _onViewers(dynamic d) {
    final m = _unwrap(d);
    if (m['liveSessionId'] != widget.liveSessionId) return;
    setState(() => _viewers = (m['viewerCount'] as num?)?.toInt() ?? _viewers);
  }

  /// How long the pinned poll stays on the astrologer's screen before it closes
  /// itself. Long enough to watch the tally fill in, short enough that it isn't
  /// still covering the broadcast ten minutes later.
  static const _pollPinDuration = Duration(minutes: 3);
  Timer? _pollCloseTimer;

  void _onPoll(dynamic d) {
    final m = _unwrap(d);
    setState(() => _poll = m);
    // Restart the window on each update so a poll that is actively collecting
    // votes isn't dismissed mid-flow.
    _pollCloseTimer?.cancel();
    if (m.isNotEmpty) {
      _pollCloseTimer = Timer(_pollPinDuration, () {
        if (mounted) setState(() => _poll = null);
      });
    }
  }

  Map<String, dynamic> _unwrap(dynamic d) {
    var v = d;
    if (v is List) v = v.isNotEmpty ? v.first : null;
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  void _autoscroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _runPoll() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<LiveApi>().createPoll(widget.liveSessionId);
      // Confirm the send. Generating the poll takes a moment (it's an LLM call),
      // so without this the astrologer taps and sees nothing change and can't
      // tell whether it worked.
      messenger.showSnackBar(const SnackBar(
        content: Text('Poll sent — results will appear here'),
        duration: Duration(seconds: 2),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send the poll. Try again.')));
    }
  }

  Future<void> _end({bool auto = false}) async {
    if (_ending) return;
    _bgTimer?.cancel();
    setState(() => _ending = true);
    try {
      // 'minimize' when auto-ended from the background grace; 'manual' on tap.
      await context.read<LiveApi>().end(widget.liveSessionId, reason: auto ? 'minimize' : 'manual');
    } catch (_) {}
    await _teardown();
    // Clear the LOCAL busy state and re-assert availability. The server already
    // drops the busy flag and re-derives presence on endLive, but this screen
    // never told the provider, so the dashboard kept showing
    // "Busy — in a consultation" after a live ended while seekers correctly saw
    // the astrologer as available. Re-asserting also covers the case where the
    // Agora teardown stalled the socket through the server's broadcast.
    if (mounted) {
      final s = context.read<SessionProvider>();
      s.setInSession(false);
      if (s.isOnline) context.read<SocketService>().setOnline(true);
    }
    if (!mounted) return;
    if (auto) {
      // Auto-ended from background: no foreground recap to show — just pop out.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Strings.of(context).liveEndedYouLeftTheBroadcast)),
      );
      Navigator.of(context).pop();
      return;
    }
    // Manual end → replace the broadcast screen with the full recap (moderation
    // scorecard + poll tallies + AI recap) and auto-prompt the feedback sheet.
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LiveRecapScreen(liveSessionId: widget.liveSessionId, showFeedback: true),
    ));
  }

  Future<void> _teardown() async {
    final s = _socket.raw;
    if (s != null) {
      s.emit('leave-live', {'liveSessionId': widget.liveSessionId});
      s.off('live-comment', _onComment);
      s.off('live-gift', _onGift);
      s.off('live-viewers', _onViewers);
      s.off('live-poll', _onPoll);
      s.off('live-poll-tally', _onPoll);
    }
    await _agora.stop();
  }

  @override
  void dispose() {
    _bgTimer?.cancel();
    _pollCloseTimer?.cancel();
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    _scroll.dispose();
    _agora.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // ── Video (local camera preview) ──
              Expanded(
                flex: 5,
                child: Stack(children: [
                  Positioned.fill(child: _videoArea(c)),
                  Positioned(
                    top: 12, left: 12, right: 12,
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.circle, color: Colors.white, size: 8), const SizedBox(width: 5),
                          Text(Strings.of(context).live, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      _pill(Icons.timer_outlined, _elapsed),
                      const SizedBox(width: 8),
                      _pill(Icons.visibility, '$_viewers'),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.smart_toy, color: c.mint, size: 13), const SizedBox(width: 5),
                          Text(Strings.of(context).aiMod, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                  ),
                  Positioned(
                    left: 12, bottom: 12, right: 12,
                    child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  if (_superTotal > 0)
                    Positioned(
                      right: 12, bottom: 44,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(20)),
                        child: Text(Strings.of(context).supertotalInGifts(_superTotal), style: const TextStyle(color: Color(0xFF1A1408), fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                ]),
              ),

              // ── Comments + poll + controls ──
              // Height follows the CONTENT (capped) instead of a fixed 6/11
              // share, so the camera preview gets the screen and the astrologer
              // can actually see themselves. The poll stays pinned above the
              // comments with its live vote percentages.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.46),
                child: Container(
                  decoration: BoxDecoration(color: c.ground, borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_poll != null) _pollCard(c, _poll!),
                    Flexible(child: _commentList(c)),
                    _controls(c),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoArea(RgColors c) {
    if (_mediaReady && _agora.engine != null && !_agora.camOff) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: _agora.engine!,
          canvas: const VideoCanvas(uid: 0), // local preview
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.redDeep, const Color(0xFF1A0E0C)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Center(child: Icon(_agora.camOff ? Icons.videocam_off : Icons.person, color: Colors.white24, size: 90)),
    );
  }

  Widget _commentList(RgColors c) {
    if (_comments.isEmpty) {
      // Sized to its text, not centred in the box: the panel is now
      // content-height, so a Center would re-expand it and shrink the preview.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(Strings.of(context).commentsWillAppearHere, style: TextStyle(color: c.muted)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _comments.length,
      itemBuilder: (_, i) {
        final m = _comments[i];
        if (m['_kind'] == 'gift') return _giftLine(c, m);
        return _commentLine(c, m);
      },
    );
  }

  Widget _commentLine(RgColors c, Map<String, dynamic> m) {
    final user = (m['user'] is Map) ? Map<String, dynamic>.from(m['user']) : {};
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(text: '${user['name'] ?? 'Guest'}  ', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 13)),
          TextSpan(text: (m['text'] ?? '').toString(), style: TextStyle(color: c.ink, fontSize: 13.5)),
        ]),
      ),
    );
  }

  Widget _giftLine(RgColors c, Map<String, dynamic> m) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.gold.withValues(alpha: 0.9), c.gold.withValues(alpha: 0.55)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.bolt, color: Color(0xFF1A1408), size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${m['fromName'] ?? 'Guest'} sent ${m['gift'] ?? 'a gift'} · ₹${m['amountRupees'] ?? ''}',
                style: const TextStyle(color: Color(0xFF1A1408), fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
      );

  Widget _pollCard(RgColors c, Map<String, dynamic> poll) {
    final options = (poll['options'] as List?) ?? [];
    final total = (poll['totalVotes'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.violet)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.poll_outlined, size: 16, color: c.violet), const SizedBox(width: 6), Text(Strings.of(context).aiPollLive, style: TextStyle(color: c.violet, fontWeight: FontWeight.w800, fontSize: 12)), const Spacer(), Text(Strings.of(context).totalVotes(total), style: TextStyle(color: c.muted, fontSize: 11))]),
        const SizedBox(height: 8),
        Text((poll['question'] ?? '').toString(), style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 8),
        ...options.map((o) {
          final opt = Map<String, dynamic>.from(o as Map);
          final votes = (opt['votes'] as num?)?.toInt() ?? 0;
          final pct = total == 0 ? 0.0 : votes / total;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Stack(children: [
              Container(height: 28, decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(8))),
              FractionallySizedBox(widthFactor: pct, child: Container(height: 28, decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)))),
              Positioned.fill(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Expanded(child: Text((opt['text'] ?? '').toString(), style: TextStyle(color: c.ink, fontSize: 12.5))), Text('${(pct * 100).round()}%', style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12))]))),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _controls(RgColors c) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: Row(children: [
          _ctrl(c, _agora.camOff ? Icons.videocam_off : Icons.videocam, () async { await _agora.toggleCamera(); setState(() {}); }),
          const SizedBox(width: 10),
          _ctrl(c, _agora.muted ? Icons.mic_off : Icons.mic, () async { await _agora.toggleMute(); setState(() {}); }),
          const SizedBox(width: 10),
          _ctrl(c, Icons.cameraswitch, () => _agora.switchCamera()),
          const SizedBox(width: 10),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _runPoll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(color: c.violet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.violet)),
              child: Row(children: [Icon(Icons.auto_awesome, size: 16, color: c.violet), const SizedBox(width: 6), Text(Strings.of(context).aiPoll, style: TextStyle(color: c.violet, fontWeight: FontWeight.w700, fontSize: 12.5))]),
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            icon: _ending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.stop_circle_outlined, size: 18),
            style: ElevatedButton.styleFrom(backgroundColor: c.red, minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 18)),
            label: Text(_ending ? Strings.of(context).ending : Strings.of(context).end),
            onPressed: _ending ? null : _end,
          ),
        ]),
      );

  Widget _ctrl(RgColors c, IconData icon, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
          child: Icon(icon, color: c.ink, size: 20),
        ),
      );

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 13), const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
