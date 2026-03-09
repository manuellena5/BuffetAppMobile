import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// DAO para operaciones de Buffet: cajas, purga y backup.
class BuffetDao {
  /// Devuelve cantidad total de cajas existentes.
  static Future<int> countCajas() async {
    try {
      final db = await AppDatabase.instance();
      final v = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(1) FROM caja_diaria')) ?? 0;
      return v;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'db.countCajas', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Purga todas las cajas y datos asociados (ventas, tickets, movimientos).
  static Future<Map<String, int>> purgeCajasYAsociados() async {
    final result = <String, int>{};
    try {
      final db = await AppDatabase.instance();
      await db.transaction((txn) async {
        result['venta_items'] = await txn.delete('venta_items');
        result['tickets'] = await txn.delete('tickets');
        result['caja_movimiento'] = await txn.delete('caja_movimiento');
        result['ventas'] = await txn.delete('ventas');
        result['caja_diaria'] = await txn.delete('caja_diaria');
        result['sync_outbox'] = await txn.delete('sync_outbox',
            where: "tipo IN (?,?,?,?,?)",
            whereArgs: ['venta', 'venta_anulada', 'cierre_caja', 'ticket_anulado', 'venta_item']);
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'db.purgeCajasYAsociados', error: e, stackTrace: st);
      rethrow;
    }
    return result;
  }

  /// Crea backup físico de la DB en el directorio de documentos.
  static Future<String> crearBackupArchivo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = await AppDatabase.dbFilePath();
      final ts = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'backup_cdm_gestion_${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.db';
      final backupPath = p.join(dir.path, name);
      await File(dbPath).copy(backupPath);
      return backupPath;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'db.crearBackupArchivo', error: e, stackTrace: st);
      rethrow;
    }
  }
}
