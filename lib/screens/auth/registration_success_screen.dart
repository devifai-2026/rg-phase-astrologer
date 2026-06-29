import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme/rg_colors.dart';
import 'phone_login_screen.dart';

/// Shown after an astrologer registration is submitted to the backend. The
/// account is now an 'applied' lead awaiting admin review; the person can sign
/// in only once it's approved.
class RegistrationSuccessScreen extends StatelessWidget {
  const RegistrationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: c.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 56, color: c.green),
              ),
              const SizedBox(height: 28),
              Text(t.regSuccessTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
              const SizedBox(height: 12),
              Text(t.regSuccessBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: c.muted, height: 1.5)),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
                    (route) => false,
                  ),
                  child: Text(t.regBackToLogin),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
