import 'dart:io';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import 'store_themes.dart';

/// The themed, public-facing link-in-bio storefront. Renders a cover banner +
/// overlapping profile photo, name/bio/stats, then a column of tappable "link"
/// cards (products + poojas). NO approval status is shown here — only live
/// items are passed in. Fully driven by [theme].
class StorePreview extends StatelessWidget {
  final StoreTheme theme;
  final String name;
  final String bio;
  final String? avatar;
  final String? coverPhoto;
  final double rating;
  final int reviewCount;
  final int followers;
  final List<StoreProduct> products;
  final List<PoojaOffering> poojas;
  /// AI-generated hero/background image URL. When set, it is used as the cover
  /// (and the gradient still shows below it), so the AI design previews exactly
  /// as the seeker sees it.
  final String? aiHeroImage;

  const StorePreview({
    super.key,
    required this.theme,
    required this.name,
    required this.bio,
    required this.avatar,
    required this.coverPhoto,
    required this.rating,
    required this.reviewCount,
    required this.followers,
    required this.products,
    required this.poojas,
    this.aiHeroImage,
  });

  ImageProvider? _img(String? v) {
    if (v == null || v.isEmpty) return null;
    return v.startsWith('http') ? NetworkImage(v) : FileImage(File(v)) as ImageProvider;
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final t = theme;
    // Prefer the AI hero image as the cover when provided.
    final cover = (aiHeroImage != null && aiHeroImage!.isNotEmpty) ? _img(aiHeroImage) : _img(coverPhoto);
    final pic = _img(avatar);
    final handle = name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: t.bg, begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        children: [
          // ── Cover + big themed motif watermark + overlapping profile pic ──
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                height: 120, width: double.infinity,
                child: cover != null
                    ? Image(image: cover, fit: BoxFit.cover)
                    : DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.55), t.accent2.withValues(alpha: 0.18)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
              ),
              // Large faint theme glyph so each template reads as its own world.
              Positioned(
                right: -10, top: -14,
                child: Icon(t.motif, size: 130, color: t.accent.withValues(alpha: cover != null ? 0.22 : 0.30)),
              ),
              // scrim so the profile pic + name read on any cover
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, t.bg.first.withValues(alpha: 0.95)]),
                  ),
                ),
              ),
              // Theme name badge (top-left) — extra cue that the design changed.
              Positioned(
                top: 10, left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.motif, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(t.name, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
              Positioned(
                bottom: -34, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [t.accent, t.accent2]),
                      boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 1)],
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: t.card,
                      backgroundImage: pic,
                      child: pic == null
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'A', style: TextStyle(color: t.accent, fontWeight: FontWeight.w800, fontSize: 28))
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 42),

          // ── Name / handle / bio / stats ──
          Text(name.isEmpty ? Strings.of(context).astrologer : name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 2),
          Text('@${handle.isEmpty ? 'astrologer' : handle}', style: TextStyle(color: t.accent, fontWeight: FontWeight.w600, fontSize: 12.5)),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(bio, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.subtext, fontSize: 12, height: 1.4)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            _stat(t, Icons.star, '$rating ($reviewCount)'),
            _stat(t, Icons.favorite, _fmt(followers)),
          ]),
          const SizedBox(height: 16),

          // ── Link cards ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(children: [
              for (final p in products)
                _LinkCard(theme: t, icon: Icons.inventory_2_outlined, image: p.image, title: p.name,
                    line: p.mrp > p.price ? '₹${p.price}   ₹${p.mrp}' : '₹${p.price}'),
              for (final p in poojas)
                _LinkCard(theme: t, icon: Icons.local_fire_department, image: p.image, title: p.name,
                    line: '₹${p.price}${p.durationNote.isNotEmpty ? ' · ${p.durationNote}' : ''}'),
              if (products.isEmpty && poojas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(Strings.of(context).yourApprovedProductsPoojasAppearHere,
                      textAlign: TextAlign.center, style: TextStyle(color: t.subtext, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              Text(Strings.of(context).rudragangaStorefront, style: TextStyle(color: t.subtext.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stat(StoreTheme t, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.cardBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: t.accent),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: t.text, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _LinkCard extends StatelessWidget {
  final StoreTheme theme;
  final IconData icon;
  final String? image;
  final String title;
  final String line;
  const _LinkCard({required this.theme, required this.icon, required this.image, required this.title, required this.line});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final hasImg = image != null && image!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.cardBorder)),
      child: Row(children: [
        Container(
          height: 48, width: 48,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.25), t.accent2.withValues(alpha: 0.12)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: hasImg
              ? Image.network(image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(icon, color: t.accent, size: 22))
              : Icon(icon, color: t.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(line, style: TextStyle(color: t.subtext, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        // Themed CTA pill (word + color vary per template).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.accent, t.accent2]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t.cta, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_forward, size: 12, color: Colors.white),
          ]),
        ),
      ]),
    );
  }
}
