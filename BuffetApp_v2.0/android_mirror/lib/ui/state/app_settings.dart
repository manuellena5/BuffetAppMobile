import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'

  AppThemeMode _theme = AppThemeMode.light;
  AppThemeMode get theme => _theme;

  ThemeMode get materialThemeMode => switch (_theme) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kThemeMode) ?? 'light';
    _theme = switch (s) {
      'system' => AppThemeMode.system,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.light,
    };
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode value) async {
    _theme = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kThemeMode, switch (value) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    });
    notifyListeners();
  }

  // Compat: mapear API vieja de darkMode a nuevo enum
  bool get darkMode => _theme == AppThemeMode.dark;
  Future<void> setDarkMode(bool value) => setTheme(value ? AppThemeMode.dark : AppThemeMode.light);
}
