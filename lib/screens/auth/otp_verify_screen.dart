import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../api/api_client.dart';
import '../../api/socket_service.dart';
import '../../i18n/strings.dart';
import '../../providers/notifications_provider.dart';
import '../../services/analytics.dart';
import '../../services/push_service.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/slide_route.dart';
import '../onboarding/permissions_screen.dart';
import 'registration_success_screen.dart';

/// Payload carried into the OTP screen when verifying a registration. After the
/// code is accepted we submit the application to the backend.
class RegistrationPayload {
  final String name;
  final String? email;
  final List<String> expertise;
  final List<String> languages;
  final int experienceYears;
  final String? note;
  /// Device FCM token captured at registration so the backend can push the
  /// "you're approved" notification when an admin activates this astrologer.
  final String? fcmToken;
  const RegistrationPayload({
    required this.name,
    this.email,
    this.expertise = const [],
    this.languages = const [],
    this.experienceYears = 0,
    this.note,
    this.fcmToken,
  });
}

/// Enter the 6-digit OTP (UI-only: dev code is 123456).
///
/// Two modes:
///  • login    → on success, route to language selection → dashboard.
///  • register → on success, submit the [registration] application to the
///               backend, then show the "application received" screen.
class OtpVerifyScreen extends StatefulWidget {
  final String phone10;

  /// When non-null, this is a registration verification: submit the application
  /// to /api/astrologers/apply once the OTP is accepted.
  final RegistrationPayload? registration;

  const OtpVerifyScreen({super.key, required this.phone10, this.registration});

  bool get isRegister => registration != null;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  AstrologerApi get _api => context.read<AstrologerApi>();
  String? _serverError;
  bool _busy = false;

  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  void _startResendCountdown() {
    _resendIn = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;
    final t = Strings.of(context);
    final code = _controller.text.trim();
    setState(() => _busy = true);

    if (widget.isRegister) {
      // Registration is unauthenticated: the OTP only gates the /apply submit.
      // Dev: accept the fixed code locally (the lead doesn't need a session).
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      if (code != '123456') {
        setState(() { _busy = false; _serverError = t.errInvalidOtp; });
        return;
      }
      await _submitRegistration(t);
      return;
    }

    // Login: verify against the backend (dev code 123456), which mints + stores
    // the JWT. Only an ACTIVE astrologer reaches this screen (gated earlier).
    try {
      final auth = await _api.verifyOtp(widget.phone10, code);
      Analytics.instance.login('otp'); // GA login event
      // Session is live → register this device's FCM token so admin broadcasts +
      // approval/system pushes reach it. Fire-and-forget; never blocks login.
      PushService.instance.registerWithBackend();
      if (!mounted) return;
      // Open the realtime socket (backend marks the astrologer online and starts
      // routing incoming requests/notifications).
      context.read<SocketService>().connect();
      // Prime the notification inbox + bell badge for the new session.
      context.read<NotificationsProvider>().load();
      setState(() => _busy = false);
      // First-time vs returning: onboarding (language + complete-profile) runs
      // only on first login. `profileCompleted` is set once onboarding finishes.
      final user = (auth['user'] is Map) ? Map<String, dynamic>.from(auth['user']) : const {};
      final firstTime = user['profileCompleted'] != true;
      // Permissions screen always runs (auto-skips if already granted), then
      // routes to onboarding (first time) or straight to the dashboard.
      Navigator.of(context).pushAndRemoveUntil(
        slideRoute(PermissionsScreen(firstTime: firstTime)),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = e.statusCode == 400 ? t.errInvalidOtp : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _busy = false; _serverError = t.errGeneric; });
    }
  }

  /// OTP accepted for a registration → persist the application on the backend.
  Future<void> _submitRegistration(Strings t) async {
    final r = widget.registration!;
    try {
      await _api.register(
        name: r.name,
        phone10: widget.phone10,
        email: r.email,
        expertise: r.expertise,
        languages: r.languages,
        experienceYears: r.experienceYears,
        note: r.note,
        fcmToken: r.fcmToken,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        slideRoute(const RegistrationSuccessScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = t.errGeneric;
      });
    }
  }

  Future<void> _resend() async {
    final t = Strings.of(context);
    // Login re-sends a real OTP; registration's code is verified locally (dev).
    if (!widget.isRegister) {
      try { await _api.requestOtp(widget.phone10); } catch (_) {/* best-effort */}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.otpSent)));
    _startResendCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    final prettyPhone = '${t.phoneCountryCode} ${widget.phone10}';

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        // LayoutBuilder + ConstrainedBox(minHeight) + IntrinsicHeight keeps the
        // content stable when the keyboard opens (no "jump to top").
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
                      Text(t.otpTitle, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.ink)),
                      const SizedBox(height: 8),
                      Text(t.otpSubtitle(prettyPhone), style: TextStyle(fontSize: 15, color: c.muted, height: 1.4)),
                      const SizedBox(height: 32),
                      TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  enabled: !_busy,
                  style: TextStyle(color: c.ink, fontSize: 26, letterSpacing: 12, fontWeight: FontWeight.w700),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: InputDecoration(labelText: t.otpLabel, counterText: ''),
                  validator: (v) => (v ?? '').trim().length != 6 ? t.errInvalidOtp : null,
                  onChanged: (v) {
                    if (v.length == 6 && !_busy) _verify();
                  },
                      ),
                      if (_serverError != null) ...[
                        const SizedBox(height: 8),
                        Text(_serverError!, style: const TextStyle(color: Color(0xFFE0584A), fontSize: 13)),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _busy ? null : _verify,
                        child: _busy
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(widget.isRegister ? t.regSubmit : t.verifyButton),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => Navigator.of(context).pop(),
                            child: Text(t.changeNumber, style: TextStyle(color: c.muted)),
                          ),
                          _resendIn > 0
                              ? Text(t.resendOtpIn(_resendIn), style: TextStyle(color: c.muted, fontSize: 13))
                              : TextButton(onPressed: _resend, child: Text(t.resendOtp)),
                        ],
                      ),
                      const Expanded(child: SizedBox(height: 8)),
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
}
