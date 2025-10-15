import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../data/dao/db.dart';
import 'caja_service.dart';

class ExportService {
  final _df = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  Future<Directory> _ensureExportDir() async {
    final dir = await getExternalStorageDirectory();
    final exportDir = Directory(p.join(dir!.path, 'exports'));
    if (!await exportDir.exists()) await exportDir.create(recursive: true);
    return exportDir;
  }

  Future<Map<String, dynamic>> _buildPayload(Database db, int cajaId) async {
    final caja = await db.query('caja_diaria', where: 'id=?', whereArgs: [cajaId], limit: 1);
    if (caja.isEmpty) { throw Exception('Caja no encontrada'); }

    final resumen = await CajaService().resumenCaja(cajaId);
    // Tickets completos (incluye anulados)
    final tickets = await db.rawQuery('''
      SELECT t.id, t.identificador_ticket, t.status, t.total_ticket, t.fecha_hora,
             p.id AS producto_id, p.codigo_producto, p.nombre AS producto_nombre,
             v.metodo_pago_id, mp.descripcion AS metodo_pago_desc
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      WHERE v.caja_id = ?
      ORDER BY t.id ASC
    ''', [cajaId]);

    // Ventas por producto (no anulados)
    final ventasPorProducto = await db.rawQuery('''
      SELECT p.id AS producto_id, p.codigo_producto, p.nombre AS producto_nombre,
             COUNT(*) AS cantidad, SUM(t.total_ticket) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      WHERE v.caja_id = ? AND t.status <> 'Anulado'
      GROUP BY p.id, p.codigo_producto, p.nombre
      ORDER BY cantidad DESC
    ''', [cajaId]);

    // Catálogo base (código, descripción, categoría)
    final catalogo = await db.rawQuery('''
      SELECT p.id, p.codigo_producto, p.nombre, c.descripcion AS categoria
      FROM products p
      LEFT JOIN Categoria_Producto c ON c.id = p.categoria_id
      WHERE p.visible = 1
      ORDER BY p.id ASC
    ''');

    // Metadatos mínimos; device_id/alias quedan como TODO si no hay persistencia aún
    final nowIso = _df.format(DateTime.now());
    final metadata = {
      'app': 'BuffetMirror',
      'app_version': '0.1.0',
      'device_id': 'unknown', // TODO: persistir con uuid en storage y leerlo aquí
      'device_alias': 'device', // TODO: permitir alias editable y persistido
      'fecha_export': nowIso,
    };

    return {
      'metadata': metadata,
      'caja': caja.first,
      'resumen': resumen,
      'totales_por_mp': resumen['por_mp'],
      'tickets': tickets,
      'ventas_por_producto': ventasPorProducto,
      'catalogo': catalogo,
    };
  }

  Future<File> exportCajaToJson(int cajaId) async {
    final exportDir = await _ensureExportDir();
  final db = await AppDatabase.instance();
  final payload = await _buildPayload(db, cajaId);
    final codigo = (payload['caja'] as Map)['codigo_caja']?.toString() ?? 'CAJA';
    final file = File(p.join(exportDir.path, 'caja_${codigo}.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload), flush: true);
    await _pruneOldBackups(exportDir);
    return file;
  }

  Future<void> shareCajaFile(int cajaId) async {
    final file = await exportCajaToJson(cajaId);
    await Share.shareXFiles([XFile(file.path)], subject: 'Caja ${p.basename(file.path)}');
  }

  Future<void> _pruneOldBackups(Directory exportDir) async {
    // Mantener sólo las últimas 4 cajas por fecha de modificación
    final files = (await exportDir.list().toList())
        .whereType<File>()
        .where((f) => p.basename(f.path).toLowerCase().endsWith('.json'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (int i = 4; i < files.length; i++) {
      try { await files[i].delete(); } catch (_) {}
    }
  }
}
