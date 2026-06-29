import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/rg_logo.dart';
import '../dashboard/dashboard_shell.dart';
import 'module_onboarding.dart';
import 'onboarding_content.dart';

/// Shown once, right after a new astrologer completes their profile. A short
/// welcome, then the full platform walkthrough (chat → call → video → AI
/// optimizer → go live → storefront), then into the dashboard.
class FirstLoginWalkthrough extends StatefulWidget {
  const FirstLoginWalkthrough({super.key});

  @override
  State<FirstLoginWalkthrough> createState() => _FirstLoginWalkthroughState();
}

class _FirstLoginWalkthroughState extends State<FirstLoginWalkthrough> {
  void _start() async {
    // Play all modules in order, then enter the dashboard.
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ModuleOnboarding(modules: firstLoginSequence, ctaLabel: Strings.of(context).enterDashboard),
    ));
    _toDashboard();
  }

  void _toDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardShell()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final steps = [
      (Icons.chat_bubble, Strings.of(context).chat, c.blue),
      (Icons.call, Strings.of(context).call, c.green),
      (Icons.videocam, Strings.of(context).video, c.violet),
      (Icons.auto_fix_high, Strings.of(context).aiOptimizer, c.violet),
      (Icons.sensors, 'Go Live', c.indigo),
      (Icons.storefront, Strings.of(context).storefront, c.gold),
    ];
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Center(child: RgLogo(size: 72)),
              const SizedBox(height: 28),
              Text(Strings.of(context).welcomeToRudraganga, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 26)),
              const SizedBox(height: 8),
              Text(
                Strings.of(context).letSTakeA1Minute,
                style: TextStyle(color: c.muted, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 28),
              // Step rail.
              ...steps.asMap().entries.map((e) {
                final (icon, label, tint) = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(children: [
                    Container(
                      height: 40, width: 40,
                      decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: tint, size: 21),
                    ),
                    const SizedBox(width: 14),
                    Text(label, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    Text('${e.key + 1}', style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                );
              }),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(icon: const Icon(Icons.play_arrow), label: Text(Strings.of(context).startTheTour), onPressed: _start),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(onPressed: _toDashboard, child: Text(Strings.of(context).skipForNow, style: TextStyle(color: c.muted, fontWeight: FontWeight.w600))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
