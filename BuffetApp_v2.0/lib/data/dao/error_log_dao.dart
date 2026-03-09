import '../database/app_database.dart';

/// DAO para el log de errores local (tabla app_error_log).
/// 
/// Para registrar un error, usar [AppDatabase.logLocalError] directamente
/// (está disponible en AppDatabase para evitar dependencia circular).
/// Este DAO expone las operaciones de lectura y limpieza.
class ErrorLogDao {
  /// Devuelve los últimos [limit] errores almacenados localmente.
  static Future<List<Map<String, dynamic>>> ultimosErrores({int limit = 50}) async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.query('app_error_log', orderBy: 'id DESC', limit: limit);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'app_error_log.read', error: e, stackTrace: st);
      return const [];
    }
  }

  /// Borra todos los registros del log de errores local.
  static Future<int> clearErrorLogs() async {
    try {
      final db = await AppDatabase.instance();
      return await db.delete('app_error_log');
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'app_error_log.clear', error: e, stackTrace: st);
      return 0;
    }
  }

  /// Elimina logs antiguos (política de retención).
  static Future<Map<String, int>> purgeOldErrorLogs({int months = 6}) async {
    final result = <String, int>{
      'app_error_log': 0,
      'sync_error_log': 0,
      'sync_outbox_error': 0,
    };

    if (months <= 0) return result;

    String toSqlString(DateTime d) {
      String two(int v) => v.toString().padLeft(2, '0');
      return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }

    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - months, now.day, now.hour, now.minute, now.second);
      final cutoffStr = toSqlString(cutoff);
      final cutoffMs = cutoff.millisecondsSinceEpoch;

      await db.transaction((txn) async {
        result['app_error_log'] = await txn.delete('app_error_log', where: 'created_ts < ?', whereArgs: [cutoffStr]);
        result['sync_error_log'] = await txn.delete('sync_error_log', where: 'created_ts < ?', whereArgs: [cutoffStr]);
        result['sync_outbox_error'] = await txn.delete('sync_outbox', where: 'tipo=? AND created_ts < ?', whereArgs: ['error', cutoffMs]);
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'db.purgeOldErrorLogs', error: e, stackTrace: st, payload: {'months': months});
    }

    return result;
  }
}
