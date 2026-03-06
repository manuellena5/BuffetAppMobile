import '../../../data/dao/db.dart';
import '../../../domain/safe_map.dart';
import 'saldo_inicial_service.dart';

/// Servicio para generar reportes de resumen (anual y mensual)
class ReporteResumenService {
  /// Obtiene el resumen anual consolidado
  /// Incluye: saldo inicial del año, ingresos acumulados, egresos acumulados, saldo actual
  static Future<Map<String, double>> obtenerResumenAnual({
    required int year,
    int? unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Obtener saldo inicial del año (desde SaldoInicialService)
      double saldoInicialAnio = 0.0;
      if (unidadGestionId != null) {
        saldoInicialAnio = await SaldoInicialService.calcularSaldoInicialMes(
          unidadGestionId: unidadGestionId,
          anio: year,
          mes: 1,
        );
      }
      
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
          AND estado = 'CONFIRMADO'
      ''';
      
      final params = <dynamic>[inicioAnio, finAnio];
      
      if (unidadGestionId != null) {
        query += ' AND disciplina_id = ?';
        params.add(unidadGestionId);
      }
      
      final result = await db.rawQuery(query, params);
      
      final ingresos = result.first.safeDouble('total_ingresos');
      final egresos = result.first.safeDouble('total_egresos');
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
  
  /// Obtiene el resumen mensual (mes a mes) hasta el mes actual del año.
  /// Usa una sola query con GROUP BY para evitar N+1.
  /// Incluye saldo acumulado progresivo con saldo inicial integrado.
  static Future<List<Map<String, dynamic>>> obtenerResumenMensual({
    required int year,
    int? unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final ahora = DateTime.now();
      final mesLimite = year == ahora.year ? ahora.month : 12;
      
      // Obtener saldo inicial del año (desde SaldoInicialService)
      double saldoInicialAnio = 0.0;
      if (unidadGestionId != null) {
        saldoInicialAnio = await SaldoInicialService.calcularSaldoInicialMes(
          unidadGestionId: unidadGestionId,
          anio: year,
          mes: 1,
        );
      }
      
      // Calcular rango del año completo
      final inicioAnio = DateTime(year, 1, 1).millisecondsSinceEpoch;
      final finAnio = DateTime(year, mesLimite + 1, 0, 23, 59, 59).millisecondsSinceEpoch;
      
      // Una sola query con GROUP BY mes (extraído de created_ts epoch → mes)
      var query = '''
        SELECT 
          CAST(strftime('%m', datetime(created_ts / 1000, 'unixepoch', 'localtime')) AS INTEGER) as mes,
          SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as ingresos,
          SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as egresos
        FROM evento_movimiento
        WHERE created_ts >= ? AND created_ts <= ?
          AND eliminado = 0
          AND estado = 'CONFIRMADO'
      ''';
      
      final params = <dynamic>[inicioAnio, finAnio];
      
      if (unidadGestionId != null) {
        query += ' AND disciplina_id = ?';
        params.add(unidadGestionId);
      }
      
      query += '''
        GROUP BY CAST(strftime('%m', datetime(created_ts / 1000, 'unixepoch', 'localtime')) AS INTEGER)
        ORDER BY mes
      ''';
      
      final rows = await db.rawQuery(query, params);
      
      // Indexar resultados por mes para acceso O(1)
      final porMes = <int, Map<String, dynamic>>{};
      for (final row in rows) {
        final mes = row.safeInt('mes');
        porMes[mes] = row;
      }
      
      // Construir resultado con saldo acumulado progresivo
      final resultado = <Map<String, dynamic>>[];
      double saldoAcumulado = saldoInicialAnio;
      
      for (var mes = 1; mes <= mesLimite; mes++) {
        final row = porMes[mes];
        final ingresos = row?.safeDouble('ingresos') ?? 0.0;
        final egresos = row?.safeDouble('egresos') ?? 0.0;
        saldoAcumulado += ingresos - egresos;
        
        resultado.add({
          'mes': mes,
          'ingresos': ingresos,
          'egresos': egresos,
          'saldo': ingresos - egresos,
          'saldo_acumulado': saldoAcumulado,
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
