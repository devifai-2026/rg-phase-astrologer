import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/astrologer_api.dart';
import '../../i18n/strings.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/rg_colors.dart';
import '../../widgets/rg_logo.dart';
import '../../widgets/slide_route.dart';
import 'complete_profile_screen.dart';

/// Full-screen language picker shown right after OTP verification (mirrors the
/// user-app flow: splash → auth → verify → languages → complete profile).
class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});

  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  bool _busy = false;

  /// Save the chosen language, then PRE-FETCH the profile + expertise catalog
  /// and PRECACHE the photos here — before navigating — so the complete-profile
  /// screen paints instantly with the photos already in the image cache (no
  /// spinner, no pop-in). The catalog is handed forward so that screen skips its
  /// own fetch entirely.
  Future<void> _continue(BuildContext context, String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = context.read<AstrologerApi>();
    final session = context.read<SessionProvider>();

    // Language save is best-effort (local prefs already hold it).
    try { await api.saveLanguage(code); } catch (_) {}

    List<String> catalog = const [];
    try {
      final results = await Future.wait([api.myProfile(), api.listExpertise()]);
      if (!mounted) return;
      session.applyServerProfile(results[0] as Map<String, dynamic>);
      catalog = results[1] as List<String>;
    } catch (_) {/* fall back: complete-profile will fetch on its own */}
    if (!mounted) return;

    // Warm the image cache for the avatar + cover so they render smoothly.
    final p = session.profile;
    final urls = [p.avatar, p.coverPhoto].where((u) => u != null && u.startsWith('http'));
    await Future.wait(urls.map((u) => precacheImage(NetworkImage(u!), context).catchError((_) {})));
    if (!mounted) return;

    setState(() => _busy = false);
    // If the pre-fetch failed we pass null so the screen fetches itself.
    Navigator.of(context).push(slideRoute(
      CompleteProfileScreen(prefetchedExpertiseCatalog: catalog.isEmpty ? null : catalog),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rg;
    final t = Strings.of(context);
    final settings = context.watch<SettingsProvider>();
    final current = settings.locale?.languageCode ?? Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Center(child: RgLogo(size: 64)),
              const SizedBox(height: 28),
              Text(t.langTitle, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.ink)),
              const SizedBox(height: 8),
              Text(t.langSubtitle, style: TextStyle(fontSize: 14, color: c.muted, height: 1.4)),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: SettingsProvider.supportedLocales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final locale = SettingsProvider.supportedLocales[i];
                    final code = locale.languageCode;
                    final selected = code == current;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.read<SettingsProvider>().setLocale(locale),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                        decoration: BoxDecoration(
                          color: selected ? c.redSoft : c.ground2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: selected ? c.red : c.line, width: selected ? 1.4 : 1),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                SettingsProvider.languageNames[code] ?? code,
                                style: TextStyle(
                                  color: selected ? c.red : c.ink,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (selected) Icon(Icons.check_circle, color: c.red),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _continue(context, current),
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(t.continueButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
