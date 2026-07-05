import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart';
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/how_it_works_button.dart';
import 'add_pooja_screen.dart';
import 'add_product_screen.dart';
import 'ai_storefront_screen.dart';
import 'store_orders_screen.dart';
import 'store_preview.dart';
import 'store_preview_screen.dart';
import 'store_themes.dart';

/// Astrologer storefront hub with three tabs:
///   • Store    — the live, themed link-in-bio PREVIEW (no approval status; only
///                approved items) + the theme picker (Save persists to DB).
///   • Products — manage products (all statuses shown here).
///   • Poojas   — manage poojas (all statuses shown here).
/// Products/poojas are loaded from the backend (astrologer-owned, approval flow).
class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({super.key});

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));

  List<StoreProduct>? _products;
  List<PoojaOffering>? _poojas;
  bool _loadFailed = false; // initial load errored with nothing loaded → offer Retry
  late String _theme;
  bool _savingTheme = false;

  @override
  void initState() {
    super.initState();
    _theme = context.read<SessionProvider>().profile.storeTheme;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AstrologerApi>();
    if (mounted) setState(() => _loadFailed = false);
    try {
      final results = await Future.wait([api.myProducts(), api.myPoojas()]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<StoreProduct>;
        _poojas = results[1] as List<PoojaOffering>;
        _loadFailed = false;
      });
    } catch (_) {
      // Flag the failure instead of collapsing to empty "no products" lists.
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _saveTheme(String key) async {
    setState(() { _theme = key; _savingTheme = true; });
    try {
      await context.read<AstrologerApi>().setStoreTheme(key);
      context.read<SessionProvider>().setStoreTheme(key); // keep session in sync
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(Strings.of(context).storethemebykeyKeyNameThemeSaved(storeThemeByKey(key).name))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(Strings.of(context).couldNotSaveThemeTryAgain)));
      }
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  Future<void> _delete({StoreProduct? product, PoojaOffering? pooja}) async {
    final api = context.read<AstrologerApi>();
    try {
      if (product?.id != null) {
        await api.deleteProduct(product!.id!);
        setState(() => _products?.removeWhere((x) => x.id == product.id));
      } else if (pooja?.id != null) {
        await api.deletePooja(pooja!.id!);
        setState(() => _poojas?.removeWhere((x) => x.id == pooja.id));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).deleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final onManageTab = _tabs.index > 0;
    final isPooja = _tabs.index == 2;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        title: Text(Strings.of(context).myStorefront, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: Strings.of(context).storefrontOrders2,
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreOrdersScreen())),
          ),
          const HowItWorksButton(moduleKey: 'storefront', compact: true),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.red,
          unselectedLabelColor: c.muted,
          indicatorColor: c.red,
          tabs: [
            Tab(text: Strings.of(context).store),
            Tab(text: Strings.of(context).productsProductsLength0(_products?.length ?? 0)),
            Tab(text: Strings.of(context).poojasPoojasLength0(_poojas?.length ?? 0)),
          ],
        ),
      ),
      floatingActionButton: onManageTab
          ? FloatingActionButton.extended(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(isPooja ? Strings.of(context).listPooja : Strings.of(context).listProduct),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => isPooja ? const AddPoojaScreen() : const AddProductScreen(),
                ));
                _load(); // refresh after returning from the add screen
              },
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Store: themed preview + theme picker ──
          _StoreTab(
            theme: _theme,
            saving: _savingTheme,
            onPick: _saveTheme,
            products: (_products ?? []).where((p) => p.status == ProductStatus.approved).toList(),
            poojas: (_poojas ?? []).where((p) => p.status == ProductStatus.approved).toList(),
          ),
          // ── Products manage ──
          _ManageList<StoreProduct>(
            items: _products,
            loadFailed: _loadFailed,
            emptyLabel: Strings.of(context).noProductsYet,
            emptyHint: Strings.of(context).tapListProductToAddYour,
            onRefresh: _load,
            itemBuilder: (p) => _ManageCard(
              title: p.name,
              priceLine: p.mrp > p.price ? '₹${p.price}  ·  ₹${p.mrp}' : '₹${p.price}',
              image: p.image,
              fallbackIcon: Icons.inventory_2_outlined,
              status: p.status,
              adminNote: p.adminNote,
              commissionLine: p.status == ProductStatus.approved
                  ? Strings.of(context).adminPCommissionpercentYouEarnP(p.commissionPercent, p.earnPerSale, p.unitsSold)
                  : null,
              onDelete: () => _delete(product: p),
            ),
          ),
          // ── Poojas manage ──
          _ManageList<PoojaOffering>(
            items: _poojas,
            loadFailed: _loadFailed,
            emptyLabel: Strings.of(context).noPoojasYet,
            emptyHint: Strings.of(context).tapListPoojaToAddYour,
            onRefresh: _load,
            itemBuilder: (p) => _ManageCard(
              title: p.name,
              priceLine: '₹${p.price}${p.durationNote.isNotEmpty ? ' · ${p.durationNote}' : ''}',
              image: p.image,
              fallbackIcon: Icons.local_fire_department,
              status: p.status,
              adminNote: p.adminNote,
              commissionLine: p.status == ProductStatus.approved
                  ? Strings.of(context).adminPCommissionpercentYouEarnP2(p.commissionPercent, p.earnPerBooking, p.booked)
                  : null,
              onDelete: () => _delete(pooja: p),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Store tab (preview + themes) ───────────────────

class _StoreTab extends StatelessWidget {
  final String theme;
  final bool saving;
  final ValueChanged<String> onPick;
  final List<StoreProduct> products;
  final List<PoojaOffering> poojas;
  const _StoreTab({required this.theme, required this.saving, required this.onPick, required this.products, required this.poojas});

  /// Open a full-screen preview of [t] (exactly the seeker view) without
  /// selecting/saving it — lets the astrologer try any theme before committing.
  void _previewTheme(BuildContext context, StoreTheme t, List<StoreProduct> products, List<PoojaOffering> poojas) {
    final profile = context.read<SessionProvider>().profile;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StorePreviewScreen(
        theme: t,
        name: profile.displayName,
        bio: profile.bio,
        avatar: profile.avatar,
        coverPhoto: profile.coverPhoto,
        rating: profile.rating,
        reviewCount: profile.reviewCount,
        followers: profile.followers,
        products: products,
        poojas: poojas,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final profile = context.watch<SessionProvider>().profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Theme picker.
        Text(Strings.of(context).storefrontDesign, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Text(Strings.of(context).pickATemplateItSavesTo, style: TextStyle(color: c.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kStoreThemes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final t = kStoreThemes[i];
              final on = t.key == theme;
              return SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: saving ? null : () => onPick(t.key),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: t.bg, begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: on ? t.accent : c.line, width: on ? 2 : 1),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(t.motif, color: t.accent, size: 16),
                              const Spacer(),
                              if (on) Icon(Icons.check_circle, color: t.accent, size: 16),
                            ]),
                            const Spacer(),
                            Text(t.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(t.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.subtext, fontSize: 9.5, height: 1.2)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Preview this theme full-screen WITHOUT selecting/saving it.
                    SizedBox(
                      height: 28,
                      child: OutlinedButton.icon(
                        onPressed: () => _previewTheme(context, t, products, poojas),
                        icon: const Icon(Icons.visibility_outlined, size: 14),
                        label: const Text('Preview', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink,
                          side: BorderSide(color: c.line),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── "Let the Stars design your storefront" (AI) entry ──
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiStorefrontScreen())),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [c.violet, c.indigo], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Strings.of(context).letTheStarsDesignYourStorefront,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.25)),
                  const SizedBox(height: 3),
                  Text(Strings.of(context).aUniqueAiCosmicThemeCrafted,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
        const SizedBox(height: 18),

        Row(children: [
          Text(Strings.of(context).livePreview2, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(width: 8),
          Text(Strings.of(context).whatSeekersSee, style: TextStyle(color: c.muted, fontSize: 11.5)),
        ]),
        const SizedBox(height: 12),
        // The actual link-in-bio store preview (no approval status shown).
        StorePreview(
          theme: storeThemeByKey(theme),
          name: profile.displayName,
          bio: profile.bio,
          avatar: profile.avatar,
          coverPhoto: profile.coverPhoto,
          rating: profile.rating,
          reviewCount: profile.reviewCount,
          followers: profile.followers,
          products: products,
          poojas: poojas,
        ),
      ],
    );
  }
}

// ──────────────────────────────── Manage list ──────────────────────────────

class _ManageList<T> extends StatelessWidget {
  final List<T>? items;
  final bool loadFailed;
  final String emptyLabel;
  final String emptyHint;
  final Future<void> Function() onRefresh;
  final Widget Function(T) itemBuilder;
  const _ManageList({required this.items, this.loadFailed = false, required this.emptyLabel, required this.emptyHint, required this.onRefresh, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    if (items == null) {
      // Nothing loaded: Retry on failure, else still loading.
      if (loadFailed) {
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
            child: Column(children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: c.muted),
              const SizedBox(height: 12),
              Text(Strings.of(context).couldNotLoadTapRetry, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(Strings.of(context).retry),
                style: OutlinedButton.styleFrom(foregroundColor: c.red, side: BorderSide(color: c.red)),
              ),
            ]),
          ),
        ]);
      }
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: items!.isEmpty
          ? ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
                child: Column(children: [
                  Icon(Icons.storefront_outlined, size: 48, color: c.muted),
                  const SizedBox(height: 12),
                  Text(emptyLabel, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(emptyHint, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
                ]),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: items!.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => itemBuilder(items![i]),
            ),
    );
  }
}

/// A manage-card: shows the item with its APPROVAL STATUS (Live/Review/Fix),
/// admin note on rejection, commission line on approval, and a delete action.
class _ManageCard extends StatelessWidget {
  final String title;
  final String priceLine;
  final String? image;
  final IconData fallbackIcon;
  final ProductStatus status;
  final String? adminNote;
  final String? commissionLine;
  final VoidCallback onDelete;
  const _ManageCard({
    required this.title,
    required this.priceLine,
    required this.image,
    required this.fallbackIcon,
    required this.status,
    required this.adminNote,
    required this.commissionLine,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final (Color sc, String label) = switch (status) {
      ProductStatus.approved => (c.green, 'Live'),
      ProductStatus.pending => (c.gold, Strings.of(context).inReview),
      ProductStatus.rejected => (c.red, Strings.of(context).needsFix),
    };
    final hasImg = image != null && image!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              height: 56, width: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(13)),
              child: hasImg
                  ? Image.network(image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: c.gold))
                  : Icon(fallbackIcon, color: c.gold, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(priceLine, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(status.icon, size: 11, color: sc),
                  const SizedBox(width: 3),
                  Text(label, style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(8),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 18, color: c.muted)),
              ),
            ]),
          ]),
        ),
        if (commissionLine != null || (status == ProductStatus.rejected && adminNote != null)) ...[
          Divider(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
            child: status == ProductStatus.rejected && adminNote != null
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.feedback_outlined, size: 13, color: c.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(Strings.of(context).adminAdminnote(adminNote!), style: TextStyle(color: c.muted, fontSize: 11.5, height: 1.3))),
                  ])
                : Text(commissionLine!, style: TextStyle(color: c.muted, fontSize: 11.5)),
          ),
        ],
      ]),
    );
  }
}
