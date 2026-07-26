import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/session_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import '../requests/requests_screen.dart' show SessionHistoryTile;
import 'bank_account_screen.dart';

/// Per-service consultation stats (sessions / minutes / earnings).
class _Svc {
  final int sessions;
  final int minutes;
  final int earnings;
  const _Svc({this.sessions = 0, this.minutes = 0, this.earnings = 0});
  factory _Svc.fromJson(Map? m) {
    final j = m == null ? const {} : Map<String, dynamic>.from(m);
    return _Svc(
      sessions: (j['sessions'] as num?)?.toInt() ?? 0,
      minutes: (j['minutes'] as num?)?.toInt() ?? 0,
      earnings: (j['earnings'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Everything the earnings screen binds to, loaded together so the screen has a
/// single loading / error / empty state.
class _EarningsData {
  final int available;
  final int thisMonth;
  final _Svc chat;
  final _Svc call;
  final _Svc video;
  final List<SessionItem> recent; // completed sessions with earning > 0
  const _EarningsData({
    required this.available,
    required this.thisMonth,
    required this.chat,
    required this.call,
    required this.video,
    required this.recent,
  });

  int get total => chat.earnings + call.earnings + video.earnings;
}

/// Earnings tab — fully API-bound: this-month / total earnings from
/// GET /astrologers/me/stats, the per-service breakdown from the same call, and
/// the recent earning sessions from GET /sessions (same data the Requests
/// History tab uses). Available-to-withdraw comes from GET /wallet/balance.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  _EarningsData? _data;
  /// Explicit loading flag. `_data == null` alone can't distinguish "still
  /// loading" from "loaded, nothing to show", which made the spinner run forever
  /// on an account with no earnings yet.
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AstrologerApi>();
    final sessionApi = context.read<SessionApi>();
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.myStats(),
        api.walletBalance(),
        sessionApi.history(limit: 50),
      ]);
      final stats = results[0] as Map<String, dynamic>;
      final bal = results[1] as Map<String, dynamic>;
      final history = (results[2] as List).cast<SessionItem>();

      final s = (stats['stats'] is Map) ? Map<String, dynamic>.from(stats['stats'] as Map) : const {};
      final recent = history.where((h) => h.isCompleted && h.astrologerEarning > 0).toList();

      if (!mounted) return;
      setState(() {
        _data = _EarningsData(
          available: (bal['available'] as num?)?.toInt() ?? (bal['balance'] as num?)?.toInt() ?? 0,
          thisMonth: (stats['thisMonthEarnings'] as num?)?.toInt() ?? 0,
          chat: _Svc.fromJson(s['chat'] as Map?),
          call: _Svc.fromJson(s['call'] as Map?),
          video: _Svc.fromJson(s['video'] as Map?),
          recent: recent,
        );
        _error = null;
        _loading = false;
      });
    } catch (_) {
      // Resolved here, not up front: _load() runs from initState() where
      // Strings.of(context) throws, which aborted the fetch and left the tab
      // stuck on its spinner.
      if (mounted) setState(() { _error = Strings.of(context).couldNotLoadEarnings; _loading = false; });
    } finally {
      // Any path escaping the try/catch must still clear the spinner, or the
      // screen is stuck on a loader with no way to recover.
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(c),
      ),
    );
  }

  Widget _buildBody(RgColors c) {
    final data = _data;

    if (_error != null && data == null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 120, 32, 0),
          child: Column(children: [
            Icon(Icons.cloud_off, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(Strings.of(context).retry)),
          ]),
        ),
      ]);
    }
    // Spinner ONLY while a request is in flight.
    if (_loading && data == null) {
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
    }
    // Loaded but nothing came back — show an empty state, not an endless spinner.
    if (data == null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 120, 32, 0),
          child: Column(children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(Strings.of(context).noEarningsYet,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(Strings.of(context).noEarningsYetHint,
                textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(Strings.of(context).retry)),
          ]),
        ),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(Strings.of(context).earnings, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 22)),
        const SizedBox(height: 16),

        // Balance card.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [c.redDeep, c.red], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Strings.of(context).availableToWithdraw, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
            const SizedBox(height: 4),
            Text('₹${_fmt(data.available)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 34)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: c.redDeep, minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.account_balance),
                label: Text(Strings.of(context).withdrawToBank, style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => _withdrawSheet(context, data.available),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        Row(children: [
          _stat(c, Strings.of(context).thisMonth, '₹${_fmt(data.thisMonth)}', Icons.calendar_month),
          const SizedBox(width: 10),
          _stat(c, Strings.of(context).totalEarned, '₹${_fmt(data.total)}', Icons.trending_up),
        ]),
        const SizedBox(height: 22),

        // ── Per-service breakdown ──
        Text(Strings.of(context).byService, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        _ServiceRow(c: c, label: Strings.of(context).chat, icon: Icons.chat_bubble_outline, tint: c.blue, svc: data.chat),
        const SizedBox(height: 10),
        _ServiceRow(c: c, label: Strings.of(context).audio, icon: Icons.call_outlined, tint: c.green, svc: data.call),
        const SizedBox(height: 10),
        _ServiceRow(c: c, label: Strings.of(context).video, icon: Icons.videocam_outlined, tint: c.violet, svc: data.video),
        const SizedBox(height: 24),

        // ── Recent earnings (same session history as the Requests tab) ──
        Text(Strings.of(context).recentEarnings, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        if (data.recent.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(children: [
              Icon(Icons.receipt_long_outlined, size: 40, color: c.muted),
              const SizedBox(height: 10),
              Text(Strings.of(context).noEarningsYet, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(Strings.of(context).completedConsultationsWillShowHere, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
            ]),
          )
        else
          ...data.recent.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SessionHistoryTile(item: s),
              )),
      ],
    );
  }

  Widget _stat(RgColors c, String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: c.gold, size: 18),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: c.muted, fontSize: 11.5)),
          ]),
        ),
      );

  void _withdrawSheet(BuildContext context, int available) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.rg.ground2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WithdrawSheet(available: available),
    ).then((didRequest) {
      if (didRequest == true) _load(); // refresh balance after a request
    });
  }

  String _fmt(int n) {
    final neg = n < 0;
    final s = n.abs().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${neg ? '-' : ''}$b';
  }
}

/// One per-service breakdown row (sessions · minutes on the left, ₹ earned on
/// the right).
class _ServiceRow extends StatelessWidget {
  final RgColors c;
  final String label;
  final IconData icon;
  final Color tint;
  final _Svc svc;
  const _ServiceRow({required this.c, required this.label, required this.icon, required this.tint, required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Row(children: [
        Container(
          height: 42, width: 42,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: tint, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(Strings.of(context).svcSessionsSessionsSvcMinutesMin(svc.sessions, svc.minutes), style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Text('₹${_fmt(svc.earnings)}', style: TextStyle(color: c.green, fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Withdraw sheet bound to the real backend: loads the saved payout account
/// (or prompts to add one), then POSTs the withdrawal request. Pops `true` when
/// a request was submitted so the caller can refresh the balance.
class _WithdrawSheet extends StatefulWidget {
  final int available;
  const _WithdrawSheet({required this.available});
  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  late final TextEditingController _amount = TextEditingController(text: '${widget.available}');
  Map<String, dynamic>? _payout;
  bool _loading = true;
  bool _submitting = false;

  bool get _hasAccount => _payout != null && ((_payout!['accountNumber'] ?? '').toString().isNotEmpty || (_payout!['upi'] ?? '').toString().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _loadPayout();
  }

  @override
  void dispose() { _amount.dispose(); super.dispose(); }

  Future<void> _loadPayout() async {
    try {
      final d = await context.read<AstrologerApi>().getPayoutDetails();
      if (mounted) setState(() { _payout = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _payout = {}; _loading = false; });
    }
  }

  Future<void> _editBank() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BankAccountScreen()),
    );
    if (changed == true) _loadPayout();
  }

  String get _accountLabel {
    final p = _payout!;
    final acct = (p['accountNumber'] ?? '').toString();
    final upi = (p['upi'] ?? '').toString();
    if (acct.isNotEmpty) return 'Bank ••••${acct.length >= 4 ? acct.substring(acct.length - 4) : acct}';
    if (upi.isNotEmpty) return 'UPI · $upi';
    return '';
  }

  Future<void> _submit() async {
    final amt = int.tryParse(_amount.text.trim()) ?? 0;
    final messenger = ScaffoldMessenger.of(context);
    if (amt <= 0) { messenger.showSnackBar(const SnackBar(content: Text('Enter a valid amount'))); return; }
    if (amt > widget.available) { messenger.showSnackBar(const SnackBar(content: Text('Amount exceeds your available balance'))); return; }
    setState(() => _submitting = true);
    try {
      await context.read<AstrologerApi>().requestWithdrawal(amountRupees: amt);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text('Withdrawal of ₹$amt requested'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Withdraw earnings', style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          Text('Available: ₹${widget.available}', style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 18),

          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
          else ...[
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              style: TextStyle(color: c.ink, fontSize: 22, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Amount'),
            ),
            const SizedBox(height: 14),

            // Payout account row: saved account + Edit, or an "Add" CTA when none.
            InkWell(
              onTap: _editBank,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.ground, borderRadius: BorderRadius.circular(12), border: Border.all(color: _hasAccount ? c.line : c.red)),
                child: Row(children: [
                  Icon(Icons.account_balance, color: _hasAccount ? c.muted : c.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _hasAccount
                        ? Text(_accountLabel, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600))
                        : Text('Add a bank account or UPI', style: TextStyle(color: c.red, fontWeight: FontWeight.w700)),
                  ),
                  Text(_hasAccount ? 'Edit' : 'Add', style: TextStyle(color: c.red, fontSize: 13, fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right, color: c.muted, size: 18),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (!_hasAccount || _submitting) ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Request withdrawal'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
