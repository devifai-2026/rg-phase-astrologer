import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../api/astrologer_api.dart';
import '../../api/api_client.dart';
import '../../i18n/strings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rg_colors.dart';
import '../../utils/phone_hint.dart';
import '../../widgets/language_button.dart';
import '../../widgets/rg_logo.dart';
import '../legal/legal_screen.dart';
import 'otp_verify_screen.dart';
import 'registration_screen.dart';

/// Astrologer sign in with a phone number. The number is checked against the
/// backend: if an active account exists we proceed to OTP; if it isn't
/// registered we show a "not registered" panel with a Register call-to-action;
/// if it's registered but still under review we tell them to wait for approval.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

/// Outcome of checking a phone against the backend, used to drive the UI panel.
enum _Gate { none, notRegistered, pending, rejected, takenByOther, error }

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _phoneFocus = FocusNode();
  AstrologerApi get _api => context.read<AstrologerApi>();
  bool _busy = false;
  bool _accepted = false; // Terms & Privacy consent — gates the OTP button.
  _Gate _gate = _Gate.none;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    // Pre-check consent if the astrologer already accepted it on a prior login.
    _accepted = context.read<SettingsProvider>().termsAccepted;
    // Re-checking a fresh number clears any prior gate panel.
    _controller.addListener(() {
      if (_gate != _Gate.none) setState(() => _gate = _Gate.none);
    });
    // Offer the SIM / Google-account numbers via the native Phone Number Hint
    // sheet once the screen settles (Android-only; no-op elsewhere).
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPhoneHint());
  }

  /// Show the Google phone-number picker; fill the field with the chosen number.
  Future<void> _requestPhoneHint() async {
    try {
      final res = await SmartAuth.instance.requestPhoneNumberHint();
      if (!mounted) return;
      if (res.hasData) {
        final ten = normalizeTo10(res.data!);
        if (ten != null) {
          _controller.text = ten;
          setState(() => _gate = _Gate.none);
        }
      }
    } catch (_) {/* hint is optional — ignore and let the user type */}
    // Picked, dismissed, or unsupported → focus so the user can type/edit.
    if (mounted) _phoneFocus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final t = Strings.of(context);
    // Consent gate — enforced HERE (not just via the disabled button) so the
    // keyboard "done" action and any other path can't bypass it.
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.acceptToContinue)));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final phone = _controller.text.trim();
    setState(() {
      _busy = true;
      _gate = _Gate.none;
    });

    try {
      final res = await _api.checkExists(phone);
      if (!mounted) return;
      setState(() => _busy = false);

      if (res.takenByOtherRole) {
        // Number belongs to a user/admin account — registration is not allowed.
        setState(() => _gate = _Gate.takenByOther);
        return;
      }
      if (!res.exists) {
        setState(() => _gate = _Gate.notRegistered);
        return;
      }
      switch (res.status) {
        case 'active':
          // Active account → send a real OTP, then go verify it.
          try { await _api.requestOtp(phone); } catch (_) {/* OTP screen can resend */}
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.otpSent)));
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OtpVerifyScreen(phone10: phone)),
          );
          break;
        case 'rejected':
        case 'suspended':
          setState(() => _gate = _Gate.rejected);
          break;
        default: // applied | contacted | details_filled
          setState(() => _gate = _Gate.pending);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _gate = _Gate.error;
        _errorMsg = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _gate = _Gate.error;
        _errorMsg = t.errGeneric;
      });
    }
  }

  void _goToRegistration() {
    final phone = _controller.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegistrationScreen(phone10: phone)),
    );
  }

  void _openLegal(String key, String fallbackTitle) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LegalScreen(contentKey: key, fallbackTitle: fallbackTitle),
    ));
  }

  /// Required-consent row: a checkbox + a rich label with tappable Terms and
  /// Privacy links. The OTP button stays disabled until this is checked.
  Widget _acceptRow(RgColors c, Strings t) {
    final linkStyle = TextStyle(color: c.red, fontWeight: FontWeight.w700, fontSize: 12.5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24, height: 24,
          child: Checkbox(
            value: _accepted,
            onChanged: _busy
                ? null
                : (v) {
                    final accepted = v ?? false;
                    setState(() => _accepted = accepted);
                    // Remember the choice so it's not required on every login.
                    context.read<SettingsProvider>().setTermsAccepted(accepted);
                  },
            activeColor: c.red,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
                children: [
                  TextSpan(text: '${t.agreePrefix} '),
                  TextSpan(text: t.termsLink, style: linkStyle,
                      recognizer: TapGestureRecognizer()..onTap = () => _openLegal('terms-astrologer', t.termsLink)),
                  TextSpan(text: ' ${t.andWord} '),
                  TextSpan(text: t.privacyLink, style: linkStyle,
                      recognizer: TapGestureRecognizer()..onTap = () => _openLegal('privacy-astrologer', t.privacyLink)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);

    return Scaffold(
      backgroundColor: c.ground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: const [LanguageButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        // LayoutBuilder + ConstrainedBox(minHeight) + IntrinsicHeight lets the
        // content fill the screen when the keyboard is closed, yet become fully
        // scrollable the moment it opens — so nothing jumps or gets trapped.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: IntrinsicHeight(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Center(child: RgLogo(size: 84)),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(t.consoleName,
                            style: TextStyle(fontSize: 13, color: c.gold, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 28),
                      Text(t.authWelcomeTitle,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.ink)),
                      const SizedBox(height: 8),
                      Text(t.authWelcomeSubtitle, style: TextStyle(fontSize: 15, color: c.muted, height: 1.4)),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _controller,
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        enabled: !_busy,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => (_busy) ? null : _submit(),
                        style: TextStyle(color: c.ink, fontSize: 18, letterSpacing: 1.5),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                        decoration: InputDecoration(
                          labelText: t.phoneLabel,
                          hintText: t.phoneHint,
                          counterText: '',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 8),
                            child: Align(
                              widthFactor: 1,
                              child: Text(t.phoneCountryCode,
                                  style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0),
                        ),
                        validator: (v) => (v ?? '').trim().length != 10 ? t.errInvalidPhone : null,
                      ),
                      const SizedBox(height: 16),

                      // Required consent: OTP is disabled until the astrologer
                      // accepts the Terms & Privacy Policy (tappable links).
                      _acceptRow(c, t),
                      const SizedBox(height: 14),

                      ElevatedButton(
                        onPressed: (_busy || !_accepted) ? null : _submit,
                        child: _busy
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(t.sendOtpButton),
                      ),

                      // Gate panel (not-registered / pending / rejected / error).
                      _buildGate(c, t),

                      // Flexible gap: fills the screen when the keyboard is
                      // closed (pushing the footer down), collapses when it opens.
                      const Expanded(child: SizedBox(height: 16)),

                      // Registration entry point — hidden when the number already
                      // belongs to another platform account (registration would fail).
                      if (_gate != _Gate.takenByOther)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _goToRegistration,
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                          label: Text(t.registerCta),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: c.red,
                            side: BorderSide(color: c.red.withValues(alpha: 0.6)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGate(RgColors c, Strings t) {
    if (_gate == _Gate.none) return const SizedBox.shrink();

    late final Color tone;
    late final IconData icon;
    late final String title;
    late final String body;
    bool showRegisterCta = false;

    switch (_gate) {
      case _Gate.notRegistered:
        tone = c.red;
        icon = Icons.info_outline_rounded;
        title = t.notRegisteredTitle;
        body = t.notRegisteredBody;
        showRegisterCta = true;
        break;
      case _Gate.pending:
        tone = c.gold;
        icon = Icons.hourglass_top_rounded;
        title = t.applicationPendingTitle;
        body = t.applicationPendingBody;
        break;
      case _Gate.rejected:
        tone = c.red;
        icon = Icons.block_rounded;
        title = t.applicationPendingTitle;
        body = t.applicationPendingBody;
        break;
      case _Gate.takenByOther:
        tone = c.red;
        icon = Icons.lock_person_rounded;
        title = t.numberTakenTitle;
        body = ''; // title ("Number already in use") is enough.
        break;
      case _Gate.error:
        tone = c.red;
        icon = Icons.wifi_off_rounded;
        title = t.errGeneric;
        body = _errorMsg;
        break;
      case _Gate.none:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: tone, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontWeight: FontWeight.w800, color: c.ink, fontSize: 15)),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body, style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.45)),
            ],
            if (showRegisterCta) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goToRegistration,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  label: Text(t.registerCta),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
