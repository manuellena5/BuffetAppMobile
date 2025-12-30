import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const _kPuntoVentaCodigo = 'punto_venta_codigo';
  static const _kAliasDispositivo = 'alias_dispositivo';

  AppThemeMode _theme = AppThemeMode.light;
  AppThemeMode get theme => _theme;

  String? _puntoVentaCodigo;
  String? get puntoVentaCodigo => _puntoVentaCodigo;

  String? _aliasDispositivo;
  String? get aliasDispositivo => _aliasDispositivo;

  bool get isPuntoVentaConfigured =>
      (_puntoVentaCodigo != null && _puntoVentaCodigo!.trim().isNotEmpty) &&
      (_aliasDispositivo != null && _aliasDispositivo!.trim().isNotEmpty);

  Future<void>? _loadFuture;

  ThemeMode get materialThemeMode => switch (_theme) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  Future<void> ensureLoaded() {
    _loadFuture ??= load();
    return _loadFuture!;
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kThemeMode) ?? 'light';
    _theme = switch (s) {
      'system' => AppThemeMode.system,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.light,
    };

    _puntoVentaCodigo = sp.getString(_kPuntoVentaCodigo);
    _aliasDispositivo = sp.getString(_kAliasDispositivo);
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

  Future<void> setPuntoVentaConfig({required String puntoVentaCodigo, required String aliasDispositivo}) async {
    _puntoVentaCodigo = puntoVentaCodigo.trim();
    _aliasDispositivo = aliasDispositivo.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPuntoVentaCodigo, _puntoVentaCodigo!);
    await sp.setString(_kAliasDispositivo, _aliasDispositivo!);
    notifyListeners();
  }

  // Compat: mapear API vieja de darkMode a nuevo enum
  bool get darkMode => _theme == AppThemeMode.dark;
  Future<void> setDarkMode(bool value) => setTheme(value ? AppThemeMode.dark : AppThemeMode.light);
}
