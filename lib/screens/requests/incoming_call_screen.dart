import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/session_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../providers/session_provider.dart';
import '../../services/callkit_service.dart';
import '../../theme/rg_colors.dart';
import 'active_session_screen.dart';
import 'call_screen.dart';

/// Full-screen "ringing" UI for an incoming chat/call/video request. The ring
/// auto-expires after 60s (matches the platform's 60s ring rule), counting as a
/// miss. Accept → active session screen; Decline → back to dashboard.
class IncomingCallScreen extends StatefulWidget {
  final ServiceKind kind;
  const IncomingCallScreen({super.key, required this.kind});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final DateTime _ringEndsAt; // fixed target → countdown is rebuild-proof
  Timer? _timer;
  bool _busy = false;

  /// Seconds left, derived from the fixed end-time (never frozen by rebuilds).
  int get _ringSecs {
    final left = _ringEndsAt.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  @override
  void initState() {
    super.initState();
    var total = context.read<SessionProvider>().incomingExpiresInSec;
    if (total <= 0) total = 60;
    _ringEndsAt = DateTime.now().add(Duration(seconds: total));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {}); // repaint → _ringSecs recomputes from wall-clock
      if (_ringSecs <= 0) {
        t.cancel();
        _dismiss(missed: true); // ring window elapsed; backend marks it missed
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    final s = Strings.of(context);
    final session = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final api = context.read<SessionApi>();
    final sessionId = session.incomingSessionId;
    final kind = widget.kind;
    final alias = session.incomingUser;
    if (sessionId == null) { _dismiss(); return; }

    // Tear down the parallel native CallKit screen (raised by the FCM push for
    // the same request) up front, so it can't re-surface over the live session.
    unawaited(CallKitService.dismiss(sessionId));

    RtcToken? token;
    try {
      // REST accept returns the Agora token for media; also join the socket room.
      token = await api.accept(sessionId);
      socket.joinSession(sessionId);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.couldNotAcceptETostring(e.toString()))));
      }
      return;
    }
    if (!mounted) return;
    session.startActive(sessionId: sessionId, kind: kind, alias: alias);
    session.clearIncoming();
    final next = kind == ServiceKind.chat
        ? const ActiveSessionScreen(kind: ServiceKind.chat)
        : CallScreen(kind: kind, token: token);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  void _decline() {
    if (_busy) return;
    _busy = true;
    _timer?.cancel();
    final session = context.read<SessionProvider>();
    final api = context.read<SessionApi>();
    final sessionId = session.incomingSessionId;
    // Optimistic: switch the screen NOW, don't wait on the network. Firing the
    // reject in the background (not awaited) means the ring dismisses on the
    // first tap instead of after a full round-trip. The backend socket/timeout
    // reconciles state, so a slow or failed POST never blocks the UI.
    if (sessionId != null) {
      unawaited(api.reject(sessionId).catchError((_) {/* socket/timeout will reconcile */}));
      // The SAME request also arrived as an FCM push that raised the native
      // CallKit screen. Tear it down too, or it re-surfaces asking accept/reject
      // again after we've already declined here. (Socket cancel/expire paths in
      // main.dart dismiss CallKit the same way; this covers the astrologer's own
      // in-app decline.)
      unawaited(CallKitService.dismiss(sessionId));
    }
    _dismiss();
  }

  void _dismiss({bool missed = false}) {
    final sid = context.read<SessionProvider>().incomingSessionId;
    context.read<SessionProvider>().clearIncoming();
    // Also tear down the NATIVE surface. The two can be up together, and the
    // ring-window timeout path used to leave CallKit running to its own timeout —
    // drawing a "missed call" notification for a session already handled here.
    if (sid != null && sid.isNotEmpty) CallKitService.dismiss(sid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(missed ? Strings.of(context).requestMissed : Strings.of(context).requestDeclined)),
    );
    Navigator.of(context).maybePop();
  }

  Color get _tint => switch (widget.kind) {
        ServiceKind.call => const Color(0xFF2E9E6B),
        ServiceKind.chat => const Color(0xFF2D6FB0),
        ServiceKind.video => const Color(0xFF6D4B9E),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.read<SessionProvider>();
    return Scaffold(
      backgroundColor: c.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(0, -0.4), radius: 1.2, colors: [_tint.withValues(alpha: 0.22), c.ground], stops: const [0, 0.7]),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Text(Strings.of(context).incomingWidgetKindLabelTolowercaseRequest(widget.kind.label.toLowerCase()), style: TextStyle(color: c.muted, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(Strings.of(context).ringsOutInRingsecsS(_ringSecs), style: TextStyle(color: _tint, fontSize: 13, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  // Pulsing avatar.
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => Container(
                      padding: EdgeInsets.all(14 + _pulse.value * 10),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _tint.withValues(alpha: 0.12 + _pulse.value * 0.08)),
                      child: child,
                    ),
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: _tint.withValues(alpha: 0.25),
                      child: Text(session.incomingUser[0], style: TextStyle(color: _tint, fontSize: 44, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(session.incomingUser, style: TextStyle(color: c.ink, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(widget.kind.icon, size: 16, color: _tint),
                    const SizedBox(width: 6),
                    Text(Strings.of(context).widgetKindLabelConsultation(widget.kind.label), style: TextStyle(color: c.muted, fontSize: 14)),
                  ]),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(icon: Icons.call_end, color: c.red, label: Strings.of(context).decline, enabled: !_busy, onTap: _decline),
                      _ActionButton(icon: Icons.check, color: _tint, label: Strings.of(context).accept, enabled: !_busy, onTap: _accept),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.color, required this.label, this.enabled = true, required this.onTap});
  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final active = widget.enabled;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        // Fire on tap-down (not up) so the very first touch registers instantly
        // — no perceptible delay before the screen switches.
        onTapDown: active ? (_) { setState(() => _down = true); widget.onTap(); } : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedOpacity(
            opacity: active ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 120),
            child: Container(
              height: 72, width: 72,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: 2)]),
              child: Icon(widget.icon, color: Colors.white, size: 32),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(widget.label, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
    ]);
  }
}
