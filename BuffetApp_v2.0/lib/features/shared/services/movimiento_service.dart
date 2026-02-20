import 'package:intl/intl.dart';

import '../../../data/dao/db.dart';

class MovimientoService {
  Future<List<Map<String, dynamic>>> listarPorCaja(int cajaId) async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery('''
        SELECT cm.*, mp.descripcion as medio_pago_desc
        FROM caja_movimiento cm
        LEFT JOIN metodos_pago mp ON mp.id = cm.medio_pago_id
        WHERE cm.caja_id=?
        ORDER BY cm.created_ts DESC
      ''', [cajaId]);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.listar', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<int> crear({required int cajaId, required String tipo, required double monto, String? observacion, int medioPagoId = 1}) async {
    try {
      final db = await AppDatabase.instance();
      return await db.insert('caja_movimiento', {
        'caja_id': cajaId,
        'tipo': tipo.toUpperCase(),
        'monto': monto,
        'observacion': observacion,
        'medio_pago_id': medioPagoId,
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.crear', error: e, stackTrace: st, payload: {'cajaId': cajaId,'tipo': tipo,'monto': monto,'medioPagoId': medioPagoId});
      rethrow;
    }
  }

  Future<void> actualizar({required int id, required String tipo, required double monto, String? observacion, int medioPagoId = 1}) async {
    try {
      final db = await AppDatabase.instance();
      await db.update('caja_movimiento', {
        'tipo': tipo.toUpperCase(),
        'monto': monto,
        'observacion': observacion,
        'medio_pago_id': medioPagoId,
      }, where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.actualizar', error: e, stackTrace: st, payload: {'id': id,'tipo': tipo,'monto': monto,'medioPagoId': medioPagoId});
      rethrow;
    }
  }

  Future<void> eliminar(int id) async {
    try {
      final db = await AppDatabase.instance();
      await db.delete('caja_movimiento', where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.eliminar', error: e, stackTrace: st, payload: {'id': id});
      rethrow;
    }
  }

  /// Totales globales (retrocompatible)
  Future<Map<String, double>> totalesPorCaja(int cajaId) async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN tipo='INGRESO' THEN monto END),0) as ingresos,
        COALESCE(SUM(CASE WHEN tipo='RETIRO' THEN monto END),0) as retiros
      FROM caja_movimiento WHERE caja_id=?
      ''', [cajaId]);
      final r = rows.first;
      return {
        'ingresos': (r['ingresos'] as num).toDouble(),
        'retiros': (r['retiros'] as num).toDouble(),
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.totales', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  /// Totales desglosados por medio de pago:
  /// Retorna mapa con claves: ingresosEfectivo, retirosEfectivo, ingresosTransferencia, retirosTransferencia
  Future<Map<String, double>> totalesPorCajaPorMp(int cajaId) async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery('''
        SELECT 
          COALESCE(SUM(CASE WHEN cm.tipo='INGRESO' AND LOWER(mp.descripcion) LIKE '%efectivo%' THEN cm.monto END),0) as ingresos_efectivo,
          COALESCE(SUM(CASE WHEN cm.tipo='RETIRO'  AND LOWER(mp.descripcion) LIKE '%efectivo%' THEN cm.monto END),0) as retiros_efectivo,
          COALESCE(SUM(CASE WHEN cm.tipo='INGRESO' AND LOWER(mp.descripcion) LIKE '%transfer%' THEN cm.monto END),0) as ingresos_transferencia,
          COALESCE(SUM(CASE WHEN cm.tipo='RETIRO'  AND LOWER(mp.descripcion) LIKE '%transfer%' THEN cm.monto END),0) as retiros_transferencia,
          COALESCE(SUM(CASE WHEN cm.tipo='INGRESO' THEN cm.monto END),0) as ingresos_total,
          COALESCE(SUM(CASE WHEN cm.tipo='RETIRO'  THEN cm.monto END),0) as retiros_total
        FROM caja_movimiento cm
        LEFT JOIN metodos_pago mp ON mp.id = cm.medio_pago_id
        WHERE cm.caja_id=?
      ''', [cajaId]);
      final r = rows.first;
      return {
        'ingresosEfectivo': (r['ingresos_efectivo'] as num).toDouble(),
        'retirosEfectivo': (r['retiros_efectivo'] as num).toDouble(),
        'ingresosTransferencia': (r['ingresos_transferencia'] as num).toDouble(),
        'retirosTransferencia': (r['retiros_transferencia'] as num).toDouble(),
        'ingresosTotal': (r['ingresos_total'] as num).toDouble(),
        'retirosTotal': (r['retiros_total'] as num).toDouble(),
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.totalesPorMp', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }
}

class EventoMovimientoService {
  Future<int> crear({
    required int disciplinaId,
    required int cuentaId,
    String? eventoId,
    required String tipo,
    String? categoria,
    required double monto,
    required int medioPagoId,
    DateTime? fecha,
    String? observacion,
    String? dispositivoId,
    String? archivoLocalPath,
    String? archivoRemoteUrl,
    String? archivoNombre,
    String? archivoTipo,
    int? archivoSize,
    int? compromisoId,
    int? entidadPlantelId,
    String? estado,
    int? esTransferencia,
    String? transferenciaId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Si no se proporciona fecha, usar hoy
      final fechaStr = fecha != null
          ? DateFormat('yyyy-MM-dd').format(fecha)
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      return await db.insert('evento_movimiento', {
        'evento_id': eventoId,
        'disciplina_id': disciplinaId,
        'cuenta_id': cuentaId,
        'tipo': tipo.toUpperCase(),
        'categoria': categoria,
        'monto': monto,
        'medio_pago_id': medioPagoId,
        'fecha': fechaStr,
        'observacion': observacion,
        'es_transferencia': esTransferencia ?? 0,
        'transferencia_id': transferenciaId,
        'dispositivo_id': dispositivoId,
        'archivo_local_path': archivoLocalPath,
        'archivo_remote_url': archivoRemoteUrl,
        'archivo_nombre': archivoNombre,
        'archivo_tipo': archivoTipo,
        'archivo_size': archivoSize,
        'compromiso_id': compromisoId,
        'entidad_plantel_id': entidadPlantelId,
        'estado': estado ?? 'CONFIRMADO',
        // created_ts + sync_estado usan DEFAULT
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.crear',
          error: e,
          stackTrace: st,
          payload: {
            'disciplinaId': disciplinaId,
            'eventoId': eventoId,
            'tipo': tipo,
            'categoria': categoria,
            'monto': monto,
            'medioPagoId': medioPagoId,
          });
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> obtenerPorId(int id) async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery('''
        SELECT
          em.*,
          mp.descripcion as medio_pago_desc,
          c.nombre as compromiso_nombre,
          ep_compromiso.nombre as entidad_compromiso_nombre,
          ep_compromiso.rol as entidad_compromiso_rol,
          ep_directo.nombre as entidad_directo_nombre,
          ep_directo.rol as entidad_directo_rol
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
        LEFT JOIN compromisos c ON c.id = em.compromiso_id
        LEFT JOIN entidades_plantel ep_compromiso ON ep_compromiso.id = c.entidad_plantel_id
        LEFT JOIN entidades_plantel ep_directo ON ep_directo.id = em.entidad_plantel_id
        WHERE em.id = ?
        LIMIT 1
      ''', [id]);
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.get', error: e, stackTrace: st, payload: {'id': id});
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listar({
    int? disciplinaId,
    String? eventoId,
    int limit = 200,
    bool incluirEliminados = false,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final where = <String>[];
      final args = <Object?>[];
      
      // Por defecto, excluir eliminados
      if (!incluirEliminados) {
        where.add('(em.eliminado IS NULL OR em.eliminado = 0)');
      }
      
      if (disciplinaId != null) {
        where.add('em.disciplina_id=?');
        args.add(disciplinaId);
      }
      if (eventoId != null) {
        where.add('em.evento_id=?');
        args.add(eventoId);
      }
      final whereSql = where.isEmpty ? '' : 'WHERE ' + where.join(' AND ');

      final rows = await db.rawQuery('''
        SELECT
          em.*,
          mp.descripcion as medio_pago_desc,
          c.nombre as compromiso_nombre
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
        LEFT JOIN compromisos c ON c.id = em.compromiso_id
        $whereSql
        ORDER BY em.created_ts DESC
        LIMIT $limit
      ''', args);

      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.listar',
          error: e,
          stackTrace: st,
          payload: {'disciplinaId': disciplinaId, 'eventoId': eventoId, 'limit': limit});
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listarPendientes({
    int? disciplinaId,
    int limit = 200,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final where = <String>["em.sync_estado IN ('PENDIENTE','ERROR')"];
      final args = <Object?>[];
      if (disciplinaId != null) {
        where.add('em.disciplina_id=?');
        args.add(disciplinaId);
      }
      final whereSql = 'WHERE ' + where.join(' AND ');

      final rows = await db.rawQuery('''
        SELECT
          em.*,
          mp.descripcion as medio_pago_desc,
          c.nombre as compromiso_nombre
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
        LEFT JOIN compromisos c ON c.id = em.compromiso_id
        $whereSql
        ORDER BY em.created_ts DESC
        LIMIT $limit
      ''', args);

      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.pendientes',
          error: e,
          stackTrace: st,
          payload: {'disciplinaId': disciplinaId, 'limit': limit});
      rethrow;
    }
  }

  Future<void> actualizar({
    required int id,
    required int disciplinaId,
    required int cuentaId,
    String? eventoId,
    required String tipo,
    String? categoria,
    required double monto,
    required int medioPagoId,
    String? observacion,
    String? archivoLocalPath,
    String? archivoNombre,
    String? archivoTipo,
    int? archivoSize,
    int? entidadPlantelId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      await db.update('evento_movimiento', {
        'evento_id': eventoId,
        'disciplina_id': disciplinaId,
        'cuenta_id': cuentaId,
        'tipo': tipo.toUpperCase(),
        'categoria': categoria,
        'monto': monto,
        'medio_pago_id': medioPagoId,
        'observacion': observacion,
        'archivo_local_path': archivoLocalPath,
        'archivo_nombre': archivoNombre,
        'archivo_tipo': archivoTipo,
        'archivo_size': archivoSize,
        'entidad_plantel_id': entidadPlantelId,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
        'sync_estado': 'PENDIENTE', // Marcar como pendiente de sincronización
      }, where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.actualizar',
          error: e,
          stackTrace: st,
          payload: {'id': id});
      rethrow;
    }
  }

  /// Eliminación lógica de un movimiento (no se borra físicamente)
  Future<void> eliminar(int id) async {
    try {
      final db = await AppDatabase.instance();
      await db.update('evento_movimiento', {
        'eliminado': 1,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
        'sync_estado': 'PENDIENTE',
      }, where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.eliminar',
          error: e,
          stackTrace: st,
          payload: {'id': id});
      rethrow;
    }
  }

  Future<void> actualizarSyncEstado({
    required int id,
    required String syncEstado,
  }) async {
    try {
      final db = await AppDatabase.instance();
      await db.update('evento_movimiento', {
        'sync_estado': syncEstado.toUpperCase(),
      }, where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'evento_mov.sync_estado',
          error: e,
          stackTrace: st,
          payload: {'id': id, 'syncEstado': syncEstado});
      rethrow;
    }
  }

  /// Calcula el saldo de arrastre hasta una fecha determinada
  /// (saldo acumulado desde el inicio hasta el último día del mes anterior)
  Future<double> calcularSaldoArrastre({
    required int disciplinaId,
    required DateTime hastaFecha,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Calcular primer día del mes de hastaFecha
      final primerDiaMes = DateTime(hastaFecha.year, hastaFecha.month, 1);
      final tsHasta = primerDiaMes.millisecondsSinceEpoch;
      
      // Sumar ingresos y egresos hasta el mes anterior
      final query = '''
        SELECT 
          SUM(CASE WHEN tipo = 'INGRESO' THEN monto ELSE 0 END) as total_ingresos,
          SUM(CASE WHEN tipo = 'EGRESO' THEN monto ELSE 0 END) as total_egresos
        FROM evento_movimiento
        WHERE disciplina_id = ?
          AND created_ts < ?
          AND eliminado = 0
      ''';
      
      final result = await db.rawQuery(query, [disciplinaId, tsHasta]);
      
      if (result.isEmpty) return 0.0;
      
      final ingresos = (result.first['total_ingresos'] as num?)?.toDouble() ?? 0.0;
      final egresos = (result.first['total_egresos'] as num?)?.toDouble() ?? 0.0;
      
      return ingresos - egresos;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'evento_movimiento.calcularSaldoArrastre',
        error: e,
        stackTrace: st,
        payload: {
          'disciplinaId': disciplinaId,
          'hastaFecha': hastaFecha.toIso8601String(),
        },
      );
      return 0.0; // En caso de error, retornar 0
    }
  }
}
