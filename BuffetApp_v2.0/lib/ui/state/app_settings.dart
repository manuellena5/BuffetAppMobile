import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const _kPuntoVentaCodigo = 'punto_venta_codigo';
  static const _kAliasDispositivo = 'alias_dispositivo';
  static const _kUiScale = 'ui_scale'; // double
  static const _kWinSalesGridMinTileWidth = 'win_sales_grid_min_tile_width';

  static const double uiScaleMin = 0.8;
  static const double uiScaleMax = 1.3;

  AppThemeMode _theme = AppThemeMode.light;
  AppThemeMode get theme => _theme;

  double _uiScale = 1.0;
  double get uiScale => _uiScale;

  // Solo Windows: ancho mínimo deseado por tarjeta (en px lógicos).
  // Si es null, se usa el comportamiento legacy por thresholds.
  double? _winSalesGridMinTileWidth;
  double? get winSalesGridMinTileWidth => _winSalesGridMinTileWidth;

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

    final rawScale = sp.getDouble(_kUiScale) ?? 1.0;
    _uiScale = rawScale.clamp(uiScaleMin, uiScaleMax);

    final rawMinTile = sp.getDouble(_kWinSalesGridMinTileWidth);
    // Rango razonable para evitar valores que rompan el layout.
    if (rawMinTile == null) {
      _winSalesGridMinTileWidth = null;
    } else {
      _winSalesGridMinTileWidth = rawMinTile.clamp(120.0, 420.0);
    }

    _puntoVentaCodigo = sp.getString(_kPuntoVentaCodigo);
    _aliasDispositivo = sp.getString(_kAliasDispositivo);
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode value) async {
    _theme = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kThemeMode,
        switch (value) {
          AppThemeMode.system => 'system',
          AppThemeMode.light => 'light',
          AppThemeMode.dark => 'dark',
        });
    notifyListeners();
  }

  Future<void> setUiScale(double value) async {
    final next = value.clamp(uiScaleMin, uiScaleMax);
    if (next == _uiScale) return;
    _uiScale = next;
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kUiScale, _uiScale);
    notifyListeners();
  }

  Future<void> setWinSalesGridMinTileWidth(double? value) async {
    final sp = await SharedPreferences.getInstance();
    if (value == null) {
      _winSalesGridMinTileWidth = null;
      await sp.remove(_kWinSalesGridMinTileWidth);
      notifyListeners();
      return;
    }
    final next = value.clamp(120.0, 420.0);
    if (_winSalesGridMinTileWidth == next) return;
    _winSalesGridMinTileWidth = next;
    await sp.setDouble(_kWinSalesGridMinTileWidth, next);
    notifyListeners();
  }

  Future<void> setPuntoVentaConfig(
      {required String puntoVentaCodigo,
      required String aliasDispositivo}) async {
    _puntoVentaCodigo = puntoVentaCodigo.trim();
    _aliasDispositivo = aliasDispositivo.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPuntoVentaCodigo, _puntoVentaCodigo!);
    await sp.setString(_kAliasDispositivo, _aliasDispositivo!);
    notifyListeners();
  }

  // Compat: mapear API vieja de darkMode a nuevo enum
  bool get darkMode => _theme == AppThemeMode.dark;
  Future<void> setDarkMode(bool value) =>
      setTheme(value ? AppThemeMode.dark : AppThemeMode.light);
}
