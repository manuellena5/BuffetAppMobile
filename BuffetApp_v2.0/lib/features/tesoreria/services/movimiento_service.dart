import 'package:sqflite/sqflite.dart';
import '../../../data/dao/db.dart';
import '../../../domain/paginated_result.dart';

class MovimientoService {
  Future<List<Map<String, dynamic>>> listarPorCaja(int cajaId) async {
    try {
      final db = await AppDatabase.instance();
    final rows = await db.query('caja_movimiento',
      where: 'caja_id=?', whereArgs: [cajaId], orderBy: 'created_ts DESC');
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.listar', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<int> crear({required int cajaId, required String tipo, required double monto, String? observacion}) async {
    try {
      final db = await AppDatabase.instance();
      return await db.insert('caja_movimiento', {
        'caja_id': cajaId,
        'tipo': tipo.toUpperCase(),
        'monto': monto,
        'observacion': observacion,
  // created_ts usa DEFAULT CURRENT_TIMESTAMP
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.crear', error: e, stackTrace: st, payload: {'cajaId': cajaId,'tipo': tipo,'monto': monto});
      rethrow;
    }
  }

  Future<void> actualizar({required int id, required String tipo, required double monto, String? observacion}) async {
    try {
      final db = await AppDatabase.instance();
      await db.update('caja_movimiento', {
        'tipo': tipo.toUpperCase(),
        'monto': monto,
        'observacion': observacion,
      }, where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'mov.actualizar', error: e, stackTrace: st, payload: {'id': id,'tipo': tipo,'monto': monto});
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
}

class EventoMovimientoService {
  Future<int> crear({
    required int disciplinaId,
    String? eventoId,
    required String tipo,
    String? categoria,
    required double monto,
    required int medioPagoId,
    String? observacion,
    String? dispositivoId,
    int? compromisoId,
    String? estado,
    String? archivoLocalPath,
    String? archivoNombre,
  }) async {
    try {
      final db = await AppDatabase.instance();
      return await db.insert('evento_movimiento', {
        'evento_id': eventoId,
        'disciplina_id': disciplinaId,
        'tipo': tipo.toUpperCase(),
        'categoria': categoria,
        'monto': monto,
        'medio_pago_id': medioPagoId,
        'observacion': observacion,
        'dispositivo_id': dispositivoId,
        'compromiso_id': compromisoId,
        'estado': estado ?? 'CONFIRMADO',
        'archivo_local_path': archivoLocalPath,
        'archivo_nombre': archivoNombre,
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
            'compromisoId': compromisoId,
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
          mp.descripcion as medio_pago_desc
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
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
  }) async {
    try {
      final db = await AppDatabase.instance();
      final where = <String>[];
      final args = <Object?>[];
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
          mp.descripcion as medio_pago_desc
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
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
          mp.descripcion as medio_pago_desc
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
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
    String? eventoId,
    required String tipo,
    String? categoria,
    required double monto,
    required int medioPagoId,
    String? observacion,
  }) async {
    try {
      final db = await AppDatabase.instance();
      await db.update('evento_movimiento', {
        'evento_id': eventoId,
        'disciplina_id': disciplinaId,
        'tipo': tipo.toUpperCase(),
        'categoria': categoria,
        'monto': monto,
        'medio_pago_id': medioPagoId,
        'observacion': observacion,
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

  /// FASE 31: Obtener movimientos con paginación
  /// 
  /// [unidadGestionId] - ID de la unidad de gestión (obligatorio)
  /// [page] - Número de página (base 1, default: 1)
  /// [pageSize] - Items por página (default: 50)
  /// [tipo] - Filtro opcional por tipo (INGRESO/EGRESO)
  /// [cuentaId] - Filtro opcional por cuenta
  /// [desde] - Fecha desde (opcional)
  /// [hasta] - Fecha hasta (opcional)
  /// [searchText] - Búsqueda en observaciones/categoría (opcional)
  Future<PaginatedResult<Map<String, dynamic>>> getMovimientosPaginados({
    required int unidadGestionId,
    int page = 1,
    int pageSize = 50,
    String? tipo,
    int? cuentaId,
    DateTime? desde,
    DateTime? hasta,
    String? searchText,
  }) async {
    try {
      final db = await AppDatabase.instance();

      // Construir WHERE clause
      final whereConditions = <String>['em.unidad_gestion_id = ?'];
      final whereArgs = <dynamic>[unidadGestionId];

      if (tipo != null && tipo.isNotEmpty) {
        whereConditions.add('em.tipo = ?');
        whereArgs.add(tipo);
      }

      if (cuentaId != null) {
        whereConditions.add('em.cuenta_id = ?');
        whereArgs.add(cuentaId);
      }

      if (desde != null) {
        whereConditions.add('em.fecha >= ?');
        whereArgs.add(desde.toIso8601String().substring(0, 10));
      }

      if (hasta != null) {
        whereConditions.add('em.fecha <= ?');
        whereArgs.add(hasta.toIso8601String().substring(0, 10));
      }

      if (searchText != null && searchText.isNotEmpty) {
        whereConditions.add('(em.observacion LIKE ? OR em.categoria LIKE ?)');
        final searchPattern = '%$searchText%';
        whereArgs.add(searchPattern);
        whereArgs.add(searchPattern);
      }

      final whereClause = whereConditions.join(' AND ');

      // Contar total de registros
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM evento_movimiento em WHERE $whereClause',
        whereArgs,
      );
      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

      if (totalCount == 0) {
        return PaginatedResult.empty();
      }

      // Obtener items de la página actual con JOINs
      final offset = (page - 1) * pageSize;
      final query = '''
        SELECT 
          em.*,
          mp.descripcion as medio_pago_desc,
          c.nombre as cuenta_nombre
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
        LEFT JOIN cuentas c ON c.id = em.cuenta_id
        WHERE $whereClause
        ORDER BY em.fecha DESC, em.created_ts DESC
        LIMIT ? OFFSET ?
      ''';

      final items = await db.rawQuery(
        query,
        [...whereArgs, pageSize, offset],
      );

      final movimientos = items.map((row) => Map<String, dynamic>.from(row)).toList();

      return PaginatedResult<Map<String, dynamic>>(
        items: movimientos,
        totalCount: totalCount,
        pageSize: pageSize,
        currentPage: page,
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_mov.get_paginados',
        error: e.toString(),
        stackTrace: stack,
        payload: {
          'unidad_gestion_id': unidadGestionId,
          'page': page,
          'page_size': pageSize,
        },
      );
      return PaginatedResult.empty();
    }
  }
}
