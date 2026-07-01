import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/session_api.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../models/ai_models.dart' show CatalogueItem;
import '../../providers/session_provider.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/secure_screen.dart';
import 'image_viewer.dart';
import 'session_summary.dart';

/// A live consultation. Shows a running timer and accruing earnings at the
/// astrologer's per-minute share. Chat shows a tiny demo conversation; call /
/// video show the standard in-call controls. End → back to dashboard.
class ActiveSessionScreen extends StatefulWidget {
  final ServiceKind kind;
  const ActiveSessionScreen({super.key, required this.kind});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> with SecureScreenMixin {
  Timer? _timer;
  bool _sending = false;
  final _input = TextEditingController();

  // Read the live elapsed seconds from the provider's SERVER-stamped start
  // (shared with the user app → no drift; 0 until both have joined).
  int get _secs => context.read<SessionProvider>().elapsedSec;

  bool _endHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<SessionProvider>();
      final socket = context.read<SocketService>();
      s.setInSession(true);
      // Record the astrologer's presence in the room (both-joined handshake).
      if (s.activeSessionId != null) socket.joinSession(s.activeSessionId!);
    });
    // React to a session-ended pushed by the server (either side ended).
    context.read<SessionProvider>().addListener(_onSession);
    // The visible clock is now driven by the provider's own 1s ticker (it
    // notifies every second → this screen rebuilds via context.watch), so we no
    // longer setState() here. This poll only closes the FCM cold-start race:
    // keep re-pulling the authoritative server startedAt until it's known, then
    // stop. Once known, the provider ticker keeps both apps in lock-step.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final s = context.read<SessionProvider>();
      if (!s.sessionStarted) {
        s.syncStartedAt(context.read<SessionApi>());
      } else {
        _timer?.cancel(); // start time locked in — nothing left to poll
      }
    });
  }

  void _onSession() {
    if (!mounted || _endHandled) return;
    final s = context.read<SessionProvider>();
    if (s.endSummary != null) {
      _endHandled = true;
      _showSummaryAndLeave(s);
    }
  }

  Future<void> _showSummaryAndLeave(SessionProvider s) async {
    _timer?.cancel();
    final summary = s.endSummary!;
    s.consumeEndSummary();
    s.setInSession(false);
    if (!mounted) return;
    // Capture the ROOT navigator + its context BEFORE popping, so the summary
    // dialog shows over the dashboard (not the about-to-be-disposed screen).
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) rootNav.pop(); // back to dashboard
    final ctx = rootNav.context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showAstroSessionSummary(ctx, summary);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    try { context.read<SessionProvider>().removeListener(_onSession); } catch (_) {}
    _input.dispose();
    super.dispose();
  }

  int get _earnPerMin {
    final p = context.read<SessionProvider>().profile;
    return switch (widget.kind) {
      ServiceKind.call => p.callRate.earnPerMin,
      ServiceKind.chat => p.chatRate.earnPerMin,
      ServiceKind.video => p.videoRate.earnPerMin,
    };
  }

  /// Earnings accrue PER MINUTE (billed at the start of each minute), not per
  /// second — matches the backend's per-minute billing.
  int get _liveEarn {
    if (!context.read<SessionProvider>().sessionStarted) return 0;
    final minutesCharged = (_secs ~/ 60) + 1; // minute 1 charged at 00:00
    return minutesCharged * _earnPerMin;
  }

  String get _clock {
    final secs = _secs;
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color get _tint => switch (widget.kind) {
        ServiceKind.call => const Color(0xFF2E9E6B),
        ServiceKind.chat => const Color(0xFF2D6FB0),
        ServiceKind.video => const Color(0xFF6D4B9E),
      };

  /// End from the astrologer side. We just tell the server; the resulting
  /// 'session-ended' event drives the summary popup + return to dashboard
  /// (via _onSession) — same path as when the USER ends, so both are identical.
  Future<void> _end() async {
    final session = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final api = context.read<SessionApi>();
    final id = session.activeSessionId;
    if (id != null) {
      socket.endSession(id);
      try { await api.end(id); } catch (_) {}
    }
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final session = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final id = session.activeSessionId;
    if (id == null) return;
    _input.clear();
    socket.sendMessage(id, message: text);
    session.addLiveMessage({'sessionId': id, 'kind': 'user', 'sender': 'me', 'message': text, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<void> _sendImage() async {
    final session = context.read<SessionProvider>();
    final socket = context.read<SocketService>();
    final api = context.read<AstrologerApi>();
    final messenger = ScaffoldMessenger.of(context);
    final s = Strings.of(context);
    final id = session.activeSessionId;
    if (id == null || _sending) return;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (x == null) return;
    setState(() => _sending = true);
    try {
      final url = await api.uploadImage(File(x.path));
      socket.sendMessage(id, mediaUrl: url, mediaType: 'image');
      session.addLiveMessage({'sessionId': id, 'kind': 'user', 'sender': 'me', 'mediaUrl': url, 'timestamp': DateTime.now().toIso8601String()});
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.couldNotSendImage)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareProduct() async {
    final session = context.read<SessionProvider>();
    final id = session.activeSessionId;
    if (id == null) return;
    final picked = await showProductPickerSheet(context);
    if (picked == null || !mounted) return;
    final socket = context.read<SocketService>();
    socket.sendMessage(id, productId: picked.id);
    // Optimistic local bubble (mirrors the persisted shape).
    session.addLiveMessage({
      'sessionId': id, 'kind': 'user', 'sender': 'me',
      'product': {'productId': picked.id, 'name': picked.name, 'price': picked.price, 'image': picked.image},
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = Strings.of(context);
    final session = context.watch<SessionProvider>();
    final user = session.activeAlias;
    final liveEarn = _liveEarn; // per-minute, not per-second

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                CircleAvatar(radius: 22, backgroundColor: _tint.withValues(alpha: 0.2), child: Text(user.isNotEmpty ? user[0] : '★', style: TextStyle(color: _tint, fontWeight: FontWeight.w800, fontSize: 18))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
                    Row(children: [
                      Icon(widget.kind.icon, size: 13, color: _tint),
                      const SizedBox(width: 5),
                      Text('${widget.kind.label} · $_clock', style: TextStyle(color: c.muted, fontSize: 12.5)),
                    ]),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: c.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text('₹$liveEarn', style: TextStyle(color: c.green, fontWeight: FontWeight.w800)),
                ),
                IconButton(onPressed: _end, icon: Icon(Icons.call_end, color: c.red)),
              ]),
            ),
            const Divider(height: 1),
            // Body — live chat.
            Expanded(child: _ChatBody(tint: _tint, messages: session.liveMessages)),
            // Input bar.
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(color: c.ground, border: Border(top: BorderSide(color: c.line))),
              child: Row(children: [
                IconButton(
                  onPressed: _sending ? null : _sendImage,
                  icon: _sending ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.image_outlined, color: _tint),
                ),
                // Share a product from the storefront / RudraMaal as a tappable card.
                IconButton(
                  onPressed: _shareProduct,
                  tooltip: s.shareAProduct,
                  icon: Icon(Icons.storefront_outlined, color: _tint),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: TextStyle(color: c.ink),
                    minLines: 1, maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: s.typeAMessage,
                      hintStyle: TextStyle(color: c.muted),
                      filled: true, fillColor: c.ground2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                IconButton(onPressed: _sendText, icon: Icon(Icons.send, color: _tint)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live chat body for the astrologer. Renders the session's messages: the
/// astrologer's own ('me'), the seeker's (anonymous), system context bubbles,
/// and gift bubbles. Newest at the bottom.
class _ChatBody extends StatelessWidget {
  final Color tint;
  final List<Map<String, dynamic>> messages;
  const _ChatBody({required this.tint, required this.messages});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    if (messages.isEmpty) {
      return Center(child: Text(Strings.of(context).sayNamaste, style: TextStyle(color: c.muted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];
        final kind = (m['kind'] ?? 'user').toString();

        if (kind == 'system') {
          return Center(child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
            child: Text((m['message'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3)),
          ));
        }
        if (kind == 'gift') {
          return Center(child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text('🎁 ${m['fromAlias'] ?? 'Seeker'} sent ${m['gift'] ?? 'a gift'}', style: TextStyle(color: c.gold, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ));
        }

        final mine = (m['sender']?.toString() == 'me');

        // Shared product card (astrologer-only; always shown right-aligned for 'me').
        final prod = m['product'];
        if (prod is Map) {
          final name = (prod['name'] ?? Strings.of(context).product).toString();
          final price = (prod['price'] as num?)?.toInt() ?? 0;
          final image = prod['image']?.toString();
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.66),
              decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: tint.withValues(alpha: 0.5))),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (image != null && image.isNotEmpty)
                  Image.network(image, height: 120, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 120, color: c.ground, child: Icon(Icons.inventory_2_outlined, color: c.muted))),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [Icon(Icons.storefront, size: 13, color: tint), const SizedBox(width: 5), Text(Strings.of(context).sharedProduct, style: TextStyle(color: tint, fontSize: 11, fontWeight: FontWeight.w700))]),
                    const SizedBox(height: 6),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('₹$price', style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 15)),
                  ]),
                ),
              ]),
            ),
          );
        }

        final mediaUrl = m['mediaUrl']?.toString();
        final hasImage = mediaUrl != null && mediaUrl.isNotEmpty;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: hasImage ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: mine ? tint : c.ground2,
              borderRadius: BorderRadius.circular(14),
              border: mine ? null : Border.all(color: c.line),
            ),
            child: hasImage
                ? GestureDetector(
                    onTap: () => ImageViewer.open(context, mediaUrl),
                    child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(mediaUrl, width: 200, height: 200, fit: BoxFit.cover)),
                  )
                : Text((m['message'] ?? '').toString(), style: TextStyle(color: mine ? Colors.white : c.ink, fontSize: 14, height: 1.35)),
          ),
        );
      },
    );
  }
}

/// Searchable bottom sheet to pick a product (storefront + RudraMaal) to share
/// in chat. Returns the chosen [CatalogueItem], or null if dismissed.
Future<CatalogueItem?> showProductPickerSheet(BuildContext context) {
  return showModalBottomSheet<CatalogueItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProductPickerSheet(),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<CatalogueItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => _load(q: _search.text.trim()));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String? q}) async {
    setState(() => _loading = true);
    try {
      final items = await context.read<AstrologerApi>().catalogue(q: q);
      if (mounted) setState(() { _items = items; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final s = Strings.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(color: c.ground, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(height: 4, width: 42, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Icon(Icons.storefront_outlined, color: c.gold, size: 20),
              const SizedBox(width: 8),
              Text(s.shareAProduct, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: s.searchProducts,
                prefixIcon: Icon(Icons.search, color: c.muted),
                isDense: true,
                filled: true, fillColor: c.ground2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: c.muted)))
                    : _items.isEmpty
                        ? Center(child: Text(s.noProductsFound, style: TextStyle(color: c.muted)))
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final p = _items[i];
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(context).pop(p),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                                  child: Row(children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: (p.image != null && p.image!.isNotEmpty)
                                          ? Image.network(p.image!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph(c))
                                          : _ph(c),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          Text('₹${p.price}', style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 13.5)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(color: c.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                                            child: Text(p.source == 'rudramaal' ? Strings.of(context).rudramaal : Strings.of(context).myStore, style: TextStyle(color: c.gold, fontSize: 10, fontWeight: FontWeight.w700)),
                                          ),
                                        ]),
                                      ]),
                                    ),
                                    Icon(Icons.send, size: 18, color: c.gold),
                                  ]),
                                ),
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _ph(RgColors c) => Container(width: 52, height: 52, color: c.ground, child: Icon(Icons.inventory_2_outlined, color: c.muted, size: 22));
}
