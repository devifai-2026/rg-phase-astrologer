import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';

/// Add / edit the astrologer's payout account (bank or UPI). Saved instantly and
/// the admin is notified; the saved account is used for withdrawal requests.
class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _name = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _upi = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose(); _account.dispose(); _ifsc.dispose(); _upi.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AstrologerApi>().getPayoutDetails();
      if (!mounted) return;
      setState(() {
        _name.text = (d['beneficiaryName'] ?? '').toString();
        _account.text = (d['accountNumber'] ?? '').toString();
        _ifsc.text = (d['ifsc'] ?? '').toString();
        _upi.text = (d['upi'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _save() async {
    final acct = _account.text.trim();
    final ifsc = _ifsc.text.trim();
    final upi = _upi.text.trim();
    if (acct.isEmpty && upi.isEmpty) {
      _toast(Strings.of(context).enterABankAccountOrA);
      return;
    }
    if (acct.isNotEmpty && ifsc.isEmpty) {
      _toast(Strings.of(context).ifscIsRequiredWithABank);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AstrologerApi>().savePayoutDetails(
            accountNumber: acct,
            ifsc: ifsc,
            beneficiaryName: _name.text.trim(),
            upi: upi,
          );
      if (!mounted) return;
      _toast(Strings.of(context).bankDetailsSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        elevation: 0,
        title: Text(Strings.of(context).bankAccount, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.muted))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    Text(Strings.of(context).whereShouldWeSendYourPayouts, style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(Strings.of(context).addABankAccountWithIfsc,
                        style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4)),
                    const SizedBox(height: 20),

                    _label(c, Strings.of(context).bankAccount),
                    _field(c, _name, Strings.of(context).accountHolderName, TextInputType.name),
                    const SizedBox(height: 12),
                    _field(c, _account, Strings.of(context).accountNumber, TextInputType.number),
                    const SizedBox(height: 12),
                    _field(c, _ifsc, Strings.of(context).ifscCode, TextInputType.text, caps: true),

                    const SizedBox(height: 22),
                    Row(children: [Expanded(child: Divider(color: c.line)), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: c.muted))), Expanded(child: Divider(color: c.line))]),
                    const SizedBox(height: 22),

                    _label(c, Strings.of(context).upi),
                    _field(c, _upi, Strings.of(context).upiIdEGNameBank, TextInputType.emailAddress),

                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(backgroundColor: c.red, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
                        child: _saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(Strings.of(context).saveBankDetails, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _label(RgColors c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 0.3)),
      );

  Widget _field(RgColors c, TextEditingController ctrl, String hint, TextInputType type, {bool caps = false}) => TextField(
        controller: ctrl,
        keyboardType: type,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
        style: TextStyle(color: c.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.muted),
          filled: true, fillColor: c.ground2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
        ),
      );
}
