import 'package:flutter/material.dart';

/// A smooth slide-from-right + fade page transition, used for forward
/// navigation (auth → onboarding → dashboard).
Route<T> slideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
