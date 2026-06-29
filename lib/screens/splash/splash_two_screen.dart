import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/astrologer_api.dart';
import '../../providers/session_provider.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/rg_logo.dart';
import '../auth/phone_login_screen.dart';
import '../dashboard/dashboard_shell.dart';

/// Second splash — the blessing/tagline over a soft crimson glow.
///
/// Session restore (persistent login): if a token is stored we validate it via
/// GET /astrologers/me/profile. The ApiClient transparently refreshes an expired
/// access token (401/403 → /auth/refresh) and replays, so a returning astrologer
/// with a valid refresh token skips OTP entirely and lands on the dashboard.
/// Only a missing/dead session falls back to the phone-login screen.
class SplashTwoScreen extends StatefulWidget {
  const SplashTwoScreen({super.key});

  @override
  State<SplashTwoScreen> createState() => _SplashTwoScreenState();
}

class _SplashTwoScreenState extends State<SplashTwoScreen> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final api = context.read<AstrologerApi>();
    final session = context.read<SessionProvider>();
    // Run the auth check and the minimum splash dwell concurrently so the
    // branding shows for at least ~1.7s either way (no jarring flash).
    final dwell = Future.delayed(const Duration(milliseconds: 1700));

    Widget next = const PhoneLoginScreen();
    if (api.tokens.hasSession) {
      try {
        final profile = await api.myProfile(); // 401/403 here auto-refreshes
        // Bind the dashboard to the real backend record (name/avatar/stats),
        // not the demo placeholder — this is the persistent-login cold start.
        session.applyServerProfile(profile);
        final user = (profile['user'] is Map)
            ? Map<String, dynamic>.from(profile['user'] as Map)
            : const <String, dynamic>{};
        // Onboarded astrologers go straight to the dashboard; anyone who hasn't
        // finished onboarding still routes through login to complete it.
        if (user['profileCompleted'] == true) next = const DashboardShell();
      } on ApiException catch (_) {
        // Dead/blocked session → token already cleared by the client; show login.
      } catch (_) {/* network hiccup → fall back to login */}
    }

    await dwell;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    return Scaffold(
      backgroundColor: c.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 1.1,
                  colors: [c.redSoft, c.ground],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RgLogo(size: 96),
                const SizedBox(height: 28),
                Text(t.appName, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.ink)),
                const SizedBox(height: 6),
                Text(
                  t.consoleName,
                  style: TextStyle(fontSize: 15, color: c.gold, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    t.splashBlessing,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.muted, height: 1.5),
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: c.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
