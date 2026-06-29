import 'package:flutter/material.dart';

/// Rudraganga brand tokens, exposed as a ThemeExtension so any widget can read
/// `Theme.of(context).extension<RgColors>()!` (or the `context.rg` helper).
///
/// Identical palette to the user app so the two apps share one visual identity.
/// The DARK set is the brand spec; the LIGHT set is a matching cream-ground
/// derivation that keeps the same crimson/gold identity.
@immutable
class RgColors extends ThemeExtension<RgColors> {
  final Color ground; // page background
  final Color ground2; // slightly lifted bands/sections
  final Color card; // glass panel over the ground
  final Color red; // primary accent (brightened logo red)
  final Color redDeep; // hover / depth — exact logo red
  final Color redSoft; // soft fills, chips
  final Color ink; // headings & body
  final Color muted; // secondary text
  final Color gold; // devotional accent (stars, the sun)
  final Color line; // hairline borders
  // Semantic accents.
  final Color violet; // video accent
  final Color indigo; // gradient partner
  final Color mint; // "available" accent
  final Color green; // online / positive
  final Color blue; // chat / info

  const RgColors({
    required this.ground,
    required this.ground2,
    required this.card,
    required this.red,
    required this.redDeep,
    required this.redSoft,
    required this.ink,
    required this.muted,
    required this.gold,
    required this.line,
    required this.violet,
    required this.indigo,
    required this.mint,
    required this.green,
    required this.blue,
  });

  /// Dark — brand tokens. Secondary accent is a muted brass/copper.
  static const dark = RgColors(
    ground: Color(0xFF0B0B0C),
    ground2: Color(0xFF121012),
    card: Color(0x0BFFFFFF),
    red: Color(0xFFE0584A),
    redDeep: Color(0xFFC0392B),
    redSoft: Color(0x29E0584A),
    ink: Color(0xFFFBF6EF),
    muted: Color(0x9EF4EFE6),
    gold: Color(0xFFC98A5E),
    line: Color(0x1AFFFFFF),
    violet: Color(0xFF6D4B9E),
    indigo: Color(0xFF3B5BA9),
    mint: Color(0xFF8FD0C0),
    green: Color(0xFF2E9E6B),
    blue: Color(0xFF2D6FB0),
  );

  /// Light — cream ground, ink text on white, crimson + copper accents.
  static const light = RgColors(
    ground: Color(0xFFFBF6EF),
    ground2: Color(0xFFF3ECE0),
    card: Color(0xFFFFFFFF),
    red: Color(0xFFC0392B),
    redDeep: Color(0xFFA42E22),
    redSoft: Color(0x1FC0392B),
    ink: Color(0xFF16140F),
    muted: Color(0x99231F18),
    gold: Color(0xFFA86A3D),
    line: Color(0x14000000),
    violet: Color(0xFF7A57AE),
    indigo: Color(0xFF4A6BC0),
    mint: Color(0xFF2E9E6B),
    green: Color(0xFF1C9963),
    blue: Color(0xFF2B6CB0),
  );

  @override
  RgColors copyWith({
    Color? ground,
    Color? ground2,
    Color? card,
    Color? red,
    Color? redDeep,
    Color? redSoft,
    Color? ink,
    Color? muted,
    Color? gold,
    Color? line,
    Color? violet,
    Color? indigo,
    Color? mint,
    Color? green,
    Color? blue,
  }) {
    return RgColors(
      ground: ground ?? this.ground,
      ground2: ground2 ?? this.ground2,
      card: card ?? this.card,
      red: red ?? this.red,
      redDeep: redDeep ?? this.redDeep,
      redSoft: redSoft ?? this.redSoft,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      gold: gold ?? this.gold,
      line: line ?? this.line,
      violet: violet ?? this.violet,
      indigo: indigo ?? this.indigo,
      mint: mint ?? this.mint,
      green: green ?? this.green,
      blue: blue ?? this.blue,
    );
  }

  @override
  RgColors lerp(ThemeExtension<RgColors>? other, double t) {
    if (other is! RgColors) return this;
    return RgColors(
      ground: Color.lerp(ground, other.ground, t)!,
      ground2: Color.lerp(ground2, other.ground2, t)!,
      card: Color.lerp(card, other.card, t)!,
      red: Color.lerp(red, other.red, t)!,
      redDeep: Color.lerp(redDeep, other.redDeep, t)!,
      redSoft: Color.lerp(redSoft, other.redSoft, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      line: Color.lerp(line, other.line, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      indigo: Color.lerp(indigo, other.indigo, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      green: Color.lerp(green, other.green, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
    );
  }
}

/// `context.rg.red` etc.
extension RgColorsX on BuildContext {
  RgColors get rg => Theme.of(this).extension<RgColors>()!;
}
