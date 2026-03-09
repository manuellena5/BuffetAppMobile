import '../database/app_database.dart';

/// DAO para saldos iniciales por unidad de gestión y período.
class TesoreriaDao {
  static Future<int> insertSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
    required double monto,
    String? observacion,
  }) async {
    final db = await AppDatabase.instance();
    return await db.insert('saldos_iniciales', {
      'unidad_gestion_id': unidadGestionId,
      'periodo_tipo': periodoTipo,
      'periodo_valor': periodoValor,
      'monto': monto,
      'observacion': observacion,
      'fecha_carga': AppDatabase.nowUtcSqlString(),
    });
  }

  static Future<Map<String, dynamic>?> obtenerSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final db = await AppDatabase.instance();
    final result = await db.query('saldos_iniciales',
        where: 'unidad_gestion_id = ? AND periodo_tipo = ? AND periodo_valor = ?',
        whereArgs: [unidadGestionId, periodoTipo, periodoValor],
        limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  static Future<bool> existeSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final db = await AppDatabase.instance();
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM saldos_iniciales WHERE unidad_gestion_id = ? AND periodo_tipo = ? AND periodo_valor = ?',
        [unidadGestionId, periodoTipo, periodoValor]);
    final count = result.first['count'] as int? ?? 0;
    return count > 0;
  }

  static Future<List<Map<String, dynamic>>> listarSaldosIniciales({int? unidadGestionId}) async {
    final db = await AppDatabase.instance();
    if (unidadGestionId != null) {
      return await db.query('saldos_iniciales',
          where: 'unidad_gestion_id = ?', whereArgs: [unidadGestionId], orderBy: 'periodo_valor DESC');
    }
    return await db.query('saldos_iniciales', orderBy: 'unidad_gestion_id, periodo_valor DESC');
  }

  static Future<int> actualizarSaldoInicial({
    required int id,
    required double monto,
    String? observacion,
  }) async {
    final db = await AppDatabase.instance();
    return await db.update('saldos_iniciales', {'monto': monto, 'observacion': observacion},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> eliminarSaldoInicial(int id) async {
    final db = await AppDatabase.instance();
    return await db.delete('saldos_iniciales', where: 'id = ?', whereArgs: [id]);
  }
}
