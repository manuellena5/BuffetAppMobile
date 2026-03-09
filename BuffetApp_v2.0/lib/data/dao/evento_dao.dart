import '../database/app_database.dart';

/// DAO para el módulo Eventos CDM.
/// Gestiona las tablas `eventos` y `evento_asistencia`.
/// Opera con Maps raw, consistente con el resto del proyecto.
class EventoDao {
  // ─── EVENTOS ────────────────────────────────────────────────────────────────

  /// Devuelve todos los eventos de una unidad en un mes dado (YYYY-MM),
  /// incluyendo totales de ingresos y egresos calculados desde evento_movimiento.
  static Future<List<Map<String, dynamic>>> getEventosByMes(
    int unidadGestionId,
    String anioMes, // formato 'YYYY-MM'
  ) async {
    try {
      final db = await AppDatabase.instance();
      return await db.rawQuery('''
        SELECT
          e.*,
          COALESCE(SUM(CASE WHEN em.tipo = 'INGRESO' AND (em.eliminado = 0 OR em.eliminado IS NULL) THEN em.monto ELSE 0 END), 0) AS total_ingresos,
          COALESCE(SUM(CASE WHEN em.tipo = 'EGRESO'  AND (em.eliminado = 0 OR em.eliminado IS NULL) THEN em.monto ELSE 0 END), 0) AS total_egresos
        FROM eventos e
        LEFT JOIN evento_movimiento em ON em.evento_cdm_id = e.id
        WHERE e.unidad_gestion_id = ? AND e.fecha LIKE ? AND e.eliminado = 0
        GROUP BY e.id
        ORDER BY e.fecha ASC
      ''', [unidadGestionId, '$anioMes%']);
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.get_by_mes',
        error: e.toString(),
        stackTrace: stack,
        payload: {'unidad_gestion_id': unidadGestionId, 'mes': anioMes},
      );
      rethrow;
    }
  }

  /// Devuelve todos los eventos de una unidad, sin filtro de mes.
  static Future<List<Map<String, dynamic>>> getEventosByUnidad(
    int unidadGestionId, {
    String? tipo, // 'PARTIDO' | 'CENA' | 'TORNEO' | 'OTRO'
    String? estado,
  }) async {
    try {
      final db = await AppDatabase.instance();
      final where = <String>['unidad_gestion_id = ?', 'eliminado = 0'];
      final whereArgs = <dynamic>[unidadGestionId];

      if (tipo != null) {
        where.add('tipo = ?');
        whereArgs.add(tipo);
      }
      if (estado != null) {
        where.add('estado = ?');
        whereArgs.add(estado);
      }

      return await db.query(
        'eventos',
        where: where.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'fecha DESC',
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.get_by_unidad',
        error: e.toString(),
        stackTrace: stack,
        payload: {'unidad_gestion_id': unidadGestionId},
      );
      rethrow;
    }
  }

  /// Devuelve un único evento por ID.
  static Future<Map<String, dynamic>?> getEventoById(int id) async {
    try {
      final db = await AppDatabase.instance();
      final result = await db.query(
        'eventos',
        where: 'id = ? AND eliminado = 0',
        whereArgs: [id],
      );
      return result.isNotEmpty ? result.first : null;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.get_by_id',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Inserta un evento nuevo. Retorna el id generado.
  static Future<int> insertEvento(Map<String, dynamic> data) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final row = Map<String, dynamic>.from(data);
      row['eliminado'] ??= 0;
      row['sync_estado'] ??= 'PENDIENTE';
      row['created_ts'] ??= now;
      row['updated_ts'] ??= now;

      final id = await db.insert('eventos', row);

      // Encolar en sync_outbox
      await _enqueueSyncOutbox(db, 'EVENTO', id.toString());

      return id;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.insert',
        error: e.toString(),
        stackTrace: stack,
        payload: {'titulo': data['titulo']},
      );
      rethrow;
    }
  }

  /// Actualiza los datos de un evento existente.
  static Future<void> updateEvento(int id, Map<String, dynamic> data) async {
    try {
      final db = await AppDatabase.instance();
      final row = Map<String, dynamic>.from(data);
      row['updated_ts'] = DateTime.now().millisecondsSinceEpoch;
      row['sync_estado'] = 'PENDIENTE';

      await db.update('eventos', row, where: 'id = ?', whereArgs: [id]);
      await _enqueueSyncOutbox(db, 'EVENTO', id.toString());
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.update',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Cambia solo el estado de un evento.
  static Future<void> updateEstadoEvento(int id, String estado) async {
    await updateEvento(id, {'estado': estado});
  }

  /// Soft-delete de un evento.
  static Future<void> softDeleteEvento(int id) async {
    await updateEvento(id, {'eliminado': 1});
  }

  // ─── ASISTENCIA ─────────────────────────────────────────────────────────────

  /// Lista todas las asistencias de un evento con datos del jugador y del acuerdo.
  static Future<List<Map<String, dynamic>>> getAsistenciaByEvento(
      int eventoId) async {
    try {
      final db = await AppDatabase.instance();
      final result = await db.rawQuery('''
        SELECT
          ea.*,
          ep.nombre      AS jugador_nombre,
          ep.posicion    AS jugador_posicion,
          ep.rol         AS jugador_rol,
          a.nombre       AS acuerdo_nombre,
          a.monto_titular,
          a.monto_suplente,
          a.monto_no_jugo
        FROM evento_asistencia ea
        INNER JOIN entidades_plantel ep ON ep.id = ea.entidad_plantel_id
        LEFT  JOIN acuerdos a ON a.id = ea.acuerdo_id
        WHERE ea.evento_id = ?
        ORDER BY ep.nombre ASC
      ''', [eventoId]);
      return result;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.get_asistencia',
        error: e.toString(),
        stackTrace: stack,
        payload: {'evento_id': eventoId},
      );
      rethrow;
    }
  }

  /// INSERT OR REPLACE en evento_asistencia.
  /// Si ya existe el par (evento_id, entidad_plantel_id) lo reemplaza.
  static Future<int> upsertAsistencia(Map<String, dynamic> data) async {
    try {
      final db = await AppDatabase.instance();
      final row = Map<String, dynamic>.from(data);
      row['created_ts'] ??= DateTime.now().millisecondsSinceEpoch;
      row['sync_estado'] ??= 'PENDIENTE';

      return await db.rawInsert('''
        INSERT INTO evento_asistencia
          (evento_id, entidad_plantel_id, acuerdo_id, condicion, monto, movimiento_id, sync_estado, created_ts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(evento_id, entidad_plantel_id)
        DO UPDATE SET
          acuerdo_id   = excluded.acuerdo_id,
          condicion    = excluded.condicion,
          monto        = excluded.monto,
          movimiento_id = excluded.movimiento_id,
          sync_estado  = 'PENDIENTE'
      ''', [
        row['evento_id'],
        row['entidad_plantel_id'],
        row['acuerdo_id'],
        row['condicion'],
        row['monto'] ?? 0,
        row['movimiento_id'],
        row['sync_estado'],
        row['created_ts'],
      ]);
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.upsert_asistencia',
        error: e.toString(),
        stackTrace: stack,
        payload: {
          'evento_id': data['evento_id'],
          'entidad_plantel_id': data['entidad_plantel_id'],
        },
      );
      rethrow;
    }
  }

  /// Actualiza el campo movimiento_id en una asistencia una vez que se generó el pago.
  /// Busca por (evento_id, entidad_plantel_id).
  static Future<void> updateMovimientoIdAsistencia({
    required int eventoId,
    required int entidadPlantelId,
    required int? movimientoId,
  }) async {
    try {
      final db = await AppDatabase.instance();
      await db.update(
        'evento_asistencia',
        {'movimiento_id': movimientoId, 'sync_estado': 'PENDIENTE'},
        where: 'evento_id = ? AND entidad_plantel_id = ?',
        whereArgs: [eventoId, entidadPlantelId],
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.update_movimiento_id_asistencia',
        error: e.toString(),
        stackTrace: stack,
        payload: {
          'evento_id': eventoId,
          'entidad_plantel_id': entidadPlantelId,
          'movimiento_id': movimientoId,
        },
      );
      rethrow;
    }
  }

  // ─── MOVIMIENTOS VINCULADOS ──────────────────────────────────────────────────

  /// Devuelve los movimientos (evento_movimiento) vinculados a un evento CDM.
  static Future<List<Map<String, dynamic>>> getMovimientosByEventoCdm(
      int eventoCdmId) async {
    try {
      final db = await AppDatabase.instance();
      return await db.rawQuery('''
        SELECT
          em.*,
          c.nombre  AS cuenta_nombre,
          mp.descripcion AS medio_pago_desc,
          cm.nombre AS categoria_nombre
        FROM evento_movimiento em
        LEFT JOIN cuentas_fondos       c  ON c.id  = em.cuenta_id
        LEFT JOIN metodos_pago         mp ON mp.id = em.medio_pago_id
        LEFT JOIN categoria_movimiento cm ON cm.codigo = em.categoria
        WHERE em.evento_cdm_id = ? AND (em.eliminado = 0 OR em.eliminado IS NULL)
        ORDER BY em.fecha DESC, em.created_ts DESC
      ''', [eventoCdmId]);
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.get_movimientos_by_evento_cdm',
        error: e.toString(),
        stackTrace: stack,
        payload: {'evento_cdm_id': eventoCdmId},
      );
      rethrow;
    }
  }

  // ─── ACUERDOS POR PARTIDO ────────────────────────────────────────────────────

  /// Devuelve acuerdos activos con es_por_evento=1 de una unidad de gestión,
  /// joined con datos del jugador/técnico.
  static Future<List<Map<String, dynamic>>> getAcuerdosPorPartido(
      int unidadGestionId) async {
    try {
      final db = await AppDatabase.instance();
      return await db.rawQuery('''
        SELECT
          a.*,
          ep.nombre   AS entidad_nombre,
          ep.posicion AS entidad_posicion,
          ep.rol      AS entidad_rol
        FROM acuerdos a
        LEFT JOIN entidades_plantel ep ON ep.id = a.entidad_plantel_id
        WHERE a.es_por_evento = 1
          AND a.activo = 1
          AND a.eliminado = 0
          AND a.unidad_gestion_id = ?
        ORDER BY ep.nombre ASC
      ''', [unidadGestionId]);
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'evento_dao.get_acuerdos_por_partido',
        error: e.toString(),
        stackTrace: stack,
        payload: {'unidad_gestion_id': unidadGestionId},
      );
      rethrow;
    }
  }

  // ─── PRIVADO ─────────────────────────────────────────────────────────────────

  static Future<void> _enqueueSyncOutbox(
      dynamic db, String tipo, String ref) async {
    try {
      await db.rawInsert('''
        INSERT OR IGNORE INTO sync_outbox (tipo, ref, estado, reintentos, created_ts)
        VALUES (?, ?, 'PENDIENTE', 0, ?)
      ''', [tipo, ref, DateTime.now().millisecondsSinceEpoch]);
    } catch (_) {
      // No interrumpir la operación principal si falla el enqueue
    }
  }
}
