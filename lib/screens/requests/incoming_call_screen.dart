import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/session_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../providers/session_provider.dart';
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

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    final session = context.read<SessionProvider>();
    final api = context.read<SessionApi>();
    final sessionId = session.incomingSessionId;
    if (sessionId != null) {
      try { await api.reject(sessionId); } catch (_) {/* socket/timeout will reconcile */}
    }
    _dismiss();
  }

  void _dismiss({bool missed = false}) {
    context.read<SessionProvider>().clearIncoming();
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
                      _ActionButton(icon: Icons.call_end, color: c.red, label: Strings.of(context).decline, onTap: () => _decline()),
                      _ActionButton(icon: Icons.check, color: _tint, label: Strings.of(context).accept, onTap: _accept),
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.color, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 72, width: 72,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: 2)]),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
      const SizedBox(height: 10),
      Text(label, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
    ]);
  }
}
