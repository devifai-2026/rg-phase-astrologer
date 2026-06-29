import 'package:flutter/material.dart';
import 'rg_colors.dart';

/// Builds the Material 3 dark & light themes from the RG brand tokens.
/// Both modes share the crimson primary and gold secondary so the identity is
/// consistent; only the ground/ink/card tokens flip.
class AppTheme {
  static ThemeData dark() => _build(RgColors.dark, Brightness.dark);
  static ThemeData light() => _build(RgColors.light, Brightness.light);

  static ThemeData _build(RgColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.red,
      onPrimary: brightness == Brightness.dark ? const Color(0xFF1A0E0C) : Colors.white,
      secondary: c.gold,
      onSecondary: const Color(0xFF1A1408),
      surface: c.ground2,
      onSurface: c.ink,
      error: const Color(0xFFE0584A),
      onError: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: c.ground,
      extensions: [c],
      textTheme: _textTheme(base.textTheme, c),
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        foregroundColor: c.ink,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark ? c.ground2 : Colors.white,
        hintStyle: TextStyle(color: c.muted),
        labelStyle: TextStyle(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.red, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0584A)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.red,
          foregroundColor: brightness == Brightness.dark ? const Color(0xFF1A0E0C) : Colors.white,
          disabledBackgroundColor: c.redSoft,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.red),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
    );
  }

  static TextTheme _textTheme(TextTheme base, RgColors c) {
    return base.apply(bodyColor: c.ink, displayColor: c.ink).copyWith(
          displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          bodyMedium: base.bodyMedium?.copyWith(color: c.muted, height: 1.4),
        );
  }
}
