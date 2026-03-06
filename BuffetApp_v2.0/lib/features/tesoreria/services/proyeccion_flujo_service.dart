import '../../../data/dao/db.dart';
import 'saldo_inicial_service.dart';

/// Servicio para calcular la proyección de flujo de caja.
///
/// Combina:
/// - Saldo actual (movimientos confirmados)
/// - Compromisos esperados futuros (INGRESO y EGRESO)
/// - Presupuesto mensual (como referencia)
///
/// Genera proyección a 1, 3 y 6 meses.
class ProyeccionFlujoService {
  ProyeccionFlujoService._();
  static final ProyeccionFlujoService instance = ProyeccionFlujoService._();

  /// Calcula la proyección de flujo de caja a futuro.
  ///
  /// Retorna una lista con un map por cada mes futuro:
  /// ```
  /// {
  ///   mes, anio,
  ///   saldo_inicio_mes,
  ///   compromisos_ingresos, compromisos_egresos,
  ///   presupuesto_ingresos, presupuesto_egresos,
  ///   saldo_proyectado,
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> calcularProyeccion({
    required int unidadGestionId,
    int mesesFuturos = 6,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final ahora = DateTime.now();

      // 1) Saldo actual: saldo inicial del año + movimientos confirmados hasta hoy
      final saldoActual = await _calcularSaldoActual(
        db: db,
        unidadGestionId: unidadGestionId,
        hasta: ahora,
      );

      // 2) Compromisos esperados agrupados por mes
      final compromisosPorMes = await _obtenerCompromisosFuturos(
        db: db,
        unidadGestionId: unidadGestionId,
        desde: ahora,
        meses: mesesFuturos,
      );

      // 3) Presupuesto mensual (constante por mes)
      final presupuesto = await _obtenerPresupuestoMensual(
        db: db,
        unidadGestionId: unidadGestionId,
        anio: ahora.year,
      );

      // 4) Construir proyección mes a mes
      final resultado = <Map<String, dynamic>>[];
      double saldoAcum = saldoActual;

      for (var i = 1; i <= mesesFuturos; i++) {
        final fecha = DateTime(ahora.year, ahora.month + i, 1);
        final mes = fecha.month;
        final anio = fecha.year;
        final key = '$anio-${mes.toString().padLeft(2, '0')}';

        final comp = compromisosPorMes[key] ?? {'ingresos': 0.0, 'egresos': 0.0};
        final compIng = (comp['ingresos'] as num?)?.toDouble() ?? 0.0;
        final compEgr = (comp['egresos'] as num?)?.toDouble() ?? 0.0;

        // Si hay compromisos, usar compromisos; si no, usar presupuesto como estimado
        final ingProyectado = compIng > 0 ? compIng : (presupuesto['ingresos'] ?? 0.0);
        final egrProyectado = compEgr > 0 ? compEgr : (presupuesto['egresos'] ?? 0.0);

        final saldoInicioMes = saldoAcum;
        saldoAcum += ingProyectado - egrProyectado;

        resultado.add({
          'mes': mes,
          'anio': anio,
          'saldo_inicio_mes': saldoInicioMes,
          'compromisos_ingresos': compIng,
          'compromisos_egresos': compEgr,
          'presupuesto_ingresos': presupuesto['ingresos'] ?? 0.0,
          'presupuesto_egresos': presupuesto['egresos'] ?? 0.0,
          'ingresos_proyectados': ingProyectado,
          'egresos_proyectados': egrProyectado,
          'saldo_proyectado': saldoAcum,
        });
      }

      return resultado;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'proyeccion_flujo.calcular',
        error: e.toString(),
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'meses': mesesFuturos},
      );
      rethrow;
    }
  }

  /// Resumen rápido a 1, 3 y 6 meses.
  /// Retorna `{saldo_actual, saldo_1m, saldo_3m, saldo_6m}`.
  Future<Map<String, double>> resumenRapido({
    required int unidadGestionId,
  }) async {
    try {
      final proyeccion = await calcularProyeccion(
        unidadGestionId: unidadGestionId,
        mesesFuturos: 6,
      );

      final saldoActual = proyeccion.isNotEmpty
          ? (proyeccion.first['saldo_inicio_mes'] as num?)?.toDouble() ?? 0.0
          : 0.0;

      double saldo1m = saldoActual;
      double saldo3m = saldoActual;
      double saldo6m = saldoActual;

      if (proyeccion.isNotEmpty) {
        saldo1m = (proyeccion.first['saldo_proyectado'] as num?)?.toDouble() ?? saldoActual;
      }
      if (proyeccion.length >= 3) {
        saldo3m = (proyeccion[2]['saldo_proyectado'] as num?)?.toDouble() ?? saldoActual;
      }
      if (proyeccion.length >= 6) {
        saldo6m = (proyeccion[5]['saldo_proyectado'] as num?)?.toDouble() ?? saldoActual;
      }

      return {
        'saldo_actual': saldoActual,
        'saldo_1m': saldo1m,
        'saldo_3m': saldo3m,
        'saldo_6m': saldo6m,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'proyeccion_flujo.resumen_rapido',
        error: e.toString(),
        stackTrace: st,
        payload: {'unidad': unidadGestionId},
      );
      rethrow;
    }
  }

  // ─────────── Helpers privados ───────────

  /// Saldo actual = saldo inicial del año + movimientos confirmados hasta [hasta].
  Future<double> _calcularSaldoActual({
    required dynamic db,
    required int unidadGestionId,
    required DateTime hasta,
  }) async {
    final anio = hasta.year;

    // Saldo inicial del año
    final saldoInicial = await SaldoInicialService.calcularSaldoInicialMes(
      unidadGestionId: unidadGestionId,
      anio: anio,
      mes: 1,
    );

    // Movimientos confirmados desde inicio de año hasta hoy
    final inicioAnio = DateTime(anio, 1, 1).millisecondsSinceEpoch;
    final hastaMs = hasta.millisecondsSinceEpoch;

    final rows = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as ingresos,
        SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as egresos
      FROM evento_movimiento
      WHERE created_ts >= ? AND created_ts <= ?
        AND eliminado = 0
        AND estado = 'CONFIRMADO'
        AND disciplina_id = ?
    ''', [inicioAnio, hastaMs, unidadGestionId]);

    final ingresos = (rows.first['ingresos'] as num?)?.toDouble() ?? 0.0;
    final egresos = (rows.first['egresos'] as num?)?.toDouble() ?? 0.0;

    return saldoInicial + ingresos - egresos;
  }

  /// Obtiene compromisos ESPERADO futuros agrupados por YYYY-MM.
  Future<Map<String, Map<String, double>>> _obtenerCompromisosFuturos({
    required dynamic db,
    required int unidadGestionId,
    required DateTime desde,
    required int meses,
  }) async {
    final hastaFecha = DateTime(desde.year, desde.month + meses + 1, 0);
    final desdeFechaStr = '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
    final hastaFechaStr = '${hastaFecha.year}-${hastaFecha.month.toString().padLeft(2, '0')}-${hastaFecha.day.toString().padLeft(2, '0')}';

    final rows = await db.rawQuery('''
      SELECT 
        substr(fecha_vencimiento, 1, 7) as mes_key,
        tipo,
        SUM(monto) as total
      FROM compromisos
      WHERE unidad_gestion_id = ?
        AND estado = 'ESPERADO'
        AND eliminado = 0
        AND fecha_vencimiento >= ?
        AND fecha_vencimiento <= ?
      GROUP BY substr(fecha_vencimiento, 1, 7), tipo
    ''', [unidadGestionId, desdeFechaStr, hastaFechaStr]);

    final resultado = <String, Map<String, double>>{};
    for (final row in rows) {
      final key = row['mes_key']?.toString() ?? '';
      final tipo = row['tipo']?.toString() ?? '';
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;

      resultado.putIfAbsent(key, () => {'ingresos': 0.0, 'egresos': 0.0});
      if (tipo == 'INGRESO') {
        resultado[key]!['ingresos'] = total;
      } else if (tipo == 'EGRESO') {
        resultado[key]!['egresos'] = total;
      }
    }

    return resultado;
  }

  /// Presupuesto mensual total por tipo.
  Future<Map<String, double>> _obtenerPresupuestoMensual({
    required dynamic db,
    required int unidadGestionId,
    required int anio,
  }) async {
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
      if (tipo == 'INGRESO') ingresos = total;
      if (tipo == 'EGRESO') egresos = total;
    }

    return {'ingresos': ingresos, 'egresos': egresos};
  }
}
