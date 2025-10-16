import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../data/dao/db.dart';

class SyncService {
  final _uuid = const Uuid();

  Future<File> exportVentasDelDia(
      {required String deviceAlias, required String fecha}) async {
    final db = await AppDatabase.instance();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ventas_${fecha}_$deviceAlias.json');
    // Totales por mp
    final totRows = await db.rawQuery(
        'SELECT metodo_pago_id, SUM(total_venta) as total FROM ventas WHERE fecha_hora LIKE ? AND activo=1 GROUP BY metodo_pago_id',
        ['$fecha%']);
    final ventas = await db
        .query('ventas', where: 'fecha_hora LIKE ?', whereArgs: ['$fecha%']);
    final items = <Map<String, dynamic>>[];
    for (final v in ventas) {
      final its = await db
          .query('venta_items', where: 'venta_id=?', whereArgs: [v['id']]);
      items.addAll(its);
    }
    final payload = {
      'device_id': await _ensureDeviceId(),
      'device_alias': deviceAlias,
      'fecha': fecha,
      'ventas': ventas,
      'items': items,
      'totales_por_mp': totRows,
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file;
  }

  Future<void> importarCatalogo(File jsonFile) async {
    final db = await AppDatabase.instance();
    final data =
        json.decode(await jsonFile.readAsString()) as Map<String, dynamic>;
    final batch = db.batch();
    for (final c in (data['categorias'] as List)) {
      batch.insert('Categoria_Producto',
          {'id': c['id'], 'descripcion': c['descripcion']},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final mp in (data['metodos_pago'] as List)) {
      batch.insert(
          'metodos_pago', {'id': mp['id'], 'descripcion': mp['descripcion']},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final p in (data['productos'] as List)) {
      batch.insert(
          'products',
          {
            'id': p['id'],
            'codigo_producto': p['codigo_producto'],
            'nombre': p['nombre'],
            'precio_compra': p['precio_compra'],
            'precio_venta': p['precio_venta'],
            'stock_actual': p['stock_actual'] ?? 0,
            'stock_minimo': p['stock_minimo'] ?? 3,
            'categoria_id': p['categoria_id'],
            'visible': p['visible'] ?? 1,
            'color': p['color']
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<String> _ensureDeviceId() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/device_id');
    if (await f.exists()) return (await f.readAsString()).trim();
    final id = _uuid.v4();
    await f.writeAsString(id);
    return id;
  }
}
