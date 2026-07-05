import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// Read-only view of the astrologer's storefront orders + pooja bookings.
/// Fulfillment status (confirmed → packed → shipped → delivered) and booking
/// status (confirmed → contacted → done) are ADMIN-controlled — the astrologer
/// can only see them and flag "I've sent this product to admin". No refunds.
class StoreOrdersScreen extends StatefulWidget {
  const StoreOrdersScreen({super.key});

  @override
  State<StoreOrdersScreen> createState() => _StoreOrdersScreenState();
}

class _StoreOrdersScreenState extends State<StoreOrdersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<StoreOrder>? _orders;
  List<StoreBooking>? _bookings;
  bool _loadFailed = false; // load errored with nothing to show → offer Retry, not "no orders"

  @override
  void initState() {
    super.initState();
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
      final r = await Future.wait([api.myStoreOrders(), api.myPoojaBookings()]);
      if (!mounted) return;
      setState(() { _orders = r[0] as List<StoreOrder>; _bookings = r[1] as List<StoreBooking>; _loadFailed = false; });
    } catch (_) {
      // Don't collapse a load failure into an empty "no orders" state — flag it so
      // the tabs can offer Retry when we have nothing loaded yet.
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _markSent(StoreOrder o) async {
    setState(() {
      final i = _orders!.indexWhere((x) => x.id == o.id);
      if (i >= 0) {
        _orders![i] = StoreOrder(id: o.id, shortId: o.shortId, status: o.status, sentToAdmin: true, createdAt: o.createdAt, items: o.items);
      }
    });
    try {
      await context.read<AstrologerApi>().markOrderSent(o.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).markedAsSentToAdmin)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).failedTryAgain)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        title: Text(Strings.of(context).storefrontOrders, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.red, unselectedLabelColor: c.muted, indicatorColor: c.red,
          tabs: [
            Tab(text: Strings.of(context).ordersOrdersLength0(_orders?.length ?? 0)),
            Tab(text: Strings.of(context).bookingsBookingsLength0(_bookings?.length ?? 0)),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _ordersTab(c),
        _bookingsTab(c),
      ]),
    );
  }

  Widget _ordersTab(RgColors c) {
    if (_orders == null) return _loadFailed ? _retry(c) : const Center(child: CircularProgressIndicator());
    if (_orders!.isEmpty) return _empty(c, Icons.receipt_long_outlined, Strings.of(context).noOrdersYet, Strings.of(context).whenSeekersBuyYourProductsThey);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _orders!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _orderCard(c, _orders![i]),
      ),
    );
  }

  Widget _bookingsTab(RgColors c) {
    if (_bookings == null) return _loadFailed ? _retry(c) : const Center(child: CircularProgressIndicator());
    if (_bookings!.isEmpty) return _empty(c, Icons.local_fire_department_outlined, Strings.of(context).noBookingsYet, Strings.of(context).paidPoojaBookingsAppearHere);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _bookingCard(c, _bookings![i]),
      ),
    );
  }

  // Order status → (color, label). Admin-controlled; astrologer just sees it.
  (Color, String) _orderStatus(RgColors c, String s) => switch (s) {
        'delivered' => (c.green, Strings.of(context).delivered),
        'out_for_delivery' => (c.blue, Strings.of(context).outForDelivery),
        'shipped' => (c.blue, Strings.of(context).shipped),
        'packed' => (c.gold, Strings.of(context).packed),
        'confirmed' => (c.gold, Strings.of(context).confirmed),
        'cancelled' => (c.red, Strings.of(context).cancelled),
        _ => (c.muted, s),
      };

  (Color, String) _bookingStatus(RgColors c, String s) => switch (s) {
        'done' || 'completed' => (c.green, 'Done'),
        'contacted' => (c.blue, Strings.of(context).contacted),
        'confirmed' => (c.gold, Strings.of(context).confirmed),
        'cancelled' => (c.red, Strings.of(context).cancelled),
        _ => (c.muted, s),
      };

  Widget _orderCard(RgColors c, StoreOrder o) {
    final (sc, label) = _orderStatus(c, o.status);
    return Container(
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(Strings.of(context).orderOShortid(o.shortId), style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: TextStyle(color: sc, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
            ...o.items.map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(child: Text('${it.name}  ×${it.qty}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 13))),
                    Text('₹${it.price * it.qty}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ]),
                )),
            const SizedBox(height: 4),
            Text(Strings.of(context).yourItemsTotalOTotal(o.total), style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
        Divider(height: 1, color: c.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: o.sentToAdmin
              ? Row(children: [
                  Icon(Icons.check_circle, size: 15, color: c.green),
                  const SizedBox(width: 6),
                  Text(Strings.of(context).sentToAdminForFulfillment, style: TextStyle(color: c.green, fontSize: 12, fontWeight: FontWeight.w600)),
                ])
              : Row(children: [
                  Expanded(child: Text(Strings.of(context).handThisProductToTheAdmin, style: TextStyle(color: c.muted, fontSize: 11.5))),
                  TextButton.icon(
                    onPressed: () => _markSent(o),
                    icon: Icon(Icons.local_shipping_outlined, size: 16, color: c.red),
                    label: Text(Strings.of(context).sentToAdmin, style: TextStyle(color: c.red, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ),
                ]),
        ),
      ]),
    );
  }

  Widget _bookingCard(RgColors c, StoreBooking b) {
    final (sc, label) = _bookingStatus(c, b.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(b.poojaType, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: sc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(color: sc, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          if (b.contactName.isNotEmpty) Text(Strings.of(context).forBContactname(b.contactName), style: TextStyle(color: c.muted, fontSize: 12.5)),
          const Spacer(),
          Text('₹${b.price}', style: TextStyle(color: c.gold, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        Text(Strings.of(context).adminCoordinatesThisBookingWithThe, style: TextStyle(color: c.muted, fontSize: 11)),
      ]),
    );
  }

  // Shown when the initial load failed and we have no data yet — Retry, never a
  // false "no orders" empty state.
  Widget _retry(RgColors c) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
          child: Column(children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(Strings.of(context).couldNotLoadTapRetry, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(Strings.of(context).retry),
              style: OutlinedButton.styleFrom(foregroundColor: c.red, side: BorderSide(color: c.red)),
            ),
          ]),
        ),
      ]);

  Widget _empty(RgColors c, IconData icon, String title, String hint) => ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
          child: Column(children: [
            Icon(icon, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(hint, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
          ]),
        ),
      ]);
}
