import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import 'store_preview.dart';
import 'store_themes.dart';

/// "Let the Stars design your storefront" — AI-generated storefront themes.
/// The astrologer can generate up to 3 lifetime designs, preview each, and
/// switch which one is live. Each design is a JSON spec (cosmic gradient,
/// shades, accents, an astrology SVG motif, fonts) the seeker app renders.
class AiStorefrontScreen extends StatefulWidget {
  const AiStorefrontScreen({super.key});

  @override
  State<AiStorefrontScreen> createState() => _AiStorefrontScreenState();
}

class _AiStorefrontScreenState extends State<AiStorefrontScreen> {
  List<Map<String, dynamic>> _layouts = [];
  ({int used, int limit, int remaining})? _usage;
  List<StoreProduct> _products = [];
  List<PoojaOffering> _poojas = [];
  bool _loading = true;
  bool _busy = false;

  AstrologerApi get _api => context.read<AstrologerApi>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.listStorefrontDesigns(),
        _api.storefrontDesignUsage(),
        _api.myProducts(),
        _api.myPoojas(),
      ]);
      if (!mounted) return;
      setState(() {
        _layouts = results[0] as List<Map<String, dynamic>>;
        _usage = results[1] as ({int used, int limit, int remaining});
        // Only approved items show on the live storefront preview.
        _products = (results[2] as List<StoreProduct>).where((p) => p.status == ProductStatus.approved).toList();
        _poojas = (results[3] as List<PoojaOffering>).where((p) => p.status == ProductStatus.approved).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_busy) return;
    final s = Strings.of(context);
    setState(() => _busy = true);
    try {
      await _api.generateStorefrontDesign();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.theStarsDesignedAFreshStorefront)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(String id) async {
    final s = Strings.of(context);
    setState(() => _busy = true);
    try {
      await _api.setActiveStorefrontDesign(id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.thisDesignIsNowLiveOn)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.couldNotSwitchDesign)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final remaining = _usage?.remaining ?? 0;
    final limit = _usage?.limit ?? 3;
    final canGenerate = remaining > 0 && !_busy;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        elevation: 0,
        title: Row(children: [
          Icon(Icons.auto_awesome, color: c.violet, size: 20),
          const SizedBox(width: 8),
          Text(Strings.of(context).aiStorefront, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: c.violet,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  // ── Hero CTA ──
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [c.violet, c.indigo], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.auto_fix_high, color: Colors.white, size: 30),
                      const SizedBox(height: 10),
                      Text(Strings.of(context).letTheStarsDesignYourStorefront,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, height: 1.25)),
                      const SizedBox(height: 6),
                      Text(Strings.of(context).aUniqueCosmicThemeColoursShades,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.4)),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: c.indigo, minimumSize: const Size.fromHeight(48)),
                          icon: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.auto_awesome),
                          label: Text(_busy ? Strings.of(context).theStarsAreDesigning : Strings.of(context).designMyStorefront, style: const TextStyle(fontWeight: FontWeight.w800)),
                          onPressed: canGenerate ? _generate : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        remaining > 0
                            ? Strings.of(context).remainingOfLimitFreeDesignsLeft(remaining, limit)
                            : Strings.of(context).youVeUsedAllLimitDesigns(limit),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 22),

                  if (_layouts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: Text(Strings.of(context).noDesignsYetTapTheButton,
                          textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.5))),
                    )
                  else ...[
                    Text(Strings.of(context).yourDesigns, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(Strings.of(context).tapMakeLiveToUseA, style: TextStyle(color: c.muted, fontSize: 12.5)),
                    const SizedBox(height: 14),
                    ..._layouts.map((l) => _DesignCard(
                          layout: l,
                          busy: _busy,
                          profile: context.read<SessionProvider>().profile,
                          products: _products,
                          poojas: _poojas,
                          onActivate: () => _activate((l['id'] ?? '').toString()),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}

/// A preview card for one generated storefront design: renders the FULL live
/// StorePreview (the exact seeker view) using the AI spec + generated hero
/// image, with a "Make live" / "Live" control. Mirrors the saved-theme preview.
class _DesignCard extends StatelessWidget {
  final Map<String, dynamic> layout;
  final bool busy;
  final dynamic profile; // AstrologerProfile (name/bio/avatar/rating/…)
  final List<StoreProduct> products;
  final List<PoojaOffering> poojas;
  final VoidCallback onActivate;
  const _DesignCard({
    required this.layout,
    required this.busy,
    required this.profile,
    required this.products,
    required this.poojas,
    required this.onActivate,
  });

  Color _hex(String? v, Color fallback) {
    if (v == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) return fallback;
    return Color(int.parse('FF${v.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final spec = Map<String, dynamic>.from(layout['spec'] ?? {});
    final active = layout['active'] == true;
    final accent = _hex(spec['accent'] as String?, c.violet);
    final heroImage = (spec['heroImage'] ?? '').toString();
    final heroPending = spec['heroPending'] == true;
    final theme = storeThemeFromAiSpec(spec);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? accent : c.line, width: active ? 1.8 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // FULL live storefront preview (exactly what the seeker sees).
          Stack(
            children: [
              StorePreview(
                theme: theme,
                name: profile.displayName,
                bio: profile.bio,
                avatar: profile.avatar,
                coverPhoto: profile.coverPhoto,
                rating: profile.rating,
                reviewCount: profile.reviewCount,
                followers: profile.followers,
                products: products,
                poojas: poojas,
                aiHeroImage: heroImage.isNotEmpty ? heroImage : null,
              ),
              if (heroPending)
                Positioned(
                  top: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 7),
                      Text('Painting artwork…', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ],
          ),
          // Footer: rationale + activate control.
          Container(
            color: c.ground2,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Expanded(
                child: Text(
                  (spec['rationale'] ?? '').toString().isEmpty ? Strings.of(context).aPremiumCosmicStorefrontTheme : spec['rationale'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.35),
                ),
              ),
              const SizedBox(width: 10),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: c.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, color: c.green, size: 15),
                    const SizedBox(width: 5),
                    Text('Live', style: TextStyle(color: c.green, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ]),
                )
              else
                OutlinedButton(
                  onPressed: busy ? null : onActivate,
                  style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                  child: Text(Strings.of(context).makeLive, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
