import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/push_service.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/language_button.dart';
import '../../widgets/slide_route.dart';
import '../ai/profile_optimizer_screen.dart';
import '../ai/recap_list_screen.dart';
import '../auth/phone_login_screen.dart';
import '../onboarding/complete_profile_screen.dart';
import '../settings/astro_settings_screen.dart';
import '../storefront/storefront_screen.dart';
import 'widgets/status_toggle.dart';

/// Profile + settings tab. Profile header (cover/avatar), reputation (read-only),
/// edit-profile entry, availability, theme, language, logout.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  ImageProvider? _img(String? v) {
    if (v == null) return null;
    return v.startsWith('http') ? NetworkImage(v) : FileImage(File(v)) as ImageProvider;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    final session = context.watch<SessionProvider>();
    final settings = context.watch<SettingsProvider>();
    final p = session.profile;
    final cover = _img(p.coverPhoto);
    final avatar = _img(p.avatar);

    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header: cover + avatar ──
          SizedBox(
            height: 190,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    gradient: cover == null ? LinearGradient(colors: [c.redDeep, c.red, c.gold], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                    image: cover != null ? DecorationImage(image: cover, fit: BoxFit.cover) : null,
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 4,
                  right: 6,
                  child: const LanguageButton(),
                ),
                Positioned(
                  left: 20,
                  bottom: 0,
                  child: Container(
                    height: 92, width: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.ground2,
                      border: Border.all(color: c.ground, width: 4),
                      image: avatar != null ? DecorationImage(image: avatar, fit: BoxFit.cover) : null,
                    ),
                    child: avatar == null
                        ? Center(child: Text(p.displayName.isNotEmpty ? p.displayName[0] : 'A', style: TextStyle(fontSize: 36, color: c.muted, fontWeight: FontWeight.w800)))
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.displayName, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 20)),
                        const SizedBox(height: 2),
                        Text(t.pExperienceyearsYrsPExpertiseTake(p.experienceYears, p.expertise.take(3).join(", ")), style: TextStyle(color: c.muted, fontSize: 13)),
                      ]),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: c.red, side: BorderSide(color: c.red)),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(t.edit),
                      onPressed: () => Navigator.of(context).push(slideRoute(const CompleteProfileScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(p.bio, style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.45)),
                const SizedBox(height: 18),

                // Reputation (read-only).
                Row(children: [
                  _rep(c, Icons.favorite, _fmt(p.followers), t.followers, c.red),
                  const SizedBox(width: 10),
                  _rep(c, Icons.card_giftcard, '${p.giftCount}', t.gifts, c.gold),
                  const SizedBox(width: 10),
                  _rep(c, Icons.star, '${p.rating}', '${p.reviewCount} ${t.reviews}', c.green),
                ]),
                const SizedBox(height: 24),

                // Availability.
                _sectionLabel(c, 'Availability'),
                const SizedBox(height: 8),
                const StatusToggle(),
                const SizedBox(height: 24),

                // Languages spoken chips.
                _sectionLabel(c, t.languagesSpoken),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: p.languages.map((l) => _tag(c, l)).toList()),
                const SizedBox(height: 24),

                // Manage.
                _sectionLabel(c, t.manage),
                const SizedBox(height: 8),
                _navTile(context, Icons.auto_fix_high, 'AI Profile Optimizer', c.violet, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileOptimizerScreen()))),
                _navTile(context, Icons.auto_awesome, t.aiChatRecaps2, c.violet, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecapListScreen()))),
                _navTile(context, Icons.storefront, 'My Storefront', c.gold, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorefrontScreen()))),
                _navTile(context, Icons.tune, 'Settings & Presets', c.red, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AstroSettingsScreen()))),
                const SizedBox(height: 24),

                // Theme.
                _sectionLabel(c, t.theme),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto, size: 18), label: Text(t.themeSystem)),
                    ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined, size: 18), label: Text(t.themeLight)),
                    ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined, size: 18), label: Text(t.themeDark)),
                  ],
                  selected: {settings.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => context.read<SettingsProvider>().setThemeMode(s.first),
                ),
                const SizedBox(height: 24),

                // Language.
                _sectionLabel(c, t.language),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showLanguageSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                    child: Row(children: [
                      Icon(Icons.translate, color: c.red, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(SettingsProvider.languageNames[settings.locale?.languageCode] ?? t.themeSystem, style: TextStyle(color: c.ink, fontSize: 14.5))),
                      Icon(Icons.chevron_right, color: c.muted),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: Text(t.logout),
                  style: ElevatedButton.styleFrom(backgroundColor: c.red, foregroundColor: Colors.white),
                  onPressed: () async {
                    final api = context.read<AstrologerApi>();
                    final navigator = Navigator.of(context);
                    final notifications = context.read<NotificationsProvider>();
                    // Drop this device's push token (needs the live session), then
                    // revoke + clear the session + notification inbox. Best-effort.
                    await PushService.instance.unregisterFromBackend();
                    await api.logout();
                    notifications.reset();
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
                      (r) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(RgColors c, String text) => Text(text, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 13));

  Widget _navTile(BuildContext context, IconData icon, String label, Color tint, VoidCallback onTap) {
    final c = context.rg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
          child: Row(children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: c.ink, fontSize: 14.5, fontWeight: FontWeight.w600))),
            Icon(Icons.chevron_right, color: c.muted),
          ]),
        ),
      ),
    );
  }

  Widget _tag(RgColors c, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
        child: Text(label, style: TextStyle(color: c.ink, fontSize: 13)),
      );

  Widget _rep(RgColors c, IconData icon, String value, String label, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: c.ground2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 11)),
          ]),
        ),
      );

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}
