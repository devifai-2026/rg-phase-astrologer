import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import 'store_preview.dart';
import 'store_preview_screen.dart';
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
  // The two calls that drive the quota UI (designs + usage). If EITHER fails we
  // must NOT fall back to "you've used all 3" — that misreports a network error
  // as an exhausted quota. We surface a retry state instead.
  bool _loadFailed = false;

  AstrologerApi get _api => context.read<AstrologerApi>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadFailed = false; });
    // Run all four independently so one failure never blanks the others. The
    // designs + usage pair is what gates the CTA, so a failure THERE flips the
    // retry state; products/poojas are only preview extras (soft-fail to empty).
    final designsF = _api.listStorefrontDesigns();
    final usageF = _api.storefrontDesignUsage();
    final productsF = _api.myProducts().catchError((_) => <StoreProduct>[]);
    final poojasF = _api.myPoojas().catchError((_) => <PoojaOffering>[]);

    List<Map<String, dynamic>>? designs;
    ({int used, int limit, int remaining})? usage;
    var quotaFailed = false;
    try {
      designs = await designsF;
      usage = await usageF;
    } catch (_) {
      quotaFailed = true;
    }
    final products = await productsF;
    final poojas = await poojasF;
    if (!mounted) return;

    setState(() {
      if (quotaFailed || designs == null || usage == null) {
        // Couldn't load the quota/designs — keep whatever we had and show retry.
        _loadFailed = true;
      } else {
        _layouts = designs;
        _usage = usage;
        _loadFailed = false;
      }
      // Only approved items show on the live storefront preview.
      _products = products.where((p) => p.status == ProductStatus.approved).toList();
      _poojas = poojas.where((p) => p.status == ProductStatus.approved).toList();
      _loading = false;
    });
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
    // When the quota load failed, usage is null — DON'T treat that as 0 remaining
    // (that would falsely disable the button + say "used all 3"). We only know the
    // real remaining once _usage is populated.
    final hasUsage = _usage != null;
    final remaining = _usage?.remaining ?? 0;
    final limit = _usage?.limit ?? 3;
    // Can generate only when we actually have usage data showing credits left.
    final canGenerate = hasUsage && remaining > 0 && !_busy;

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
                              : Icon(_loadFailed ? Icons.refresh : Icons.auto_awesome),
                          // On a failed load the CTA becomes a Retry — the quota is
                          // unknown, so we don't pretend it's used up.
                          label: Text(
                            _busy
                                ? Strings.of(context).theStarsAreDesigning
                                : _loadFailed
                                    ? Strings.of(context).retry
                                    : Strings.of(context).designMyStorefront,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          onPressed: _busy ? null : (_loadFailed ? _load : (canGenerate ? _generate : null)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _loadFailed
                            ? Strings.of(context).couldNotLoadTapRetry
                            : remaining > 0
                                ? Strings.of(context).remainingOfLimitFreeDesignsLeft(remaining, limit)
                                : Strings.of(context).youVeUsedAllLimitDesigns(limit),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 22),

                  if (_loadFailed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: Text(Strings.of(context).couldNotLoadTapRetry,
                          textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.5))),
                    )
                  else if (_layouts.isEmpty)
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
          // FULL live storefront preview (exactly what the seeker sees). Tap to
          // open it full-screen.
          Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StorePreviewScreen(
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
                )),
                child: StorePreview(
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
              const SizedBox(width: 6),
              // Explicit full-screen Preview action.
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StorePreviewScreen(
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
                )),
                style: TextButton.styleFrom(foregroundColor: c.muted, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: Text(Strings.of(context).livePreview2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              const SizedBox(width: 4),
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
