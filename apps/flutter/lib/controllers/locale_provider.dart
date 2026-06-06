import 'package:flutter/material.dart';
import '../repositories/user_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale? _locale;

  Locale? get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final savedLangCode = await UserPreferences.getLocale();
    if (savedLangCode != null && savedLangCode.isNotEmpty) {
      _locale = Locale(savedLangCode);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    await UserPreferences.setLocale(locale.languageCode);
    notifyListeners();
  }

  Future<void> clearLocale() async {
    _locale = null;
    await UserPreferences.removeLocale();
    notifyListeners();
  }
}
