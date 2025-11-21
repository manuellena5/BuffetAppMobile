import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../data/dao/db.dart';
import '../ui/state/reportes_model.dart';

class ReportesService {
  Future<Database> _db() async => (await AppDatabase.instance()).database;

  Future<List<DateTime>> obtenerFechasCajas() async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT DISTINCT fecha FROM caja_diaria WHERE fecha IS NOT NULL ORDER BY fecha',
    );
    return rows.map((r) {
      final f = r['fecha'] as String?;
      final parsed = f == null ? null : DateTime.tryParse(f);
      return parsed ?? DateTime.now();
    }).toList();
  }

  Future<List<String>> obtenerDisciplinas() async {
    final db = await _db();
    final rows = await db.rawQuery('SELECT DISTINCT disciplina FROM caja_diaria WHERE disciplina IS NOT NULL AND disciplina <> "" ORDER BY disciplina');
    return rows.map((r) => (r['disciplina'] as String?) ?? '').where((e) => e.isNotEmpty).toList();
  }

  String _strftimeFormat(AggregacionFecha agg) {
    switch (agg) {
      case AggregacionFecha.dia:
        return '%Y-%m-%d';
      case AggregacionFecha.mes:
        return '%Y-%m';
      case AggregacionFecha.anio:
        return '%Y';
    }
  }

  Future<List<PeriodoVentas>> obtenerSerieVentas({required DateTime desde, required DateTime hasta, required AggregacionFecha agregacion, String? disciplina}) async {
    final db = await _db();
    final formato = _strftimeFormat(agregacion);
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add('v.fecha_hora BETWEEN ? AND ?');
    params.add(desde.toIso8601String());
    params.add(hasta.toIso8601String());
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    final sql = '''
      SELECT strftime('$formato', v.fecha_hora) AS periodo,
             SUM(v.total_venta) AS total
      FROM ventas v
      JOIN caja_diaria c ON c.id = v.caja_id
      WHERE ${filtros.join(' AND ')}
      GROUP BY periodo
      ORDER BY periodo
    ''';
    final rows = await db.rawQuery(sql, params);
    return rows.map((r) => PeriodoVentas(
      periodo: (r['periodo'] as String?) ?? '',
      totalVentas: (r['total'] as num?)?.toDouble() ?? 0,
    )).toList();
  }

  Future<ReportesKpis> obtenerKpis({required DateTime desde, required DateTime hasta, String? disciplina}) async {
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add('v.fecha_hora BETWEEN ? AND ?');
    params.add(desde.toIso8601String());
    params.add(hasta.toIso8601String());
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    final sqlVentas = '''
      SELECT COUNT(*) AS cant, SUM(v.total_venta) AS total
      FROM ventas v
      JOIN caja_diaria c ON c.id = v.caja_id
      WHERE ${filtros.join(' AND ')}
    ''';
    final ventasRow = (await db.rawQuery(sqlVentas, params)).firstOrNull ?? {};
    final cantVentas = (ventasRow['cant'] as num?)?.toInt() ?? 0;
    final totalVentas = (ventasRow['total'] as num?)?.toDouble() ?? 0;
    final ticketProm = cantVentas > 0 ? (totalVentas / cantVentas).toDouble() : 0.0;

    final sqlTickets = '''
      SELECT 
        SUM(CASE WHEN t.status <> 'Anulado' THEN 1 ELSE 0 END) AS activos,
        SUM(CASE WHEN t.status = 'Anulado' THEN 1 ELSE 0 END) AS anulados,
        SUM(CASE WHEN t.status <> 'Anulado' THEN t.total_ticket ELSE 0 END) AS importe_activos
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id AND v.activo=1
      JOIN caja_diaria c ON c.id = v.caja_id
      WHERE ${filtros.join(' AND ')}
    ''';
    final ticketsRow = (await db.rawQuery(sqlTickets, params)).firstOrNull ?? {};
    final activos = (ticketsRow['activos'] as num?)?.toInt() ?? 0;
    final anulados = (ticketsRow['anulados'] as num?)?.toInt() ?? 0;
    final importeActivos = (ticketsRow['importe_activos'] as num?)?.toDouble() ?? 0;

    return ReportesKpis(
      totalVentas: totalVentas,
      ticketPromedio: ticketProm,
      cantidadVentas: cantVentas,
      ticketsActivos: activos,
      ticketsAnulados: anulados,
      totalEntradasCount: activos, // interpretación provisional
      totalEntradasImporte: importeActivos, // interpretación provisional
    );
  }

  Future<List<MetodoPagoVentas>> obtenerVentasPorMetodo({required DateTime desde, required DateTime hasta, String? disciplina}) async {
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add('v.fecha_hora BETWEEN ? AND ?');
    params.add(desde.toIso8601String());
    params.add(hasta.toIso8601String());
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    final sql = '''
      SELECT mp.descripcion AS metodo, SUM(v.total_venta) AS total
      FROM ventas v
      JOIN caja_diaria c ON c.id = v.caja_id
      JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      WHERE ${filtros.join(' AND ')}
      GROUP BY mp.id, mp.descripcion
      ORDER BY total DESC
    ''';
    final rows = await db.rawQuery(sql, params);
    return rows.map((r) => MetodoPagoVentas(
      metodo: (r['metodo'] as String?) ?? '',
      importe: (r['total'] as num?)?.toDouble() ?? 0,
    )).toList();
  }

  Future<List<ProductoRanking>> obtenerRankingProductos({required DateTime desde, required DateTime hasta, String? disciplina, int limit = 10}) async {
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add('v.fecha_hora BETWEEN ? AND ?');
    params.add(desde.toIso8601String());
    params.add(hasta.toIso8601String());
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    final sql = '''
      SELECT p.id AS producto_id, p.nombre AS nombre,
             SUM(vi.cantidad) AS unidades,
             SUM(vi.subtotal) AS importe
      FROM venta_items vi
      JOIN ventas v ON v.id = vi.venta_id AND v.activo=1
      JOIN caja_diaria c ON c.id = v.caja_id
      JOIN products p ON p.id = vi.producto_id
      WHERE ${filtros.join(' AND ')}
      GROUP BY p.id, p.nombre
      ORDER BY importe DESC
      LIMIT $limit
    ''';
    final rows = await db.rawQuery(sql, params);
    return rows.map((r) => ProductoRanking(
      productoId: (r['producto_id'] as num?)?.toInt() ?? 0,
      nombre: (r['nombre'] as String?) ?? '',
      unidades: (r['unidades'] as num?)?.toInt() ?? 0,
      importe: (r['importe'] as num?)?.toDouble() ?? 0,
    )).toList();
  }
}

extension FirstOrNullExt<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
