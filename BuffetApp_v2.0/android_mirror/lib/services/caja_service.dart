import '../data/dao/db.dart';
import 'supabase_sync_service.dart';

class CajaService {
  Future<List<Map<String, dynamic>>> listarPuntosVenta() async {
    try {
      final db = await AppDatabase.instance();
      final r = await db.query('punto_venta', orderBy: 'codigo ASC');
      return r.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.listarPV', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<List<String>> listarDisciplinas() async {
    try {
      final db = await AppDatabase.instance();
      final r = await db.query('disciplinas', columns: ['nombre'], orderBy: 'nombre ASC');
      return r.map((e) => (e['nombre'] as String)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.listarDisciplinas', error: e, stackTrace: st);
      rethrow;
    }
  }
  Future<Map<String, dynamic>?> getCajaAbierta() async {
    try {
      final db = await AppDatabase.instance();
      final r =
          await db.query('caja_diaria', where: "estado = 'ABIERTA'", limit: 1);
      return r.isNotEmpty ? r.first : null;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.getAbierta', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<int> abrirCaja(
    {required String usuario,
      required double fondoInicial,
      required String disciplina,
      required String descripcionEvento,
      String? observacion,
      required String puntoVentaCodigo}) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now();
      final fecha =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hora =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      String discCode = 'OTRO';
      if (disciplina.toLowerCase().contains('infantil')) {
        discCode = 'FUTI';
      } else if (disciplina.toLowerCase().contains('mayor')) {
        discCode = 'FUTM';
      } else if (disciplina.toLowerCase().contains('evento')) {
        discCode = 'EVEN';
      }
      final fechaCompact = fecha.replaceAll('-', '');
      final baseCodigo = '$puntoVentaCodigo-$fechaCompact-$discCode';
      // Generar código único: si existe el base, agregar sufijo -2, -3, ...
      String codigo = baseCodigo;
      final existentes = await db.query(
        'caja_diaria',
        columns: ['codigo_caja'],
        where: 'codigo_caja LIKE ?',
        whereArgs: ['$baseCodigo%'],
      );
      if (existentes.isNotEmpty) {
        int maxSufijo = 1; // 1 implica que existe el base sin sufijo
        for (final row in existentes) {
          final cc = (row['codigo_caja'] as String?) ?? '';
          if (cc == baseCodigo) {
            if (maxSufijo < 1) maxSufijo = 1;
            continue;
          }
          if (cc.startsWith('$baseCodigo-')) {
            final parts = cc.split('-');
            final last = parts.isNotEmpty ? parts.last : '';
            final n = int.tryParse(last);
            if (n != null && n > maxSufijo) {
              maxSufijo = n;
            }
          }
        }
        // si encontramos el base usado (maxSufijo>=1), proponer el siguiente entero
        if (maxSufijo >= 1) {
          codigo = '$baseCodigo-${maxSufijo + 1}';
        }
      }
      final newId = await db.insert('caja_diaria', {
        'codigo_caja': codigo,
        'disciplina': disciplina,
        'fecha': fecha,
        // Guardar usuario clásico como 'admin' por defecto
        'usuario_apertura': 'admin',
        // Nuevo campo cajero_apertura
        'cajero_apertura': usuario,
        'hora_apertura': hora,
        'apertura_dt': '$fecha $hora',
        'fondo_inicial': fondoInicial,
        'estado': 'ABIERTA',
        'descripcion_evento': descripcionEvento,
        'observaciones_apertura': (observacion ?? ''),
        'diferencia': 0,
        // Nota: columnas esperadas en Supabase -> 'ingresos' y 'retiros'
        'ingresos': 0,
        'retiros': 0,
        'total_tickets': 0,
        'tickets_anulados': 0,
        'entradas': null,
      });
      // Encolar apertura para sync (idempotente por codigo_caja)
      await SupaSyncService.I.enqueueCaja({
        'codigo_caja': codigo,
        'caja_local_id': newId,
        'disciplina': disciplina,
        'fecha_apertura': '$fecha $hora',
        'usuario_apertura': 'admin',
        'cajero_apertura': usuario,
        'fondo_inicial': fondoInicial,
        'ingresos': 0,
        'retiros': 0,
        'total_efectivo_teorico': fondoInicial, // ventas en efectivo = 0 al abrir
        'estado': 'ABIERTA',
        'descripcion_evento': descripcionEvento,
        'observaciones_apertura': (observacion ?? ''),
        'tickets': 0,
        'tickets_anulados': 0,
      });
      return newId;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'caja.abrir',
        error: e,
        stackTrace: st,
        payload: {
          'usuario': usuario,
          'fondoInicial': fondoInicial,
          'disciplina': disciplina,
          'puntoVenta': puntoVentaCodigo,
        },
      );
      rethrow;
    }
  }

  Future<void> cerrarCaja(
      {required int cajaId,
      required double efectivoEnCaja,
      required double transferencias,
    required String usuarioCierre,
      String? observacion,
      int? entradas}) async {
    try {
      // Asegurar columna de efectivo declarado si la DB venía de una versión previa
      await AppDatabase.ensureCajaDiariaColumn('conteo_efectivo_final', 'conteo_efectivo_final REAL');
      final db = await AppDatabase.instance();
      final now = DateTime.now();
      final hora =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      // calcular diferencia: (efectivo + transferencias) - totalVentasSistema (excluyendo tickets anulados)
      final tot = await db.rawQuery('''
      SELECT COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
    ''', [cajaId]);
      final totalVentas = (tot.first['total'] as num?)?.toDouble() ?? 0.0;
      // Ventas por efectivo (para total_efectivo_teorico)
      final tef = await db.rawQuery('''
      SELECT COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      JOIN metodos_pago m ON m.id = v.metodo_pago_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado' AND LOWER(m.descripcion) = 'efectivo'
    ''', [cajaId]);
      final totalEfectivoVentas = (tef.first['total'] as num?)?.toDouble() ?? 0.0;
      // Tickets emitidos (sin contar anulados)
      final tk = await db.rawQuery('''
      SELECT COALESCE(COUNT(1),0) as c
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
    ''', [cajaId]);
      final totalTicketsEmitidos = (tk.first['c'] as num?)?.toInt() ?? 0;
      // Fórmula ajustada (incluye ingresos/retiros):
      // Diferencia = ((Efectivo - Fondo - Ingresos + Retiros) + Transferencias) - TotalVentas
      final cajaRow = await db.query('caja_diaria', columns: ['fondo_inicial','codigo_caja','fecha','apertura_dt','disciplina','descripcion_evento','observaciones_apertura'], where: 'id=?', whereArgs: [cajaId], limit: 1);
      final fondo = ((cajaRow.first['fondo_inicial'] as num?) ?? 0).toDouble();
      // Obtener totales de movimientos para aplicar fórmula ajustada
      final movTotals = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN tipo='INGRESO' THEN monto END),0) as ingresos,
        COALESCE(SUM(CASE WHEN tipo='RETIRO' THEN monto END),0) as retiros
      FROM caja_movimiento
      WHERE caja_id = ?
    ''', [cajaId]);
      final ingresos = (movTotals.first['ingresos'] as num?)?.toDouble() ?? 0.0;
      final retiros = (movTotals.first['retiros'] as num?)?.toDouble() ?? 0.0;
      final totalPorFormula = (efectivoEnCaja - fondo - ingresos + retiros) + transferencias;
      final diferencia = totalPorFormula - totalVentas;
      await db.update(
        'caja_diaria',
        {
          'estado': 'CERRADA',
          'hora_cierre': hora,
          'cierre_dt': '${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}',
          'usuario_cierre': 'admin',
          'cajero_cierre': usuarioCierre,
          'obs_cierre': observacion,
          'conteo_efectivo_final': efectivoEnCaja,
          'diferencia': diferencia,
          'entradas': entradas,
          'total_tickets': totalTicketsEmitidos,
          // contar anulados aparte
          'tickets_anulados': (await db.rawQuery('''
            SELECT COALESCE(COUNT(1),0) as c
            FROM tickets t
            JOIN ventas v ON v.id = t.venta_id
            WHERE v.caja_id = ? AND t.status = 'Anulado'
          ''', [cajaId])).first['c'] ?? 0,
        },
        where: 'id=?',
        whereArgs: [cajaId]);
    // Encolar cierre (incluye totales y diferencia)
      final codigo = (cajaRow.first['codigo_caja'] as String?) ?? '';
      await SupaSyncService.I.enqueueCaja({
      'codigo_caja': codigo,
      'caja_local_id': cajaId,
      'disciplina': cajaRow.first['disciplina'],
      'descripcion_evento': cajaRow.first['descripcion_evento'],
      'fondo_inicial': fondo,
      'fecha_apertura': (cajaRow.first['apertura_dt'] ?? cajaRow.first['fecha'])?.toString(),
      'usuario_apertura': 'admin',
      'cajero_apertura': cajaRow.first['cajero_apertura'],
      'observaciones_apertura': cajaRow.first['observaciones_apertura'],
      'fecha_cierre': '${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}',
      'usuario_cierre': 'admin',
      'cajero_cierre': usuarioCierre,
      'conteo_efectivo_final': efectivoEnCaja,
      'transferencias_final': transferencias,
      'total_ventas': totalVentas,
      'total_efectivo_teorico': fondo + totalEfectivoVentas,
  // En Supabase los totales de movimientos se guardan en 'ingresos' y 'retiros'
      'ingresos': ingresos,
      'retiros': retiros,
      'tickets': totalTicketsEmitidos,
      'tickets_anulados': (await db.rawQuery('''
        SELECT COALESCE(COUNT(1),0) as c
        FROM tickets t
        JOIN ventas v ON v.id = t.venta_id
        WHERE v.caja_id = ? AND t.status = 'Anulado'
      ''', [cajaId])).first['c'] ?? 0,
      'diferencia': diferencia,
      'estado': 'CERRADA',
      'obs_cierre': observacion,
      'entradas': entradas,
    });
    // Sync manual por demanda: no forzar aquí
    // Se podría registrar un movimiento resumen si hiciera falta; por ahora solo cerramos estado
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'caja.cerrar',
        error: e,
        stackTrace: st,
        payload: {
          'cajaId': cajaId,
          'efectivo': efectivoEnCaja,
          'transfer': transferencias,
          'usuarioCierre': usuarioCierre,
        },
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resumenCaja(int cajaId) async {
    try {
      final db = await AppDatabase.instance();
      final totalPorMp = await db.rawQuery('''
      SELECT v.metodo_pago_id as mp, m.descripcion as mp_desc, COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN metodos_pago m ON m.id = v.metodo_pago_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY v.metodo_pago_id
    ''', [cajaId]);
      final ticketsCont = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN t.status = 'Anulado' THEN 1 ELSE 0 END),0) as anulados,
        COALESCE(SUM(CASE WHEN t.status <> 'Anulado' THEN 1 ELSE 0 END),0) as emitidos
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ?
    ''', [cajaId]);
      final ventasPorProducto = await db.rawQuery('''
      SELECT COALESCE(p.nombre,'(Sin nombre)') AS nombre,
             COUNT(t.id) as cantidad,
             COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY p.id
      ORDER BY cantidad DESC
    ''', [cajaId]);
      final totales = await db.rawQuery('''
      SELECT COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
    ''', [cajaId]);
      return {
        'total': totales.first['total'] ?? 0,
        'por_mp': totalPorMp,
        'tickets': ticketsCont.isNotEmpty
            ? ticketsCont.first
            : {'anulados': 0, 'emitidos': 0},
        'por_producto': ventasPorProducto,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.resumen', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listarCajas({bool incluirOcultas = false}) async {
    try {
      final db = await AppDatabase.instance();
      // Asegurar columna visible si fuese una BD antigua
      await AppDatabase.ensureCajaDiariaColumn('visible', 'visible INTEGER NOT NULL DEFAULT 1');
      final r = await db.query(
        'caja_diaria',
        columns: [
          'id',
          'codigo_caja',
          'fecha',
          'observaciones_apertura',
          'estado',
          'apertura_dt',
          'visible'
        ],
        where: incluirOcultas ? null : 'COALESCE(visible,1)=1',
        orderBy: 'apertura_dt DESC, id DESC',
      );
      return r.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.listar', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getCajaById(int id) async {
    try {
      final db = await AppDatabase.instance();
      await AppDatabase.ensureCajaDiariaColumn('visible', 'visible INTEGER NOT NULL DEFAULT 1');
      final r = await db.query('caja_diaria', where: 'id=?', whereArgs: [id], limit: 1);
      return r.isNotEmpty ? r.first : null;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.getById', error: e, stackTrace: st, payload: {'id': id});
      rethrow;
    }
  }

  Future<void> setCajaVisible(int id, bool visible) async {
    try {
      final db = await AppDatabase.instance();
      await AppDatabase.ensureCajaDiariaColumn('visible', 'visible INTEGER NOT NULL DEFAULT 1');
      await db.update('caja_diaria', {'visible': visible ? 1 : 0, 'updated_ts': DateTime.now().millisecondsSinceEpoch}, where: 'id=?', whereArgs: [id]);
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'caja.setVisible', error: e, stackTrace: st, payload: {'id': id, 'visible': visible});
      rethrow;
    }
  }
}
