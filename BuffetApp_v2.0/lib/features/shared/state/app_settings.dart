import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
  static const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const _kPuntoVentaCodigo = 'punto_venta_codigo';
  static const _kAliasDispositivo = 'alias_dispositivo';
  static const _kUiScale = 'ui_scale'; // double
  static const _kWinSalesGridMinTileWidth = 'win_sales_grid_min_tile_width';

  // Contexto activo (vNext)
  static const _kDisciplinaActivaId = 'disciplina_activa_id';
  static const _kEventoActivoId = 'evento_activo_id';
  static const _kEventoActivoFecha = 'evento_activo_fecha';
  static const _kEventoActivoEsEspecial = 'evento_activo_especial';
  
  // Buffet: ayuda de vuelto en efectivo
  static const _kCashChangeHelper = 'cash_change_helper';
  static const _kUpdateMetadataUrl = 'update_metadata_url';

  // Unidad de Gestión activa para Tesorería
  static const _kUnidadGestionActivaId = 'unidad_gestion_activa_id';

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

  int? _disciplinaActivaId;
  int? get disciplinaActivaId => _disciplinaActivaId;

  String? _eventoActivoId;
  String? get eventoActivoId => _eventoActivoId;

  String? _eventoActivoFecha;
  String? get eventoActivoFecha => _eventoActivoFecha;

  bool _eventoActivoEsEspecial = false;
  bool get eventoActivoEsEspecial => _eventoActivoEsEspecial;

  // Buffet: mostrar calculador de vuelto en pago efectivo
  bool _cashChangeHelper = true;
  bool get cashChangeHelper => _cashChangeHelper;

  String? _updateMetadataUrl;
  String? get updateMetadataUrl => _updateMetadataUrl;

  // Unidad de Gestión activa para Tesorería
  int? _unidadGestionActivaId;
  int? get unidadGestionActivaId => _unidadGestionActivaId;
  
  bool get isUnidadGestionConfigured => _unidadGestionActivaId != null;

  String _todayYmd() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

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

    _disciplinaActivaId = sp.getInt(_kDisciplinaActivaId);
    _eventoActivoId = sp.getString(_kEventoActivoId);
    _eventoActivoFecha = sp.getString(_kEventoActivoFecha);
    _eventoActivoEsEspecial = sp.getBool(_kEventoActivoEsEspecial) ?? false;
    
    // Buffet: ayuda de vuelto
    _cashChangeHelper = sp.getBool(_kCashChangeHelper) ?? true;

    _updateMetadataUrl = sp.getString(_kUpdateMetadataUrl);

    // Unidad de Gestión activa para Tesorería
    _unidadGestionActivaId = sp.getInt(_kUnidadGestionActivaId);

    notifyListeners();
  }

  Future<void> setUpdateMetadataUrl(String? url) async {
    _updateMetadataUrl = url?.trim();
    final sp = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await sp.remove(_kUpdateMetadataUrl);
    } else {
      await sp.setString(_kUpdateMetadataUrl, _updateMetadataUrl!);
    }
    notifyListeners();
  }

  /// Genera un `evento_id` determinístico y estable entre dispositivos.
  ///
  /// - Normal: `evento:<disciplinaId>:<fecha>`
  /// - Especial (semanal/sin partido): `evento_especial:<disciplinaId>:<fecha>`
  ///
  /// `fecha` debe venir como YYYY-MM-DD.
  String buildEventoIdDeterministico({
    required int disciplinaId,
    required String fecha,
    required bool especial,
  }) {
    final prefix = especial ? 'evento_especial' : 'evento';
    return const Uuid().v5(Uuid.NAMESPACE_URL, '$prefix:$disciplinaId:$fecha');
  }

  Future<void> setDisciplinaActivaId(int? disciplinaId) async {
    _disciplinaActivaId = disciplinaId;
    final sp = await SharedPreferences.getInstance();
    if (disciplinaId == null) {
      await sp.remove(_kDisciplinaActivaId);
    } else {
      await sp.setInt(_kDisciplinaActivaId, disciplinaId);
    }
    notifyListeners();
  }

  /// Setea el evento activo (normal o especial) y lo persiste.
  ///
  /// - También guarda `disciplina_activa_id`.
  /// - Persistimos `evento_activo_id` para uso directo en `evento_movimiento.evento_id`.
  Future<void> setEventoActivo({
    required int disciplinaId,
    required String fecha,
    required bool especial,
  }) async {
    final eventoId = buildEventoIdDeterministico(
        disciplinaId: disciplinaId, fecha: fecha, especial: especial);

    _disciplinaActivaId = disciplinaId;
    _eventoActivoId = eventoId;
    _eventoActivoFecha = fecha;
    _eventoActivoEsEspecial = especial;

    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kDisciplinaActivaId, disciplinaId);
    await sp.setString(_kEventoActivoId, eventoId);
    await sp.setString(_kEventoActivoFecha, fecha);
    await sp.setBool(_kEventoActivoEsEspecial, especial);
    notifyListeners();
  }

  /// Atajo: setea evento activo usando la fecha local del dispositivo (YYYY-MM-DD).
  Future<void> setEventoActivoHoy({
    required int disciplinaId,
    required bool especial,
  }) async {
    await setEventoActivo(
      disciplinaId: disciplinaId,
      fecha: _todayYmd(),
      especial: especial,
    );
  }

  Future<void> clearEventoActivo() async {
    _eventoActivoId = null;
    _eventoActivoFecha = null;
    _eventoActivoEsEspecial = false;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kEventoActivoId);
    await sp.remove(_kEventoActivoFecha);
    await sp.remove(_kEventoActivoEsEspecial);
    notifyListeners();
  }

  /// Setea la Unidad de Gestión activa para Tesorería
  Future<void> setUnidadGestionActivaId(int? id) async {
    _unidadGestionActivaId = id;
    final sp = await SharedPreferences.getInstance();
    if (id == null) {
      await sp.remove(_kUnidadGestionActivaId);
    } else {
      await sp.setInt(_kUnidadGestionActivaId, id);
    }
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

  Future<void> setCashChangeHelper(bool value) async {
    _cashChangeHelper = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kCashChangeHelper, value);
    notifyListeners();
  }

  // Compat: mapear API vieja de darkMode a nuevo enum
  bool get darkMode => _theme == AppThemeMode.dark;
  Future<void> setDarkMode(bool value) =>
      setTheme(value ? AppThemeMode.dark : AppThemeMode.light);
}
