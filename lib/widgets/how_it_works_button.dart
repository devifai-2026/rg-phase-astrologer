import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../screens/onboarding/module_onboarding.dart';
import '../theme/rg_colors.dart';

/// A small "?" pill that re-runs a module's onboarding walkthrough. Drop it
/// into any module screen's app bar (or body) with the matching module key.
class HowItWorksButton extends StatelessWidget {
  final String moduleKey;
  final bool compact; // true = icon only (for app bars)
  const HowItWorksButton({super.key, required this.moduleKey, this.compact = false});

  void _open(BuildContext context) => ModuleOnboarding.show(context, moduleKey);

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    if (compact) {
      return IconButton(
        tooltip: Strings.of(context).howItWorks,
        icon: Icon(Icons.help_outline, color: c.gold, size: 22),
        onPressed: () => _open(context),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.gold.withValues(alpha: 0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_circle_outline, size: 15, color: c.gold),
          const SizedBox(width: 6),
          Text(Strings.of(context).howItWorks, style: TextStyle(color: c.gold, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
