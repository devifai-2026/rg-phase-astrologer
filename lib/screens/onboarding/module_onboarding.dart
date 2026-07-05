import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import 'onboarding_content.dart';

/// One animated card within a module walkthrough. [mock] draws a small but
/// real-looking UI preview of the feature; the card animates it in with the
/// title + body.
class OnboardCard {
  final String title;
  final String body;
  // Optional localized builders — when set, they win over the static [title]/
  // [body] at render time (a const card can't call Strings.of(context), so
  // translatable cards pass these instead).
  final String Function(BuildContext)? titleL10n;
  final String Function(BuildContext)? bodyL10n;
  final IconData icon;
  final Color Function(RgColors) tint;
  final Widget Function(BuildContext, RgColors) mock;
  const OnboardCard({
    this.title = '',
    this.body = '',
    this.titleL10n,
    this.bodyL10n,
    required this.icon,
    required this.tint,
    required this.mock,
  });

  String resolvedTitle(BuildContext ctx) => titleL10n != null ? titleL10n!(ctx) : title;
  String resolvedBody(BuildContext ctx) => bodyL10n != null ? bodyL10n!(ctx) : body;
}

/// A named module walkthrough (a sequence of [OnboardCard]s).
class OnboardModule {
  final String key;
  final String name;
  final List<OnboardCard> cards;
  const OnboardModule({required this.key, required this.name, required this.cards});
}

/// A full-screen player for one or more modules' cards, with a paged, animated
/// walkthrough. Used both for first-login (all modules chained) and for the
/// per-module "How it works" re-run (a single module).
class ModuleOnboarding extends StatefulWidget {
  final List<OnboardModule> modules;
  final String ctaLabel; // label on the final page
  const ModuleOnboarding({super.key, required this.modules, this.ctaLabel = 'Get started'});

  /// Convenience: play a single module by key.
  static Future<void> show(BuildContext context, String moduleKey, {String cta = 'Got it'}) {
    final m = onboardModules.firstWhere((x) => x.key == moduleKey);
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ModuleOnboarding(modules: [m], ctaLabel: cta),
    ));
  }

  @override
  State<ModuleOnboarding> createState() => _ModuleOnboardingState();
}

class _ModuleOnboardingState extends State<ModuleOnboarding> {
  final _pc = PageController();
  int _page = 0;

  late final List<(OnboardModule, OnboardCard)> _all = [
    for (final m in widget.modules)
      for (final card in m.cards) (m, card),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _all.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final last = _page == _all.length - 1;
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: module label + skip.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(children: [
                Text(_all[_page].$1.name, style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.4)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(Strings.of(context).skip, style: TextStyle(color: c.muted, fontWeight: FontWeight.w600))),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: _all.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _CardView(card: _all[i].$2, active: i == _page),
              ),
            ),
            // Dots.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_all.length, (i) {
                final on = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 7,
                  width: on ? 22 : 7,
                  decoration: BoxDecoration(color: on ? c.red : c.line, borderRadius: BorderRadius.circular(4)),
                );
              }),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(last ? widget.ctaLabel : Strings.of(context).next),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders one card: an animated phone-frame mock on top, then title + body.
class _CardView extends StatefulWidget {
  final OnboardCard card;
  final bool active;
  const _CardView({required this.card, required this.active});
  @override
  State<_CardView> createState() => _CardViewState();
}

class _CardViewState extends State<_CardView> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  @override
  void didUpdateWidget(covariant _CardView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    final rise = Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(fade);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Phone-frame mock.
          Expanded(
            child: Center(
              child: FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.0).animate(fade),
                  child: _PhoneFrame(child: widget.card.mock(context, c)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: rise,
              child: Column(children: [
                Container(
                  height: 44, width: 44,
                  decoration: BoxDecoration(color: widget.card.tint(c).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
                  child: Icon(widget.card.icon, color: widget.card.tint(c), size: 24),
                ),
                const SizedBox(height: 12),
                Text(widget.card.resolvedTitle(context), textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 21)),
                const SizedBox(height: 8),
                Text(widget.card.resolvedBody(context), textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14, height: 1.5)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// A lightweight phone bezel that frames the mock UI.
class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({required this.child});
  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Container(
      width: 230,
      height: 290,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.ground2,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.line, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(color: c.ground, child: child),
      ),
    );
  }
}
