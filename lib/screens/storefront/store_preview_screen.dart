import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../theme/rg_colors.dart';
import 'store_preview.dart';
import 'store_themes.dart';

/// Full-screen preview of a storefront design — exactly what a seeker sees when
/// they open the astrologer's link-in-bio store. Opened by tapping a design's
/// preview / the "Preview" button, so the astrologer can review the AI (or
/// preset) theme at full size before making it live.
class StorePreviewScreen extends StatelessWidget {
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
  final String? aiHeroImage;

  const StorePreviewScreen({
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

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: theme.bg.isNotEmpty ? theme.bg.last : c.ground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(Strings.of(context).whatSeekersSee,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: StorePreview(
          theme: theme,
          name: name,
          bio: bio,
          avatar: avatar,
          coverPhoto: coverPhoto,
          rating: rating,
          reviewCount: reviewCount,
          followers: followers,
          products: products,
          poojas: poojas,
          aiHeroImage: aiHeroImage,
        ),
      ),
    );
  }
}
