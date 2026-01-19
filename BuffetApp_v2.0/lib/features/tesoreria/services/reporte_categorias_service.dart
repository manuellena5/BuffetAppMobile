import '../../../data/dao/db.dart';

/// Servicio para generación de reportes por categorías de movimientos
class ReporteCategoriasService {
  /// Obtiene resumen de movimientos por categoría en un rango de fechas
  /// Retorna lista de Map con: categoria_codigo, categoria_nombre, tipo, ingresos, egresos, saldo
  static Future<List<Map<String, dynamic>>> obtenerResumenPorCategoria({
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    int? unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Convertir fechas a timestamps (epoch ms)
      final tsDesde = fechaDesde.millisecondsSinceEpoch;
      final tsHasta = fechaHasta.add(const Duration(days: 1)).millisecondsSinceEpoch; // incluir todo el día
      
      String where = 'em.created_ts >= ? AND em.created_ts < ? AND em.eliminado = 0';
      List<dynamic> whereArgs = [tsDesde, tsHasta];
      
      if (unidadGestionId != null) {
        where += ' AND em.unidad_gestion_id = ?';
        whereArgs.add(unidadGestionId);
      }
      
      final query = '''
        SELECT 
          COALESCE(em.categoria, 'Sin categoría') as categoria_codigo,
          COALESCE(cm.nombre, em.categoria, 'Sin categoría') as categoria,
          em.tipo,
          SUM(CASE WHEN em.tipo = 'INGRESO' THEN em.monto ELSE 0 END) as total_ingresos,
          SUM(CASE WHEN em.tipo = 'EGRESO' THEN em.monto ELSE 0 END) as total_egresos,
          COUNT(*) as cantidad_movimientos
        FROM evento_movimiento em
        LEFT JOIN categoria_movimiento cm ON em.categoria = cm.codigo
        WHERE $where
        GROUP BY em.categoria, cm.nombre, em.tipo
        ORDER BY categoria ASC
      ''';
      
      final rows = await db.rawQuery(query, whereArgs);
      
      // Consolidar por categoría (agrupar ingresos y egresos de la misma categoría)
      final Map<String, Map<String, dynamic>> consolidado = {};
      
      for (final row in rows) {
        final categoria = row['categoria'] as String;
        if (!consolidado.containsKey(categoria)) {
          consolidado[categoria] = {
            'categoria': categoria,
            'total_ingresos': 0.0,
            'total_egresos': 0.0,
            'cantidad_movimientos': 0,
            'saldo': 0.0,
          };
        }
        
        final ingresos = (row['total_ingresos'] as num?)?.toDouble() ?? 0.0;
        final egresos = (row['total_egresos'] as num?)?.toDouble() ?? 0.0;
        final cantidad = (row['cantidad_movimientos'] as int?) ?? 0;
        
        consolidado[categoria]!['total_ingresos'] = 
            (consolidado[categoria]!['total_ingresos'] as double) + ingresos;
        consolidado[categoria]!['total_egresos'] = 
            (consolidado[categoria]!['total_egresos'] as double) + egresos;
        consolidado[categoria]!['cantidad_movimientos'] = 
            (consolidado[categoria]!['cantidad_movimientos'] as int) + cantidad;
      }
      
      // Calcular saldos
      for (final item in consolidado.values) {
        item['saldo'] = (item['total_ingresos'] as double) - (item['total_egresos'] as double);
      }
      
      return consolidado.values.toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'reporte_categorias.obtenerResumen',
        error: e,
        stackTrace: st,
        payload: {
          'fechaDesde': fechaDesde.toIso8601String(),
          'fechaHasta': fechaHasta.toIso8601String(),
          'unidadGestionId': unidadGestionId,
        },
      );
      rethrow;
    }
  }

  /// Obtiene totales generales de un período
  static Future<Map<String, double>> obtenerTotalesGenerales({
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    int? unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      final tsDesde = fechaDesde.millisecondsSinceEpoch;
      final tsHasta = fechaHasta.add(const Duration(days: 1)).millisecondsSinceEpoch;
      
      String where = 'created_ts >= ? AND created_ts < ? AND eliminado = 0';
      List<dynamic> whereArgs = [tsDesde, tsHasta];
      
      if (unidadGestionId != null) {
        where += ' AND unidad_gestion_id = ?';
        whereArgs.add(unidadGestionId);
      }
      
      final query = '''
        SELECT 
          SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as total_ingresos,
          SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as total_egresos
        FROM evento_movimiento
        WHERE $where
      ''';
      
      final rows = await db.rawQuery(query, whereArgs);
      
      if (rows.isEmpty) {
        return {
          'ingresos': 0.0,
          'egresos': 0.0,
          'saldo': 0.0,
        };
      }
      
      final row = rows.first;
      final ingresos = (row['total_ingresos'] as num?)?.toDouble() ?? 0.0;
      final egresos = (row['total_egresos'] as num?)?.toDouble() ?? 0.0;
      
      return {
        'ingresos': ingresos,
        'egresos': egresos,
        'saldo': ingresos - egresos,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'reporte_categorias.obtenerTotales',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }
}
