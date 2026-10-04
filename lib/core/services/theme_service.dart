import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

/// Central theme management service for QuickShare Studio.
/// Controls theme mode switching between 'Dark Forest' (dark) and 'Light Mode' (light).
/// Persists user preference via SharedPreferences under 'appearance_dark_mode'.
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;

  ThemeMode _themeMode = ThemeMode.dark;

  ThemeService._internal() {
    _loadFromPrefs();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('appearance_dark_mode') ?? true;
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      AppColors.isDark = isDark;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    await setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    AppColors.isDark = mode == ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('appearance_dark_mode', mode == ThemeMode.dark);
    } catch (_) {}
  }
}
