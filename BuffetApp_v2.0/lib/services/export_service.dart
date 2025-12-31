import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// Public Downloads via third-party plugins removed due to AGP namespace issues.
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../data/dao/db.dart';
import 'caja_service.dart';
import '../app_version.dart';

class ExportService {
  final _df = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  String _csvEscape(String v) {
    final needsQuotes = v.contains(',') || v.contains('\n') || v.contains('"');
    var s = v.replaceAll('"', '""');
    return needsQuotes ? '"$s"' : s;
  }
  String _rowsToCsv(List<List<String>> rows) {
    return rows.map((r) => r.map(_csvEscape).join(',')).join('\n') + '\n';
  }

  Future<Directory> _ensureExportDir() async {
    // Forzar prioridad absoluta a carpeta pública de Descargas
    // Nota: En Android modernos, esta ruta suele ser /storage/emulated/0/Download.
    Directory? base;
    try {
      final dl = Directory('/storage/emulated/0/Download');
      if (await dl.exists()) {
        base = dl; // preferimos SIEMPRE esta
      }
    } catch (_) {
      base = null;
    }
    // Si no existe, intentar con path_provider (puede devolver carpeta privada de app)
    if (base == null) {
      try {
        final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (dirs != null && dirs.isNotEmpty) {
          base = dirs.first;
        } else {
          base = await getExternalStorageDirectory();
        }
      } catch (_) {
        base = null;
      }
    }
    base ??= Directory(p.join((await getApplicationDocumentsDirectory()).path, 'exports'));
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  Future<Map<String, dynamic>> _buildPayload(Database db, int cajaId) async {
    try {
      final caja = await db.query('caja_diaria', where: 'id=?', whereArgs: [cajaId], limit: 1);
      if (caja.isEmpty) throw Exception('Caja no encontrada');

      final resumen = await CajaService().resumenCaja(cajaId);
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

      final catalogo = await db.rawQuery('''
        SELECT p.id, p.codigo_producto, p.nombre, c.descripcion AS categoria
        FROM products p
        LEFT JOIN Categoria_Producto c ON c.id = p.categoria_id
        WHERE p.visible = 1
        ORDER BY p.id ASC
      ''');

      final nowIso = _df.format(DateTime.now());
      final metadata = {
        'app': 'BuffetMirror',
        'app_version': '${AppBuildInfo.version}+${AppBuildInfo.buildNumber}',
        'device_id': 'unknown',
        'device_alias': 'device',
        'fecha_export': nowIso,
      };

      final movimientos = await db.query('caja_movimiento', where: 'caja_id=?', whereArgs: [cajaId], orderBy: 'created_ts ASC');

      return {
        'metadata': metadata,
        'caja': caja.first,
        'resumen': resumen,
        'totales_por_mp': resumen['por_mp'],
        'tickets': tickets,
        'ventas_por_producto': ventasPorProducto,
        'movimientos': movimientos,
        'catalogo': catalogo,
      };
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.buildPayload', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<File> exportCajaToJson(int cajaId) async {
    try {
      final exportDir = await _ensureExportDir();
      final db = await AppDatabase.instance();
      final payload = await _buildPayload(db, cajaId);
      final codigo = (payload['caja'] as Map)['codigo_caja']?.toString() ?? 'CAJA';
      final file = File(p.join(exportDir.path, 'caja_$codigo.json'));
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload), flush: true);
      return file;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.cajaJson', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<void> shareCajaFile(int cajaId) async {
    try {
      final file = await exportCajaToJson(cajaId);
      final base = p.basename(file.path);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Caja $base', title: 'Caja $base'));
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.shareCaja', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<File> exportCajaToCsv(int cajaId, {String? directoryPath}) async {
    try {
      final exportDir = directoryPath != null ? Directory(directoryPath) : await _ensureExportDir();
      final db = await AppDatabase.instance();
      final payload = await _buildPayload(db, cajaId);
      final caja = Map<String, Object?>.from(payload['caja'] as Map);
      final resumen = Map<String, Object?>.from(payload['resumen'] as Map);
      final totalesMp = List<Map<String, Object?>>.from(payload['totales_por_mp'] as List);
      final porProducto = List<Map<String, Object?>>.from(payload['ventas_por_producto'] as List);
      final movimientos = List<Map<String, Object?>>.from(payload['movimientos'] as List);
      final codigo = caja['codigo_caja']?.toString() ?? 'CAJA';

      final headers = [
        'Codigo de caja', 'Estado', 'Fecha', 'Hora apertura', 'Disciplina',
        'Desc Evento', 'Caj Apertura', 'Caj cierre', 'Total Ventas',
        'Fondo Inicial', 'Efectivo declarado en caja', 'Diferencia',
        'Entradas vendidas', 'Tickets emitidos', 'Tickets anulados',
        'Ventas Efectivo', 'Ventas Transferencia', 'Ventas por producto',
        'Ingresos', 'Retiros', 'Ticket promedio'
      ];

      double ventasEfec = 0.0, ventasTransf = 0.0;
      for (final m in totalesMp) {
        final desc = (m['mp_desc'] as String?)?.toLowerCase() ?? '';
        final monto = ((m['total'] as num?) ?? 0).toDouble();
        if (desc.contains('efectivo')) ventasEfec += monto;
        else if (desc.contains('transfer')) ventasTransf += monto;
      }

      final productosConcat = porProducto.map((p) {
        final nom = (p['producto_nombre'] ?? p['nombre'] ?? '').toString();
        final cant = ((p['cantidad'] as num?) ?? 0).toInt();
        final tot = ((p['total'] as num?) ?? 0).toInt();
        return '$nom x $cant = $tot';
      }).join(' ; ');

      double ing = 0.0, ret = 0.0;
      for (final m in movimientos) {
        final tipo = (m['tipo'] ?? '').toString().toUpperCase();
        final monto = ((m['monto'] as num?) ?? 0).toDouble();
        if (tipo == 'INGRESO') ing += monto; else if (tipo == 'RETIRO') ret += monto;
      }

      final avgRows = await db.rawQuery('''
        SELECT AVG(total_venta_no_anulados) AS avg_ticket
        FROM (
          SELECT v.id, SUM(t.total_ticket) AS total_venta_no_anulados
          FROM ventas v
          JOIN tickets t ON t.venta_id = v.id AND t.status <> 'Anulado'
          WHERE v.caja_id = ?
          GROUP BY v.id
        )
      ''', [cajaId]);
      final avgTicket = (avgRows.isNotEmpty && (avgRows.first['avg_ticket'] as num?) != null)
          ? ((avgRows.first['avg_ticket'] as num).toDouble())
          : 0.0;

      final tks = Map<String, Object?>.from(resumen['tickets'] as Map);
      final values = [
        caja['codigo_caja']?.toString() ?? '',
        caja['estado']?.toString() ?? '',
        caja['fecha']?.toString() ?? '',
        caja['hora_apertura']?.toString() ?? '',
        caja['disciplina']?.toString() ?? '',
        caja['descripcion_evento']?.toString() ?? '',
        caja['cajero_apertura']?.toString() ?? '',
        caja['cajero_cierre']?.toString() ?? '',
        (((resumen['total'] as num?) ?? 0)).toString(),
        (((caja['fondo_inicial'] as num?) ?? 0)).toString(),
        (((caja['conteo_efectivo_final'] as num?) ?? 0)).toString(),
        (((caja['diferencia'] as num?) ?? 0)).toString(),
        ((((caja['entradas'] as num?) ?? 0)).toInt()).toString(),
        (((tks['emitidos'] as num?) ?? 0).toInt()).toString(),
        (((tks['anulados'] as num?) ?? 0).toInt()).toString(),
        ventasEfec.toString(),
        ventasTransf.toString(),
        productosConcat,
        ing.toString(),
        ret.toString(),
        avgTicket.toStringAsFixed(2),
      ];

      final csv = _rowsToCsv([headers, values]);
      final file = File(p.join(exportDir.path, 'caja_${codigo}.csv'));
      await file.writeAsString(csv, flush: true);
      return file;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.cajaCsv', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<String> saveCsvToDownloadsViaMediaStore(int cajaId) async {
    try {
      final db = await AppDatabase.instance();
      final payload = await _buildPayload(db, cajaId);
      final caja = Map<String, Object?>.from(payload['caja'] as Map);
      final resumen = Map<String, Object?>.from(payload['resumen'] as Map);
      final totalesMp = List<Map<String, Object?>>.from(payload['totales_por_mp'] as List);
      final porProducto = List<Map<String, Object?>>.from(payload['ventas_por_producto'] as List);
      final movimientos = List<Map<String, Object?>>.from(payload['movimientos'] as List);
      final codigo = caja['codigo_caja']?.toString() ?? 'CAJA';

      final headers = [
        'Codigo de caja', 'Estado', 'Fecha', 'Hora apertura', 'Disciplina',
        'Desc Evento', 'Caj Apertura', 'Caj cierre', 'Total Ventas',
        'Fondo Inicial', 'Efectivo declarado en caja', 'Diferencia',
        'Entradas vendidas', 'Tickets emitidos', 'Tickets anulados',
        'Ventas Efectivo', 'Ventas Transferencia', 'Ventas por producto',
        'Ingresos', 'Retiros', 'Ticket promedio'
      ];

      double ventasEfec = 0.0, ventasTransf = 0.0;
      for (final m in totalesMp) {
        final desc = (m['mp_desc'] as String?)?.toLowerCase() ?? '';
        final monto = ((m['total'] as num?) ?? 0).toDouble();
        if (desc.contains('efectivo')) ventasEfec += monto;
        else if (desc.contains('transfer')) ventasTransf += monto;
      }

      final productosConcat = porProducto.map((p) {
        final nom = (p['producto_nombre'] ?? p['nombre'] ?? '').toString();
        final cant = ((p['cantidad'] as num?) ?? 0).toInt();
        final tot = ((p['total'] as num?) ?? 0).toInt();
        return '$nom x $cant = $tot';
      }).join(' ; ');

      double ing = 0.0, ret = 0.0;
      for (final m in movimientos) {
        final tipo = (m['tipo'] ?? '').toString().toUpperCase();
        final monto = ((m['monto'] as num?) ?? 0).toDouble();
        if (tipo == 'INGRESO') ing += monto; else if (tipo == 'RETIRO') ret += monto;
      }

      final avgRows = await db.rawQuery('''
        SELECT AVG(total_venta_no_anulados) AS avg_ticket
        FROM (
          SELECT v.id, SUM(t.total_ticket) AS total_venta_no_anulados
          FROM ventas v
          JOIN tickets t ON t.venta_id = v.id AND t.status <> 'Anulado'
          WHERE v.caja_id = ?
          GROUP BY v.id
        )
      ''', [cajaId]);
      final avgTicket = (avgRows.isNotEmpty && (avgRows.first['avg_ticket'] as num?) != null)
          ? ((avgRows.first['avg_ticket'] as num).toDouble())
          : 0.0;

      final tks = Map<String, Object?>.from(resumen['tickets'] as Map);
      final values = [
        caja['codigo_caja']?.toString() ?? '',
        caja['estado']?.toString() ?? '',
        caja['fecha']?.toString() ?? '',
        caja['hora_apertura']?.toString() ?? '',
        caja['disciplina']?.toString() ?? '',
        caja['descripcion_evento']?.toString() ?? '',
        caja['cajero_apertura']?.toString() ?? '',
        caja['cajero_cierre']?.toString() ?? '',
        (((resumen['total'] as num?) ?? 0)).toString(),
        (((caja['fondo_inicial'] as num?) ?? 0)).toString(),
        (((caja['conteo_efectivo_final'] as num?) ?? 0)).toString(),
        (((caja['diferencia'] as num?) ?? 0)).toString(),
        ((((caja['entradas'] as num?) ?? 0)).toInt()).toString(),
        (((tks['emitidos'] as num?) ?? 0).toInt()).toString(),
        (((tks['anulados'] as num?) ?? 0).toInt()).toString(),
        ventasEfec.toString(),
        ventasTransf.toString(),
        productosConcat,
        ing.toString(),
        ret.toString(),
        avgTicket.toStringAsFixed(2),
      ];

      final csvString = _rowsToCsv([headers, values]);
      final bytes = Uint8List.fromList(csvString.codeUnits);
      final name = '$codigo';
      final savedPath = await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.text,
      );
      return savedPath;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.cajaCsvMediaStore', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<void> openFile(String path) async {
    await OpenFilex.open(path);
  }

  Future<File> exportCajaToCsvInDownloads(int cajaId) async {
    try {
      // Prioridad: carpeta pública de Descargas
      Directory? exportDir;
      try {
        final dl = Directory('/storage/emulated/0/Download');
        if (await dl.exists()) {
          exportDir = dl;
        }
      } catch (_) {
        exportDir = null;
      }
      // Si no existe, usar path_provider como alternativa
      if (exportDir == null) {
        try {
          final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (dirs != null && dirs.isNotEmpty) {
            exportDir = dirs.first;
          }
        } catch (_) {
          exportDir = null;
        }
      }
      exportDir ??= await _ensureExportDir();
      return exportCajaToCsv(cajaId, directoryPath: exportDir.path);
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.cajaCsvDownloads', error: e, stackTrace: st, payload: {'cajaId': cajaId});
      rethrow;
    }
  }

  Future<void> shareCajaCsv(int cajaId) async {
    final file = await exportCajaToCsv(cajaId);
    final base = p.basename(file.path);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Caja $base', title: 'Caja $base'));
  }

  Future<File> exportVisibleCajasToCsvInDownloads() async {
    try {
      Directory? exportDir;
      try {
        final dl = Directory('/storage/emulated/0/Download');
        if (await dl.exists()) {
          exportDir = dl;
        }
      } catch (_) {
        exportDir = null;
      }
      if (exportDir == null) {
        try {
          final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (dirs != null && dirs.isNotEmpty) {
            exportDir = dirs.first;
          }
        } catch (_) {
          exportDir = null;
        }
      }
      exportDir ??= await _ensureExportDir();

      final db = await AppDatabase.instance();
      final cajas = await db.query('caja_diaria', where: 'visible = 1', orderBy: 'fecha DESC, id DESC');

      final headers = [
        'Codigo de caja', 'Estado', 'Fecha', 'Hora apertura', 'Disciplina',
        'Desc Evento', 'Caj Apertura', 'Caj cierre', 'Total Ventas',
        'Fondo Inicial', 'Efectivo declarado en caja', 'Diferencia',
        'Entradas vendidas', 'Tickets emitidos', 'Tickets anulados',
        'Ventas Efectivo', 'Ventas Transferencia', 'Ventas por producto',
        'Ingresos', 'Retiros', 'Ticket promedio'
      ];

      final rows = <List<String>>[headers];
      for (final caja in cajas) {
        final cajaId = (caja['id'] as num).toInt();
        final payloadResumen = await _buildPayload(db, cajaId);
        final resumen = Map<String, Object?>.from(payloadResumen['resumen'] as Map);
        final totalesMp = List<Map<String, Object?>>.from(payloadResumen['totales_por_mp'] as List);
        final porProducto = List<Map<String, Object?>>.from(payloadResumen['ventas_por_producto'] as List);
        final movimientos = List<Map<String, Object?>>.from(payloadResumen['movimientos'] as List);

        double ventasEfec = 0.0, ventasTransf = 0.0;
        for (final m in totalesMp) {
          final desc = (m['mp_desc'] as String?)?.toLowerCase() ?? '';
          final monto = ((m['total'] as num?) ?? 0).toDouble();
          if (desc.contains('efectivo')) ventasEfec += monto;
          else if (desc.contains('transfer')) ventasTransf += monto;
        }

        final productosConcat = porProducto.map((p) {
          final nom = (p['producto_nombre'] ?? p['nombre'] ?? '').toString();
          final cant = ((p['cantidad'] as num?) ?? 0).toInt();
          final tot = ((p['total'] as num?) ?? 0).toInt();
          return '$nom x $cant = $tot';
        }).join(' ; ');

        double ing = 0.0, ret = 0.0;
        for (final m in movimientos) {
          final tipo = (m['tipo'] ?? '').toString().toUpperCase();
          final monto = ((m['monto'] as num?) ?? 0).toDouble();
          if (tipo == 'INGRESO') ing += monto; else if (tipo == 'RETIRO') ret += monto;
        }

        final avgRows = await db.rawQuery('''
          SELECT AVG(total_venta_no_anulados) AS avg_ticket
          FROM (
            SELECT v.id, SUM(t.total_ticket) AS total_venta_no_anulados
            FROM ventas v
            JOIN tickets t ON t.venta_id = v.id AND t.status <> 'Anulado'
            WHERE v.caja_id = ?
            GROUP BY v.id
          )
        ''', [cajaId]);
        final avgTicket = (avgRows.isNotEmpty && (avgRows.first['avg_ticket'] as num?) != null)
            ? ((avgRows.first['avg_ticket'] as num).toDouble())
            : 0.0;

        final tks = Map<String, Object?>.from(resumen['tickets'] as Map);
        rows.add([
          caja['codigo_caja']?.toString() ?? '',
          caja['estado']?.toString() ?? '',
          caja['fecha']?.toString() ?? '',
          caja['hora_apertura']?.toString() ?? '',
          caja['disciplina']?.toString() ?? '',
          caja['descripcion_evento']?.toString() ?? '',
          caja['cajero_apertura']?.toString() ?? '',
          caja['cajero_cierre']?.toString() ?? '',
          (((resumen['total'] as num?) ?? 0)).toString(),
          (((caja['fondo_inicial'] as num?) ?? 0)).toString(),
          (((caja['conteo_efectivo_final'] as num?) ?? 0)).toString(),
          (((caja['diferencia'] as num?) ?? 0)).toString(),
          ((((caja['entradas'] as num?) ?? 0)).toInt()).toString(),
          (((tks['emitidos'] as num?) ?? 0).toInt()).toString(),
          (((tks['anulados'] as num?) ?? 0).toInt()).toString(),
          ventasEfec.toString(),
          ventasTransf.toString(),
          productosConcat,
          ing.toString(),
          ret.toString(),
          avgTicket.toStringAsFixed(2),
        ]);
      }

      final csv = _rowsToCsv(rows);
      final file = File(p.join(exportDir.path, 'cajas_historial.csv'));
      await file.writeAsString(csv, flush: true);
      return file;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.cajasCsvDownloads', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<String> saveVisibleCajasCsvToDownloadsViaMediaStore() async {
    try {
      final db = await AppDatabase.instance();
      final cajas = await db.query('caja_diaria', where: 'visible = 1', orderBy: 'fecha DESC, id DESC');

      final headers = [
        'Codigo de caja', 'Estado', 'Fecha', 'Hora apertura', 'Disciplina',
        'Desc Evento', 'Caj Apertura', 'Caj cierre', 'Total Ventas',
        'Fondo Inicial', 'Efectivo declarado en caja', 'Diferencia',
        'Entradas vendidas', 'Tickets emitidos', 'Tickets anulados',
        'Ventas Efectivo', 'Ventas Transferencia', 'Ventas por producto',
        'Ingresos', 'Retiros', 'Ticket promedio'
      ];
      final rows = <List<String>>[headers];

      for (final caja in cajas) {
        final cajaId = (caja['id'] as num).toInt();
        final payloadResumen = await _buildPayload(db, cajaId);
        final resumen = Map<String, Object?>.from(payloadResumen['resumen'] as Map);
        final totalesMp = List<Map<String, Object?>>.from(payloadResumen['totales_por_mp'] as List);
        final porProducto = List<Map<String, Object?>>.from(payloadResumen['ventas_por_producto'] as List);
        final movimientos = List<Map<String, Object?>>.from(payloadResumen['movimientos'] as List);

        double ventasEfec = 0.0, ventasTransf = 0.0;
        for (final m in totalesMp) {
          final desc = (m['mp_desc'] as String?)?.toLowerCase() ?? '';
          final monto = ((m['total'] as num?) ?? 0).toDouble();
          if (desc.contains('efectivo')) ventasEfec += monto;
          else if (desc.contains('transfer')) ventasTransf += monto;
        }
        final productosConcat = porProducto.map((p) {
          final nom = (p['producto_nombre'] ?? p['nombre'] ?? '').toString();
          final cant = ((p['cantidad'] as num?) ?? 0).toInt();
          final tot = ((p['total'] as num?) ?? 0).toInt();
          return '$nom x $cant = $tot';
        }).join(' ; ');
        double ing = 0.0, ret = 0.0;
        for (final m in movimientos) {
          final tipo = (m['tipo'] ?? '').toString().toUpperCase();
          final monto = ((m['monto'] as num?) ?? 0).toDouble();
          if (tipo == 'INGRESO') ing += monto; else if (tipo == 'RETIRO') ret += monto;
        }
        final avgRows = await db.rawQuery('''
          SELECT AVG(total_venta_no_anulados) AS avg_ticket
          FROM (
            SELECT v.id, SUM(t.total_ticket) AS total_venta_no_anulados
            FROM ventas v
            JOIN tickets t ON t.venta_id = v.id AND t.status <> 'Anulado'
            WHERE v.caja_id = ?
            GROUP BY v.id
          )
        ''', [cajaId]);
        final avgTicket = (avgRows.isNotEmpty && (avgRows.first['avg_ticket'] as num?) != null)
            ? ((avgRows.first['avg_ticket'] as num).toDouble())
            : 0.0;
        final tks = Map<String, Object?>.from(resumen['tickets'] as Map);
        rows.add([
          caja['codigo_caja']?.toString() ?? '',
          caja['estado']?.toString() ?? '',
          caja['fecha']?.toString() ?? '',
          caja['hora_apertura']?.toString() ?? '',
          caja['disciplina']?.toString() ?? '',
          caja['descripcion_evento']?.toString() ?? '',
          caja['cajero_apertura']?.toString() ?? '',
          caja['cajero_cierre']?.toString() ?? '',
          (((resumen['total'] as num?) ?? 0)).toString(),
          (((caja['fondo_inicial'] as num?) ?? 0)).toString(),
          (((caja['conteo_efectivo_final'] as num?) ?? 0)).toString(),
          (((caja['diferencia'] as num?) ?? 0)).toString(),
          ((((caja['entradas'] as num?) ?? 0)).toInt()).toString(),
          (((tks['emitidos'] as num?) ?? 0).toInt()).toString(),
          (((tks['anulados'] as num?) ?? 0).toInt()).toString(),
          ventasEfec.toString(),
          ventasTransf.toString(),
          productosConcat,
          ing.toString(),
          ret.toString(),
          avgTicket.toStringAsFixed(2),
        ]);
      }

      final csvString = _rowsToCsv(rows);
      final bytes = Uint8List.fromList(csvString.codeUnits);
      final savedPath = await FileSaver.instance.saveFile(
        name: 'cajas_historial',
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.text,
      );
      return savedPath;
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'export.cajasCsvMediaStore', error: e, stackTrace: st);
      rethrow;
    }
  }
}
