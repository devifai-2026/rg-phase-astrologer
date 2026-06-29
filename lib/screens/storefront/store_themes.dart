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
];

StoreTheme storeThemeByKey(String? key) =>
    kStoreThemes.firstWhere((t) => t.key == key, orElse: () => kStoreThemes.first);
