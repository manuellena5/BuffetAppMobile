import '../../../data/dao/db.dart';

/// Servicio para generar reportes de resumen (anual y mensual)
class ReporteResumenService {
  /// Obtiene el resumen anual consolidado
  /// Incluye: saldo inicial (por ahora 0), ingresos acumulados, egresos acumulados, saldo actual
  static Future<Map<String, double>> obtenerResumenAnual({
    required int year,
    int? unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Por ahora el saldo inicial del año es 0
      // TODO: obtener desde configuración cuando se implemente
      final saldoInicialAnio = 0.0;
      
      // Calcular fechas
      final inicioAnio = DateTime(year, 1, 1).millisecondsSinceEpoch;
      final finAnio = DateTime(year, 12, 31, 23, 59, 59).millisecondsSinceEpoch;
      
      // Query base
      var query = '''
        SELECT 
          SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as total_ingresos,
          SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as total_egresos
        FROM evento_movimiento
        WHERE created_ts >= ? AND created_ts <= ?
          AND eliminado = 0
      ''';
      
      final params = <dynamic>[inicioAnio, finAnio];
      
      if (unidadGestionId != null) {
        query += ' AND disciplina_id = ?';
        params.add(unidadGestionId);
      }
      
      final result = await db.rawQuery(query, params);
      
      final ingresos = (result.first['total_ingresos'] as num?)?.toDouble() ?? 0.0;
      final egresos = (result.first['total_egresos'] as num?)?.toDouble() ?? 0.0;
      final saldoActual = saldoInicialAnio + ingresos - egresos;
      
      return {
        'saldo_inicial': saldoInicialAnio,
        'ingresos_acumulados': ingresos,
        'egresos_acumulados': egresos,
        'saldo_actual': saldoActual,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'reporte_resumen.obtener_anual',
        error: e,
        stackTrace: st,
        payload: {'year': year, 'unidad': unidadGestionId},
      );
      rethrow;
    }
  }
  
  /// Obtiene el resumen mensual (mes a mes) hasta el mes actual del año
  /// Retorna lista con: mes (1-12), ingresos, egresos, saldo
  static Future<List<Map<String, dynamic>>> obtenerResumenMensual({
    required int year,
    int? unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final ahora = DateTime.now();
      final mesLimite = year == ahora.year ? ahora.month : 12;
      
      final resultado = <Map<String, dynamic>>[];
      
      for (var mes = 1; mes <= mesLimite; mes++) {
        final inicioMes = DateTime(year, mes, 1).millisecondsSinceEpoch;
        final finMes = DateTime(year, mes + 1, 0, 23, 59, 59).millisecondsSinceEpoch;
        
        var query = '''
          SELECT 
            SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as ingresos,
            SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as egresos
          FROM evento_movimiento
          WHERE created_ts >= ? AND created_ts <= ?
            AND eliminado = 0
        ''';
        
        final params = <dynamic>[inicioMes, finMes];
        
        if (unidadGestionId != null) {
          query += ' AND disciplina_id = ?';
          params.add(unidadGestionId);
        }
        
        final result = await db.rawQuery(query, params);
        
        final ingresos = (result.first['ingresos'] as num?)?.toDouble() ?? 0.0;
        final egresos = (result.first['egresos'] as num?)?.toDouble() ?? 0.0;
        final saldo = ingresos - egresos;
        
        resultado.add({
          'mes': mes,
          'ingresos': ingresos,
          'egresos': egresos,
          'saldo': saldo,
        });
      }
      
      return resultado;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'reporte_resumen.obtener_mensual',
        error: e,
        stackTrace: st,
        payload: {'year': year, 'unidad': unidadGestionId},
      );
      rethrow;
    }
  }
}
