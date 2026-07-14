import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/session_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../providers/session_provider.dart';
import '../../services/agora_session.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/secure_screen.dart';
import 'session_summary.dart';

/// Live audio/video consultation on the astrologer side. Joins the Agora
/// channel with the token from accept, shows remote/local video (video) or an
/// avatar (audio), with mute / speaker / camera controls + a running timer and
/// live earnings. Recording is automatic server-side. The seeker is anonymous.
class CallScreen extends StatefulWidget {
  final ServiceKind kind;
  final RtcToken? token;
  const CallScreen({super.key, required this.kind, this.token});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin, SecureScreenMixin, WidgetsBindingObserver {
  final _agora = AgoraSession();
  bool _mock = false;
  bool _endHandled = false;
  bool _ending = false; // first End tap → instant feedback, blocks repeat taps
  bool _leaving = false; // engine is being released → stop painting video views
  Timer? _ticker;

  // Drives the soft glow/pulse ring around the avatar while connecting.
  late final AnimationController _pulse;

  // Server-stamped elapsed seconds (shared with the user app → no drift).
  int get _secs => context.read<SessionProvider>().elapsedSec;

  bool get _isVideo => widget.kind == ServiceKind.video;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    final s = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final api = context.read<SessionApi>();
    s.addListener(_onSession);
    // Record the astrologer's join (both-joined handshake) + join the room.
    if (s.activeSessionId != null) socket.joinSession(s.activeSessionId!);
    _join();
    // The clock is driven by the provider's own 1s ticker (it notifies every
    // second → this screen rebuilds via context.watch), so no per-second
    // setState here. This poll only closes the race where the live
    // 'session-started' event fired before this screen mounted (FCM cold start):
    // re-pull the authoritative server startedAt until known, then stop.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!s.sessionStarted) {
        s.syncStartedAt(api);
      } else {
        _ticker?.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from background: the OS may have dropped the socket — reconnect,
    // rejoin the session room, and re-anchor the clock to server truth.
    if (state == AppLifecycleState.resumed && mounted) {
      final s = context.read<SessionProvider>();
      final socket = context.read<SocketService>();
      socket.connect();
      if (s.activeSessionId != null) socket.joinSession(s.activeSessionId!);
      s.syncStartedAt(context.read<SessionApi>());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _pulse.dispose();
    _agora.errorNotifier.removeListener(_onAgoraError);
    try { context.read<SessionProvider>().removeListener(_onSession); } catch (_) {}
    _agora.leave();
    _agora.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final token = widget.token;
    if (token == null) { setState(() => _mock = true); return; }
    _agora.errorNotifier.addListener(_onAgoraError);
    final ok = await _agora.join(token, video: _isVideo);
    if (mounted) setState(() => _mock = !ok);
  }

  void _onAgoraError() {
    final msg = _agora.errorNotifier.value;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _onSession() {
    if (!mounted || _endHandled) return;
    final s = context.read<SessionProvider>();
    // Capture the summary synchronously. The backend emits `session-ended`
    // multiple times (to-session + to-user + to-astrologer), so this listener
    // can fire more than once; _endHandled + this null-check make it idempotent.
    final summary = s.endSummary;
    if (summary != null) {
      _endHandled = true;
      s.consumeEndSummary();
      _leaveWithSummary(summary);
    }
  }

  Future<void> _leaveWithSummary(Map<String, dynamic> summary) async {
    // Grab the navigator BEFORE the await — using context after an async gap
    // (and especially using a popped navigator's context to push a dialog) is
    // what threw the red error when both sides ended at once / on video end.
    final rootNav = Navigator.of(context, rootNavigator: true);
    // STOP rendering the AgoraVideoView widgets BEFORE releasing the engine.
    // On VIDEO end, a rebuild that paints an AgoraVideoView against a just-
    // released RtcEngine throws the red-screen error. Flip _leaving first so
    // the build() guards drop the video views, then tear the engine down.
    if (mounted) setState(() => _leaving = true);
    await _agora.leave();
    if (!mounted) return;
    // Pop the call screen, then show the summary on the SURVIVING route. We push
    // the dialog via the root navigator state (still valid after the pop) rather
    // than a stale BuildContext, and only if it's still able to present.
    if (rootNav.canPop()) rootNav.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rootNav.mounted) return; // navigator gone → nothing to show on
      showAstroSessionSummary(rootNav.context, summary);
    });
  }

  Future<void> _end() async {
    // Guard against double-taps: show instant feedback on the first tap and
    // ignore repeats until the session-ended event tears the screen down.
    if (_ending || _endHandled) return;
    // Stop painting video views immediately (the engine is torn down shortly).
    setState(() { _ending = true; _leaving = true; });
    final s = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final api = context.read<SessionApi>();
    final id = s.activeSessionId;
    if (id != null) {
      socket.endSession(id);
      try { await api.end(id); } catch (_) {}
    }
  }

  String get _clock {
    final m = (_secs ~/ 60).toString().padLeft(2, '0');
    final sec = (_secs % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = context.watch<SessionProvider>();
    final showVideo = _isVideo && !_mock && !_leaving && _agora.engine != null && _agora.remoteUid != null;

    // Back minimizes the call (session stays live); a Resume pill on the
    // dashboard brings it back. Ending is explicit (the red End button).
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: _remoteView(c, s)),

          // Top scrim so header text stays legible over live video.
          if (showVideo)
            const Positioned(
              top: 0, left: 0, right: 0, height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),

          // Local camera preview — positioned BELOW the header row so it never
          // overlaps the alias / timer / earning pill. (Header occupies the top
          // ~96px incl. the safe area + the type pill row.)
          if (_isVideo && !_mock && !_leaving && _agora.engine != null)
            Positioned(
              top: 132, right: 16, width: 104, height: 146,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: AgoraVideoView(controller: VideoViewController(rtcEngine: _agora.engine!, canvas: const VideoCanvas(uid: 0))),
                ),
              ),
            ),

          // Header: seeker alias, call-type/timer, live earning indicator.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    s.activeAlias,
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _typePill(c, s),
                ])),
                const SizedBox(width: 12),
                _earningPill(c, s),
              ]),
            ),
          ),

          // Bottom scrim behind controls.
          const Positioned(
            left: 0, right: 0, bottom: 0, height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              child: Padding(
                // SafeArea already insets for the system nav; keep the extra
                // lift small. spaceEvenly + FittedBox (instead of fixed 16px
                // gaps) so all five video controls fit 360dp-wide screens —
                // the end button used to clip off-screen.
                padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width - 24,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _ctrl(Icons.mic, Icons.mic_off, _agora.muted, () async { await _agora.toggleMute(); setState(() {}); }),
                      _ctrl(Icons.volume_up, Icons.hearing, !_agora.speakerOn, () async { await _agora.toggleSpeaker(); setState(() {}); }),
                      if (_isVideo) ...[
                        _ctrl(Icons.videocam, Icons.videocam_off, _agora.cameraOff, () async { await _agora.toggleCamera(); setState(() {}); }),
                        _ctrl(Icons.cameraswitch, Icons.cameraswitch, false, () => _agora.switchCamera()),
                      ],
                      GestureDetector(
                        onTap: _ending ? null : _end,
                        child: Container(
                          height: 66, width: 66,
                          decoration: BoxDecoration(color: _ending ? c.red.withValues(alpha: 0.5) : c.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.red.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: 1)]),
                          child: _ending
                              ? const Padding(padding: EdgeInsets.all(21), child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Icon(Icons.call_end, color: Colors.white, size: 28),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // Live call-type + LIVE/Connecting indicator under the alias.
  Widget _typePill(RgColors c, SessionProvider s) {
    final live = s.sessionStarted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: live ? c.green : c.gold, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          live ? Strings.of(context).widgetKindLabelTouppercaseLive(widget.kind.label.toUpperCase()) : Strings.of(context).connecting,
          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
        ),
      ]),
    );
  }

  // Live "Earning" indicator — the astrologer's running ₹ earning (perMin ×
  // billed minutes) with the elapsed clock beneath it. perMin arrives on the
  // 'session-started' event; the exact final figure is in the end summary.
  Widget _earningPill(RgColors c, SessionProvider s) {
    final live = s.sessionStarted;
    final hasRate = s.activePerMin > 0;
    final earningText = !live ? '₹--' : (hasRate ? '₹${s.liveEarning}' : _clock);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.gold.withValues(alpha: 0.30), c.gold.withValues(alpha: 0.16)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.gold.withValues(alpha: 0.55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.payments_outlined, size: 13, color: c.gold),
          const SizedBox(width: 4),
          Text(Strings.of(context).earning, style: TextStyle(color: c.gold, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ]),
        const SizedBox(height: 1),
        Text(
          earningText,
          style: TextStyle(
            color: c.gold, fontSize: 16, fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (live && hasRate)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule, size: 10, color: c.gold.withValues(alpha: 0.85)),
            const SizedBox(width: 3),
            Text(Strings.of(context).clockSActiveperminMin(_clock, s.activePerMin),
                style: TextStyle(color: c.gold.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
      ]),
    );
  }

  Widget _remoteView(RgColors c, SessionProvider s) {
    if (_isVideo && !_mock && !_leaving && _agora.engine != null && _agora.remoteUid != null) {
      return AgoraVideoView(controller: VideoViewController.remote(
        rtcEngine: _agora.engine!,
        canvas: VideoCanvas(uid: _agora.remoteUid),
        connection: RtcConnection(channelId: s.activeSessionId),
      ));
    }
    // Audio call, mock mode, or waiting for the remote → premium centered layout.
    final live = s.sessionStarted;
    final initial = s.activeAlias.isNotEmpty ? s.activeAlias[0].toUpperCase() : '★';
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.45),
          radius: 1.1,
          colors: [c.red.withValues(alpha: 0.22), c.ground, Colors.black],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Animated pulse/glow ring while connecting; settles once live.
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = _pulse.value;
              final outer = live ? 1.0 : 1.0 + 0.18 * t;
              final fade = live ? 0.0 : (1.0 - t);
              return SizedBox(
                width: 200, height: 200,
                child: Stack(alignment: Alignment.center, children: [
                  if (!live)
                    Transform.scale(
                      scale: outer,
                      child: Container(
                        width: 160, height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.gold.withValues(alpha: 0.5 * fade), width: 2),
                        ),
                      ),
                    ),
                  child!,
                ]),
              );
            },
            child: Container(
              width: 138, height: 138,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [c.gold.withValues(alpha: 0.38), c.gold.withValues(alpha: 0.14)],
                ),
                border: Border.all(color: c.gold.withValues(alpha: 0.55), width: 2),
                boxShadow: [BoxShadow(color: c.gold.withValues(alpha: 0.30), blurRadius: 36, spreadRadius: 4)],
              ),
              alignment: Alignment.center,
              child: Text(initial, style: TextStyle(color: c.gold, fontSize: 56, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            s.activeAlias,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.3),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // Call-type + LIVE indicator.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: live ? c.green : c.gold, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(
                live ? Strings.of(context).widgetKindLabelTouppercaseLive(widget.kind.label.toUpperCase()) : Strings.of(context).connecting,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.8),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          // Big readable running timer (also the astrologer's live earning clock).
          Text(
            live ? _clock : '--:--',
            style: TextStyle(
              color: live ? Colors.white : Colors.white38,
              fontSize: 46,
              fontWeight: FontWeight.w300,
              letterSpacing: 2.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _ctrl(IconData on, IconData off, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58, width: 58,
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12)],
          ),
          child: Icon(active ? off : on, color: Colors.white, size: 24),
        ),
      );
}
