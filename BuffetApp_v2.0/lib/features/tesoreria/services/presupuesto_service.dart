import '../../../data/dao/db.dart';

/// Servicio CRUD para partidas presupuestarias anuales.
///
/// Cada partida define un monto mensual presupuestado para una categoría
/// de ingreso/egreso en una unidad de gestión y año determinados.
class PresupuestoService {
  PresupuestoService._();
  static final PresupuestoService instance = PresupuestoService._();

  // ─────────── CRUD ───────────

  /// Inserta una nueva partida presupuestaria.
  /// Retorna el id del registro insertado.
  Future<int> crear({
    required int unidadGestionId,
    required String categoriaCodigo,
    required String tipo, // INGRESO | EGRESO
    required int anio,
    required double montoMensual,
    String? observacion,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      final id = await db.insert('presupuesto_anual', {
        'unidad_gestion_id': unidadGestionId,
        'categoria_codigo': categoriaCodigo,
        'tipo': tipo,
        'anio': anio,
        'monto_mensual': montoMensual,
        'observacion': observacion,
        'eliminado': 0,
        'created_ts': now,
        'updated_ts': now,
      });

      return id;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.crear',
        error: e.toString(),
        stackTrace: st,
        payload: {
          'unidad': unidadGestionId,
          'cat': categoriaCodigo,
          'tipo': tipo,
          'anio': anio,
        },
      );
      rethrow;
    }
  }

  /// Actualiza una partida existente.
  Future<void> actualizar({
    required int id,
    required double montoMensual,
    String? observacion,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.update(
        'presupuesto_anual',
        {
          'monto_mensual': montoMensual,
          'observacion': observacion,
          'updated_ts': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.actualizar',
        error: e.toString(),
        stackTrace: st,
        payload: {'id': id, 'monto': montoMensual},
      );
      rethrow;
    }
  }

  /// Soft-delete de una partida.
  Future<void> eliminar(int id) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.update(
        'presupuesto_anual',
        {'eliminado': 1, 'updated_ts': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.eliminar',
        error: e.toString(),
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  // ─────────── Queries ───────────

  /// Obtiene todas las partidas activas de un año y unidad.
  Future<List<Map<String, dynamic>>> listar({
    required int unidadGestionId,
    required int anio,
    String? tipo, // opcional: filtrar por INGRESO o EGRESO
  }) async {
    try {
      final db = await AppDatabase.instance();

      var where = 'p.unidad_gestion_id = ? AND p.anio = ? AND p.eliminado = 0';
      final args = <dynamic>[unidadGestionId, anio];

      if (tipo != null) {
        where += ' AND p.tipo = ?';
        args.add(tipo);
      }

      // JOIN con categoria_movimiento para nombre legible
      final rows = await db.rawQuery('''
        SELECT 
          p.*,
          COALESCE(cm.nombre, p.categoria_codigo) as categoria_nombre
        FROM presupuesto_anual p
        LEFT JOIN categoria_movimiento cm 
          ON cm.codigo = p.categoria_codigo AND cm.activa = 1
        WHERE $where
        ORDER BY p.tipo ASC, categoria_nombre ASC
      ''', args);

      return rows;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.listar',
        error: e.toString(),
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'anio': anio},
      );
      rethrow;
    }
  }

  /// Obtiene el presupuesto mensual total (sumado) por tipo para un año/unidad.
  /// Retorna `{ingresos_mensuales, egresos_mensuales, saldo_mensual}`.
  Future<Map<String, double>> obtenerTotalesMensuales({
    required int unidadGestionId,
    required int anio,
  }) async {
    try {
      final db = await AppDatabase.instance();

      final rows = await db.rawQuery('''
        SELECT 
          tipo,
          SUM(monto_mensual) as total
        FROM presupuesto_anual
        WHERE unidad_gestion_id = ? AND anio = ? AND eliminado = 0
        GROUP BY tipo
      ''', [unidadGestionId, anio]);

      double ingresos = 0.0;
      double egresos = 0.0;

      for (final row in rows) {
        final tipo = row['tipo']?.toString() ?? '';
        final total = (row['total'] as num?)?.toDouble() ?? 0.0;
        if (tipo == 'INGRESO') {
          ingresos = total;
        } else if (tipo == 'EGRESO') {
          egresos = total;
        }
      }

      return {
        'ingresos_mensuales': ingresos,
        'egresos_mensuales': egresos,
        'saldo_mensual': ingresos - egresos,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.totales_mensuales',
        error: e.toString(),
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'anio': anio},
      );
      rethrow;
    }
  }

  /// Comparativa presupuesto vs ejecución mes a mes.
  ///
  /// Retorna lista con un map por mes:
  /// ```
  /// {
  ///   mes, presupuesto_ingresos, presupuesto_egresos,
  ///   real_ingresos, real_egresos,
  ///   desvio_ingresos, desvio_egresos,
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> comparativaVsEjecucion({
    required int anio,
    required int unidadGestionId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final ahora = DateTime.now();
      final mesLimite = anio == ahora.year ? ahora.month : 12;

      // 1) Presupuesto mensual por tipo
      final presRows = await db.rawQuery('''
        SELECT 
          tipo,
          SUM(monto_mensual) as total
        FROM presupuesto_anual
        WHERE unidad_gestion_id = ? AND anio = ? AND eliminado = 0
        GROUP BY tipo
      ''', [unidadGestionId, anio]);

      double presIngresos = 0.0;
      double presEgresos = 0.0;
      for (final r in presRows) {
        final t = r['tipo']?.toString() ?? '';
        final v = (r['total'] as num?)?.toDouble() ?? 0.0;
        if (t == 'INGRESO') presIngresos = v;
        if (t == 'EGRESO') presEgresos = v;
      }

      // 2) Ejecución real mes a mes
      final inicioAnio = DateTime(anio, 1, 1).millisecondsSinceEpoch;
      final finAnio = DateTime(anio, mesLimite + 1, 0, 23, 59, 59).millisecondsSinceEpoch;

      final realRows = await db.rawQuery('''
        SELECT 
          CAST(strftime('%m', datetime(created_ts / 1000, 'unixepoch', 'localtime')) AS INTEGER) as mes,
          SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as real_ingresos,
          SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as real_egresos
        FROM evento_movimiento
        WHERE created_ts >= ? AND created_ts <= ?
          AND eliminado = 0
          AND estado = 'CONFIRMADO'
          AND disciplina_id = ?
        GROUP BY CAST(strftime('%m', datetime(created_ts / 1000, 'unixepoch', 'localtime')) AS INTEGER)
        ORDER BY mes
      ''', [inicioAnio, finAnio, unidadGestionId]);

      final porMes = <int, Map<String, dynamic>>{};
      for (final r in realRows) {
        porMes[r['mes'] as int] = r;
      }

      // 3) Construir comparativa
      final resultado = <Map<String, dynamic>>[];
      for (var m = 1; m <= mesLimite; m++) {
        final real = porMes[m];
        final rIng = (real?['real_ingresos'] as num?)?.toDouble() ?? 0.0;
        final rEgr = (real?['real_egresos'] as num?)?.toDouble() ?? 0.0;

        resultado.add({
          'mes': m,
          'presupuesto_ingresos': presIngresos,
          'presupuesto_egresos': presEgresos,
          'real_ingresos': rIng,
          'real_egresos': rEgr,
          'desvio_ingresos': rIng - presIngresos,
          'desvio_egresos': rEgr - presEgresos,
        });
      }

      return resultado;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.comparativa',
        error: e.toString(),
        stackTrace: st,
        payload: {'anio': anio, 'unidad': unidadGestionId},
      );
      rethrow;
    }
  }

  /// Obtiene las categorías disponibles para presupuesto (de categoria_movimiento).
  Future<List<Map<String, dynamic>>> obtenerCategorias({String? tipo}) async {
    try {
      final db = await AppDatabase.instance();
      var where = 'activa = 1';
      final args = <dynamic>[];

      if (tipo != null) {
        where += " AND (tipo = ? OR tipo = 'AMBOS')";
        args.add(tipo);
      }

      return await db.query(
        'categoria_movimiento',
        where: where,
        whereArgs: args,
        orderBy: 'tipo ASC, nombre ASC',
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto.obtener_categorias',
        error: e.toString(),
        stackTrace: st,
      );
      rethrow;
    }
  }
}
