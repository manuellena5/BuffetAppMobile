import '../data/dao/db.dart';

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
