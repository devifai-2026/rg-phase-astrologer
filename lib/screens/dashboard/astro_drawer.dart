import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../models/astrologer.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/push_service.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/language_button.dart';
import '../ai/profile_optimizer_screen.dart';
import '../auth/phone_login_screen.dart';
import '../legal/legal_screen.dart';
import '../notifications/notifications_screen.dart';
import '../onboarding/complete_profile_screen.dart';
import '../settings/astro_settings_screen.dart';
import '../storefront/storefront_screen.dart';
import 'dashboard_shell.dart';

/// App version shown in the drawer footer. Keep in sync with pubspec.yaml.
const String _appVersion = '1.0.0';

/// Side drawer opened from the dashboard hamburger — profile header + menu list,
/// theme/language, legal, logout, and the maker credit footer.
class AstroDrawer extends StatelessWidget {
  const AstroDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final session = context.watch<SessionProvider>();
    final p = session.profile;

    void push(Widget screen) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    void goTab(int index) {
      Navigator.of(context).pop();
      DashboardShell.goToTab(index);
    }

    return Drawer(
      backgroundColor: c.ground,
      child: SafeArea(
        child: Column(
          children: [
            // Profile header (tap → complete/edit profile).
            InkWell(
              onTap: () => push(const CompleteProfileScreen()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: c.redSoft,
                      backgroundImage: _avatarImg(p),
                      child: _avatarImg(p) == null
                          ? Text(p.displayName.isNotEmpty ? p.displayName[0] : 'A',
                              style: TextStyle(color: c.red, fontWeight: FontWeight.w800, fontSize: 22))
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.displayName.isNotEmpty ? p.displayName : Strings.of(context).astrologer,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(Strings.of(context).viewProfile, style: TextStyle(color: c.red, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.muted),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: c.line),

            // Menu list.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _item(c, Icons.dashboard_outlined, Strings.of(context).home, () => goTab(DashboardShell.tabHome)),
                  _item(c, Icons.call_received, 'Requests', () => goTab(DashboardShell.tabRequests)),
                  _item(c, Icons.history, 'History', () => goTab(DashboardShell.tabHistory)),
                  _item(c, Icons.account_balance_wallet_outlined, 'Earnings', () => goTab(DashboardShell.tabEarnings)),
                  Divider(height: 1, color: c.line),
                  _item(c, Icons.auto_fix_high, 'AI Profile Optimizer', () => push(const ProfileOptimizerScreen())),
                  _item(c, Icons.storefront, 'My Storefront', () => push(const StorefrontScreen())),
                  _item(c, Icons.notifications_none_rounded, 'Notifications', () => push(const NotificationsScreen())),
                  _item(c, Icons.tune, 'Settings & Presets', () => push(const AstroSettingsScreen())),
                  _item(c, Icons.translate, Strings.of(context).changeLanguage, () {
                    Navigator.of(context).pop();
                    showLanguageSheet(context);
                  }),
                  _item(c, Icons.star_outline, Strings.of(context).rateRudraganga, () {
                    Navigator.of(context).pop(); // close the drawer first
                    showRateRudragangaDialog(context);
                  }),
                  _item(c, Icons.description_outlined, Strings.of(context).termsOfService, () => push(LegalScreen(contentKey: 'terms', fallbackTitle: Strings.of(context).termsOfService))),
                  _item(c, Icons.privacy_tip_outlined, Strings.of(context).privacyPolicy, () => push(LegalScreen(contentKey: 'privacy', fallbackTitle: Strings.of(context).privacyPolicy))),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            _item(c, Icons.logout, Strings.of(context).logout, () => _logout(context), danger: true),
            const SizedBox(height: 6),
            _madeByFooter(c),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _item(RgColors c, IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: danger ? c.red : c.muted, size: 22),
      title: Text(label, style: TextStyle(color: danger ? c.red : c.ink, fontSize: 14.5, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  /// App version + "Made by DevifAI ❤️". DevifAI opens the company site.
  Widget _madeByFooter(RgColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text('v$_appVersion', style: TextStyle(color: c.muted, fontSize: 11)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('https://www.devifai.in');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: c.muted, fontSize: 11.5),
                children: [
                  const TextSpan(text: 'Made by '),
                  TextSpan(text: 'DevifAI', style: TextStyle(color: c.red, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' with ❤️'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final api = context.read<AstrologerApi>();
    final navigator = Navigator.of(context);
    final notifications = context.read<NotificationsProvider>();
    navigator.pop(); // close the drawer
    // Drop this device's push token (needs the live session), then revoke +
    // clear the session and the cached notification inbox. Best-effort.
    await PushService.instance.unregisterFromBackend();
    await api.logout();
    notifications.reset();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
      (r) => false,
    );
  }

  ImageProvider? _avatarImg(Astrologer p) {
    final a = p.avatar;
    if (a == null) return null;
    return a.startsWith('http') ? NetworkImage(a) : FileImage(File(a)) as ImageProvider;
  }
}

/// "Rate Rudraganga" — 1-5 stars + optional review, posted to /feedback/rate
/// (same endpoint the user app uses; one rating per account, re-submit updates).
Future<void> showRateRudragangaDialog(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _RateDialog());
}

class _RateDialog extends StatefulWidget {
  const _RateDialog();
  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  int _stars = 0;
  final _review = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _review.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_stars == 0 || _saving) return;
    setState(() => _saving = true);
    final api = context.read<AstrologerApi>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final s = Strings.of(context);
    try {
      await api.rateApp(rating: _stars, review: _review.text.trim());
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.thanksForYourRating)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('Could not submit. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    return AlertDialog(
      backgroundColor: c.ground2,
      title: Text(Strings.of(context).rateRudraganga, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Strings.of(context).howIsYourExperienceAsAn, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => IconButton(
                  onPressed: _saving ? null : () => setState(() => _stars = i + 1),
                  icon: Icon(i < _stars ? Icons.star_rounded : Icons.star_border_rounded, color: c.gold, size: 34),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  constraints: const BoxConstraints(),
                )),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _review,
            maxLines: 3,
            maxLength: 1000,
            style: TextStyle(color: c.ink),
            decoration: InputDecoration(hintText: Strings.of(context).writeAReviewOptional, hintStyle: TextStyle(color: c.muted), counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(Strings.of(context).later, style: TextStyle(color: c.muted))),
        ElevatedButton(
          onPressed: (_stars == 0 || _saving) ? null : _submit,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit'),
        ),
      ],
    );
  }
}
