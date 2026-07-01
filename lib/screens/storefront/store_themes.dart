import 'package:flutter/material.dart';

/// A storefront design template. The astrologer picks one; it's saved to the
/// backend (AstrologerProfile.storeTheme) and drives the link-in-bio preview's
/// background, accent, and card look. Keep the `key` values in sync with the
/// backend enum: ['rudraksh', 'shiva', 'cosmic', 'royal'].
class StoreTheme {
  final String key;
  final String name;
  final String tagline;
  final List<Color> bg; // page background gradient (top → bottom)
  final Color accent; // headings, ring, CTA
  final Color accent2; // secondary accent (gradient pair)
  final Color card; // link-card surface
  final Color cardBorder;
  final Color text; // primary text on bg
  final Color subtext; // muted text on bg
  final IconData motif; // decorative glyph (also the big header watermark)
  final String cta; // CTA word on each link card's pill ("Get", "Book", etc.)

  const StoreTheme({
    required this.key,
    required this.name,
    required this.tagline,
    required this.bg,
    required this.accent,
    required this.accent2,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.subtext,
    required this.motif,
    this.cta = 'View',
  });
}

/// Parse a 6-digit hex (#RRGGBB) to a Color, or [fallback] if malformed.
Color _hexColor(dynamic v, Color fallback) {
  if (v is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) {
    return Color(int.parse('FF${v.substring(1)}', radix: 16));
  }
  return fallback;
}

/// Build a [StoreTheme] from an AI-generated layout spec map (bgGradient, shades,
/// accent, accent2…) so the AI design renders through the SAME preview widgets
/// as the preset themes. Card/text colours derive from the spec with defaults.
StoreTheme storeThemeFromAiSpec(Map<String, dynamic> spec) {
  final bg = (spec['bgGradient'] as List?)?.cast<dynamic>() ?? const [];
  final shades = (spec['shades'] as List?)?.cast<dynamic>() ?? const [];
  final accent = _hexColor(spec['accent'], const Color(0xFFB98CFF));
  final accent2 = _hexColor(spec['accent2'], const Color(0xFFF2C879));
  return StoreTheme(
    key: 'ai',
    name: (spec['name'] ?? 'AI Design').toString(),
    tagline: (spec['rationale'] ?? 'AI-designed storefront').toString(),
    bg: [
      _hexColor(bg.isNotEmpty ? bg[0] : null, const Color(0xFF1A1030)),
      _hexColor(bg.length > 1 ? bg[1] : null, const Color(0xFF0A0617)),
    ],
    accent: accent,
    accent2: accent2,
    card: _hexColor(shades.isNotEmpty ? shades[0] : null, const Color(0x14FFFFFF)),
    cardBorder: accent.withValues(alpha: 0.30),
    text: const Color(0xFFFFFFFF),
    subtext: const Color(0xB3FFFFFF),
    motif: Icons.auto_awesome,
    cta: 'View',
  );
}

const kStoreThemes = <StoreTheme>[
  // Earthy rudraksh: deep browns + saffron, beads vibe.
  StoreTheme(
    key: 'rudraksh',
    name: 'Rudraksh',
    tagline: 'Earthy beads · saffron warmth',
    bg: [Color(0xFF2A1A0E), Color(0xFF120B06)],
    accent: Color(0xFFE8A33D),
    accent2: Color(0xFFB5651D),
    card: Color(0xFF34230F),
    cardBorder: Color(0x33E8A33D),
    text: Color(0xFFF6ECDD),
    subtext: Color(0xFFC9B79B),
    motif: Icons.spa,
    cta: 'Shop',
  ),
  // Shiva: RED Rudra energy — ember/crimson with ash highlights, trishul motif.
  StoreTheme(
    key: 'shiva',
    name: 'Shiva',
    tagline: 'Rudra ember · trishul fire',
    bg: [Color(0xFF3A0A0A), Color(0xFF120303)],
    accent: Color(0xFFFF5436),
    accent2: Color(0xFFE0B7A0),
    card: Color(0xFF3B1411),
    cardBorder: Color(0x44FF5436),
    text: Color(0xFFFBE9E4),
    subtext: Color(0xFFD8A99B),
    motif: Icons.change_history,
    cta: 'Seek',
  ),
  // Cosmic: deep violet + starlight gold.
  StoreTheme(
    key: 'cosmic',
    name: 'Cosmic',
    tagline: 'Nebula violet · starlight',
    bg: [Color(0xFF1C1030), Color(0xFF0A0617)],
    accent: Color(0xFFB98CFF),
    accent2: Color(0xFFF2C879),
    card: Color(0xFF241640),
    cardBorder: Color(0x33B98CFF),
    text: Color(0xFFF1EAFB),
    subtext: Color(0xFFB7A9D0),
    motif: Icons.auto_awesome,
    cta: 'Explore',
  ),
  // Royal: maroon + gold, regal temple feel.
  StoreTheme(
    key: 'royal',
    name: 'Royal',
    tagline: 'Maroon · temple gold',
    bg: [Color(0xFF2B0B12), Color(0xFF140509)],
    accent: Color(0xFFD4AF37),
    accent2: Color(0xFFE0556B),
    card: Color(0xFF341017),
    cardBorder: Color(0x33D4AF37),
    text: Color(0xFFF7E9CE),
    subtext: Color(0xFFCBA98E),
    motif: Icons.workspace_premium,
    cta: 'Book',
  ),
  // ── AI-styled premium cosmic presets (same lush gradient look as the AI
  //    designer output) ──
  // Aurora: teal–emerald nebula with moonstone silver glow.
  StoreTheme(
    key: 'aurora',
    name: 'Aurora',
    tagline: 'Emerald nebula · moonstone',
    bg: [Color(0xFF06231F), Color(0xFF03110E)],
    accent: Color(0xFF3FD8B4),
    accent2: Color(0xFFBFE9D8),
    card: Color(0xFF0C3229),
    cardBorder: Color(0x333FD8B4),
    text: Color(0xFFE9FBF5),
    subtext: Color(0xFFA9CFC4),
    motif: Icons.auto_awesome,
    cta: 'Discover',
  ),
  // Twilight: indigo → rose dusk, iridescent y2k-mystic vibe.
  StoreTheme(
    key: 'twilight',
    name: 'Twilight',
    tagline: 'Indigo dusk · rose glow',
    bg: [Color(0xFF241436), Color(0xFF0E0718)],
    accent: Color(0xFFC77DFF),
    accent2: Color(0xFFFF9EC4),
    card: Color(0xFF2E1B47),
    cardBorder: Color(0x33C77DFF),
    text: Color(0xFFF4EAFB),
    subtext: Color(0xFFC3B0DD),
    motif: Icons.nightlight_round,
    cta: 'Begin',
  ),
  // Sapphire: deep ocean blue + cyan starlight.
  StoreTheme(
    key: 'sapphire',
    name: 'Sapphire',
    tagline: 'Deep blue · cyan stars',
    bg: [Color(0xFF0A1B3D), Color(0xFF040B1C)],
    accent: Color(0xFF5AA9FF),
    accent2: Color(0xFF8FE0FF),
    card: Color(0xFF122A52),
    cardBorder: Color(0x335AA9FF),
    text: Color(0xFFE8F1FF),
    subtext: Color(0xFFA6BEDD),
    motif: Icons.blur_on,
    cta: 'Consult',
  ),
  // Lotus: rose-gold + blush, soft sacred elegance.
  StoreTheme(
    key: 'lotus',
    name: 'Lotus',
    tagline: 'Rose gold · blush petals',
    bg: [Color(0xFF2E1220), Color(0xFF150710)],
    accent: Color(0xFFF2B8C6),
    accent2: Color(0xFFE8C07D),
    card: Color(0xFF3A1A2A),
    cardBorder: Color(0x33F2B8C6),
    text: Color(0xFFFBECF1),
    subtext: Color(0xFFD6B3C0),
    motif: Icons.local_florist,
    cta: 'Bless',
  ),
];

StoreTheme storeThemeByKey(String? key) =>
    kStoreThemes.firstWhere((t) => t.key == key, orElse: () => kStoreThemes.first);
