import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';

/// Persists the theme mode + chosen locale across launches.
/// A `null` locale means "follow the device locale".
class SettingsProvider extends ChangeNotifier {
  static const _kTheme = 'rg_astro_theme_mode';
  static const _kLocale = 'rg_astro_locale';
  static const _kTermsAccepted = 'rg_astro_terms_accepted';

  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  bool _termsAccepted = false;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  /// Whether the astrologer has previously accepted Terms & Privacy. Once true,
  /// the login screen pre-checks the consent box (no need to re-tick every time).
  bool get termsAccepted => _termsAccepted;

  /// Effective language code actually shown (chosen locale, else 'en'). Used to
  /// tell the backend which language to return dynamic content in.
  String get effectiveLangCode => _locale?.languageCode ?? 'en';

  /// Called whenever the effective language changes so the API client can send
  /// the right `x-lang` header for dynamic-content translation. Set from main().
  void Function(String langCode)? onLanguageChanged;

  void _notifyLanguage() => onLanguageChanged?.call(effectiveLangCode);

  static const supportedLocales = Strings.supportedLocales;
  static const languageNames = Strings.languageNames;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kTheme);
    _themeMode = switch (t) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final l = prefs.getString(_kLocale);
    _locale = (l == null || l.isEmpty) ? null : Locale(l);
    _termsAccepted = prefs.getBool(_kTermsAccepted) ?? false;
    _notifyLanguage();
    notifyListeners();
  }

  /// Remember that Terms & Privacy were accepted (persisted across launches).
  Future<void> setTermsAccepted(bool accepted) async {
    _termsAccepted = accepted;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTermsAccepted, accepted);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, mode.name);
  }

  /// Pass `null` to follow the device language.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    _notifyLanguage();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, locale?.languageCode ?? '');
  }
}
