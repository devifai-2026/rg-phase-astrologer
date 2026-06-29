import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../i18n/strings.dart';
import '../../services/push_service.dart';
import '../../theme/rg_colors.dart';
import '../../utils/phone_hint.dart';
import '../../widgets/rg_logo.dart';
import 'otp_verify_screen.dart';

/// Astrologer self-registration. Collects the applicant's details, then routes
/// to the OTP screen (register mode) which verifies the number and submits the
/// application to /api/astrologers/apply.
///
/// The phone carries over from the login screen. If a valid 10-digit number was
/// entered there, it's shown read-only (the confirmed account key). If the form
/// was opened without a number, the phone field is editable so it can be typed.
class RegistrationScreen extends StatefulWidget {
  /// 10-digit phone the applicant entered on the login screen (may be empty).
  final String phone10;
  const RegistrationScreen({super.key, this.phone10 = ''});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _expertise = TextEditingController();
  final _languages = TextEditingController();
  final _experience = TextEditingController();
  final _note = TextEditingController();

  /// True when a valid number came from login → phone is locked (confirmed).
  late final bool _phoneLocked;

  @override
  void initState() {
    super.initState();
    _phoneLocked = widget.phone10.trim().length == 10;
    _phone = TextEditingController(text: widget.phone10.trim());
    // If the form was opened without a number, offer the Google phone-number
    // picker (same as the login screen). Skipped when the phone is locked.
    if (!_phoneLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestPhoneHint());
    }
  }

  /// Show the Google phone-number picker and fill the editable phone field.
  Future<void> _requestPhoneHint() async {
    try {
      final res = await SmartAuth.instance.requestPhoneNumberHint();
      if (!mounted) return;
      if (res.hasData) {
        final ten = normalizeTo10(res.data!);
        if (ten != null) _phone.text = ten;
      }
    } catch (_) {/* hint is optional — ignore and let the user type */}
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _email.dispose();
    _expertise.dispose();
    _languages.dispose();
    _experience.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Split a comma-separated field into a clean list (no empties / dupes).
  List<String> _splitCsv(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(',')) {
      final v = part.trim();
      if (v.isNotEmpty && seen.add(v.toLowerCase())) out.add(v);
    }
    return out;
  }

  Future<void> _continueToOtp() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final t = Strings.of(context);
    final phone10 = _phone.text.trim();

    // Capture the device push token (best-effort) so the backend can notify
    // this device when an admin approves the application. Never blocks submit.
    final fcmToken = await PushService.instance.ensureToken();
    if (!mounted) return;

    final payload = RegistrationPayload(
      name: _name.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      expertise: _splitCsv(_expertise.text),
      languages: _splitCsv(_languages.text),
      experienceYears: int.tryParse(_experience.text.trim()) ?? 0,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      fcmToken: fcmToken,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.otpSent)));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OtpVerifyScreen(phone10: phone10, registration: payload),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);

    InputDecoration deco(String label, {String? hint}) =>
        InputDecoration(labelText: label, hintText: hint);

    return Scaffold(
      backgroundColor: c.ground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        child: SingleChildScrollView(
          // Drag anywhere on the form to dismiss the keyboard; bottom padding
          // grows with the keyboard so the active field/button stays in view.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: RgLogo(size: 64)),
                const SizedBox(height: 20),
                Text(t.regTitle, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.ink)),
                const SizedBox(height: 8),
                Text(t.regSubtitle, style: TextStyle(fontSize: 15, color: c.muted, height: 1.4)),
                const SizedBox(height: 24),

                // Phone — locked (read-only) when a valid number came from the
                // login screen; editable when the form was opened without one.
                TextFormField(
                  controller: _phone,
                  enabled: !_phoneLocked,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  style: TextStyle(
                      color: _phoneLocked ? c.muted : c.ink, fontSize: 16, letterSpacing: 1.2),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: deco(t.phoneLabel, hint: t.phoneHint).copyWith(
                    counterText: '',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Align(
                        widthFactor: 1,
                        child: Text(t.phoneCountryCode,
                            style: TextStyle(
                                color: _phoneLocked ? c.muted : c.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().length != 10 ? t.errInvalidPhone : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: TextStyle(color: c.ink),
                  decoration: deco(t.regName, hint: t.regNameHint),
                  validator: (v) => (v ?? '').trim().isEmpty ? t.errNameRequired : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  style: TextStyle(color: c.ink),
                  decoration: deco(t.regEmail, hint: t.regEmailHint),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return null; // optional
                    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
                    return ok ? null : '—';
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _expertise,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: TextStyle(color: c.ink),
                  decoration: deco(t.regExpertise, hint: t.vedicTarotNumerology),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _languages,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  style: TextStyle(color: c.ink),
                  decoration: deco(t.regLanguages, hint: t.hindiEnglishBengali),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _experience,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  style: TextStyle(color: c.ink),
                  decoration: deco(t.regExperience),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _note,
                  maxLines: 3,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: c.ink),
                  decoration: deco(t.regNote, hint: t.regNoteHint),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _continueToOtp,
                    child: Text(t.regVerifyFirst),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(t.termsNotice,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.muted, height: 1.4)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
