import 'package:flutter/material.dart';
import '../repositories/user_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeMode get themeMode => _themeMode;

  Future<void> _loadTheme() async {
    _themeMode = await UserPreferences.getThemeMode();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    await UserPreferences.setThemeMode(mode);
    notifyListeners();
  }

  bool isDarkMode() => _themeMode == ThemeMode.dark;
  bool isLightMode() => _themeMode == ThemeMode.light;
  bool isSystemMode() => _themeMode == ThemeMode.system;
}
