import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../data/dao/db.dart';

class SeedService {
  Future<void> ensureSeedData() async {
    final db = await AppDatabase.instance();
    // Seed métodos de pago (upsert)
    await db.insert('metodos_pago', {'id': 1, 'descripcion': 'Efectivo'}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('metodos_pago', {'id': 2, 'descripcion': 'Transferencia'}, conflictAlgorithm: ConflictAlgorithm.replace);

    // Seed catálogo desde assets (upsert siempre para asegurar consistencia con backoffice)
    final raw = await rootBundle.loadString('assets/sync/catalogo_v01.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final batch = db.batch();
    for (final c in (data['categorias'] as List)) {
      batch.insert('Categoria_Producto', {'id': c['id'], 'descripcion': c['descripcion']}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final p in (data['productos'] as List)) {
      batch.insert('products', {
        'id': p['id'],
        'codigo_producto': p['codigo_producto'],
        'nombre': p['nombre'],
        'precio_venta': p['precio_venta'],
        'stock_actual': p['stock_actual'] ?? 0,
        'stock_minimo': p['stock_minimo'] ?? 3,
        'categoria_id': p['categoria_id'],
        'visible': p['visible'] ?? 1,
        'color': p['color']
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
