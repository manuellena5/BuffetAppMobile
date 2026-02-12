import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Servicio para persistir y restaurar filtros de pantallas
/// 
/// Permite guardar filtros aplicados por el usuario en cada pantalla
/// para que se mantengan entre sesiones.
class FiltrosPersistentesService {
  static const String _prefix = 'filtros_';
  
  /// Guardar filtros de una pantalla
  /// 
  /// [screenKey]: Identificador único de la pantalla (ej: 'movimientos_list')
  /// [filtros]: Map con los filtros a guardar
  static Future<void> guardarFiltros(String screenKey, Map<String, dynamic> filtros) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefix + screenKey;
      final json = jsonEncode(filtros);
      await prefs.setString(key, json);
    } catch (e) {
      // Falla silenciosa - los filtros no son críticos
      print('Error guardando filtros para $screenKey: $e');
    }
  }
  
  /// Cargar filtros guardados de una pantalla
  /// 
  /// [screenKey]: Identificador único de la pantalla
  /// Retorna Map con filtros guardados o null si no hay filtros guardados
  static Future<Map<String, dynamic>?> cargarFiltros(String screenKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefix + screenKey;
      final json = prefs.getString(key);
      
      if (json == null) return null;
      
      return Map<String, dynamic>.from(jsonDecode(json));
    } catch (e) {
      print('Error cargando filtros para $screenKey: $e');
      return null;
    }
  }
  
  /// Limpiar filtros guardados de una pantalla
  /// 
  /// [screenKey]: Identificador único de la pantalla
  static Future<void> limpiarFiltros(String screenKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefix + screenKey;
      await prefs.remove(key);
    } catch (e) {
      print('Error limpiando filtros para $screenKey: $e');
    }
  }
  
  /// Verificar si hay filtros guardados para una pantalla
  /// 
  /// [screenKey]: Identificador único de la pantalla
  static Future<bool> tieneFiltrosGuardados(String screenKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefix + screenKey;
      return prefs.containsKey(key);
    } catch (e) {
      return false;
    }
  }
  
  /// Limpiar todos los filtros de todas las pantallas
  static Future<void> limpiarTodosFiltros() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
      
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      print('Error limpiando todos los filtros: $e');
    }
  }
}

/// Keys de pantallas para usar con FiltrosPersistentesService
class FiltrosScreenKeys {
  static const String movimientosList = 'movimientos_list';
  static const String compromisos = 'compromisos';
  static const String plantel = 'plantel';
  static const String acuerdos = 'acuerdos';
  static const String eventos = 'eventos';
}

/// Keys de filtros comunes
class FiltrosKeys {
  // Movimientos
  static const String tipo = 'tipo';
  static const String estado = 'estado';
  static const String mesYear = 'mes_year';
  static const String mesMonth = 'mes_month';
  static const String unidadGestionId = 'unidad_gestion_id';
  static const String categoria = 'categoria';
  
  // Compromisos
  static const String activo = 'activo';
  static const String pausado = 'pausado';
  static const String entidadPlantelId = 'entidad_plantel_id';
  
  // Plantel
  static const String rol = 'rol';
  static const String estadoEntidad = 'estado_entidad';
  static const String busqueda = 'busqueda';
  
  // Eventos
  static const String disciplinaId = 'disciplina_id';
  static const String fechaDesde = 'fecha_desde';
  static const String fechaHasta = 'fecha_hasta';
}
