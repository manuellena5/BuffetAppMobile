import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../data/dao/db.dart';
import '../ui/state/reportes_model.dart';

class ReportesService {
  Future<Database> _db() async => (await AppDatabase.instance());

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

  /// Devuelve pares (fecha, disciplina) para construir calendario con colores.
  Future<List<Map<String, String>>> obtenerFechasCajasConDisciplinas() async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT fecha, disciplina FROM caja_diaria WHERE fecha IS NOT NULL AND disciplina IS NOT NULL AND disciplina <> "" ORDER BY fecha',
    );
    return rows.map((r) => {
          'fecha': (r['fecha'] as String?) ?? '',
          'disciplina': (r['disciplina'] as String?) ?? ''
        }).where((m) => m['fecha']!.isNotEmpty && m['disciplina']!.isNotEmpty).toList();
  }

  Future<List<String>> obtenerDisciplinas() async {
    final db = await _db();
    final rows = await db.rawQuery('SELECT DISTINCT disciplina FROM caja_diaria WHERE disciplina IS NOT NULL AND disciplina <> "" ORDER BY disciplina');
    return rows.map((r) => (r['disciplina'] as String?) ?? '').where((e) => e.isNotEmpty).toList();
  }

  Future<List<PeriodoVentas>> obtenerSerieVentas({required DateTime desde, required DateTime hasta, required AggregacionFecha agregacion, String? disciplina}) async {
    // Agrupación basada en fecha de apertura de caja (c.fecha) y
    // montos calculados SOLO con tickets no anulados.
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add("t.status <> 'Anulado'");
    filtros.add('c.fecha BETWEEN ? AND ?');
    params.add(_fmtDia(desde));
    params.add(_fmtDia(hasta));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    String selectPeriodo;
    String groupPeriodo;
    if (agregacion == AggregacionFecha.dia) {
      selectPeriodo = 'c.fecha';
      groupPeriodo = 'c.fecha';
    } else if (agregacion == AggregacionFecha.mes) {
      selectPeriodo = "substr(c.fecha,1,7)"; // YYYY-MM
      groupPeriodo = "substr(c.fecha,1,7)";
    } else { // anio
      selectPeriodo = "substr(c.fecha,1,4)"; // YYYY
      groupPeriodo = "substr(c.fecha,1,4)";
    }
    final sql = '''
      SELECT $selectPeriodo AS periodo, SUM(t.total_ticket) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      JOIN caja_diaria c ON c.id = v.caja_id AND v.activo=1
      WHERE ${filtros.join(' AND ')}
      GROUP BY $groupPeriodo
      ORDER BY $groupPeriodo
    ''';
    final rows = await db.rawQuery(sql, params);
    return rows.map((r) => PeriodoVentas(
      periodo: (r['periodo'] as String?) ?? '',
      totalVentas: (r['total'] as num?)?.toDouble() ?? 0,
    )).toList();
  }

  Future<List<Map<String, Object?>>> obtenerVentasDiaPorDisciplina({required DateTime mesInicio, required DateTime mesFin, String? disciplina}) async {
    // Devuelve filas dia, disciplina, total para el mes (por fecha apertura caja)
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add('c.fecha BETWEEN ? AND ?');
    params.add(_fmtDia(mesInicio));
    params.add(_fmtDia(mesFin));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    final sql = '''
      SELECT c.fecha AS dia, c.disciplina AS disciplina, SUM(t.total_ticket) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      JOIN caja_diaria c ON c.id = v.caja_id AND v.activo=1
      WHERE t.status <> 'Anulado' AND ${filtros.join(' AND ')}
      GROUP BY c.fecha, c.disciplina
      ORDER BY c.fecha, c.disciplina
    ''';
    return db.rawQuery(sql, params);
  }

  /// Totales de ventas por disciplina para un día específico.
  Future<List<Map<String, Object?>>> obtenerVentasPorDisciplinaDia({required DateTime dia}) async {
    final db = await _db();
    final dateStr = '${dia.year.toString().padLeft(4,'0')}-${dia.month.toString().padLeft(2,'0')}-${dia.day.toString().padLeft(2,'0')}';
    final sql = '''
      SELECT c.disciplina AS disciplina, SUM(t.total_ticket) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      JOIN caja_diaria c ON c.id = v.caja_id
      WHERE v.activo=1 AND t.status <> 'Anulado' AND c.fecha = ?
      GROUP BY c.disciplina
      ORDER BY total DESC
    ''';
    final rows = await db.rawQuery(sql, [dateStr]);
    return rows;
  }

  Future<ReportesKpis> obtenerKpis({required DateTime desde, required DateTime hasta, String? disciplina}) async {
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add("t.status <> 'Anulado'");
    // Rango por fecha de apertura de caja (c.fecha)
    filtros.add('c.fecha BETWEEN ? AND ?');
    params.add(_fmtDia(desde));
    params.add(_fmtDia(hasta));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    // Ventas básicas (total por tickets no anulados + cantidad de ventas distintas)
    final sqlVentas = '''
      SELECT COUNT(DISTINCT v.id) AS cant, SUM(t.total_ticket) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      JOIN caja_diaria c ON c.id = v.caja_id
      WHERE ${filtros.join(' AND ')}
    ''';
    final ventasRowList = await db.rawQuery(sqlVentas, params);
    final ventasRow = ventasRowList.isEmpty ? <String, Object?>{} : ventasRowList.first;
    final cantidadVentas = (ventasRow['cant'] as num?)?.toInt() ?? 0;
    final totalVentas = (ventasRow['total'] as num?)?.toDouble() ?? 0;
    final ticketPromedio = cantidadVentas > 0 ? totalVentas / cantidadVentas : 0.0;

    // Tickets (emitidos / anulados)
    final sqlTickets = '''
      SELECT 
        SUM(CASE WHEN t.status <> 'Anulado' THEN 1 ELSE 0 END) AS emitidos,
        SUM(CASE WHEN t.status = 'Anulado' THEN 1 ELSE 0 END) AS anulados
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id AND v.activo=1
      JOIN caja_diaria c ON c.id = v.caja_id
      WHERE c.fecha BETWEEN ? AND ? ${disciplina != null && disciplina.isNotEmpty ? ' AND c.disciplina = ?' : ''}
    ''';
    final ticketsParams = <Object?>[_fmtDia(desde), _fmtDia(hasta), if (disciplina != null && disciplina.isNotEmpty) disciplina];
    final ticketsRowList = await db.rawQuery(sqlTickets, ticketsParams);
    final ticketsRow = ticketsRowList.isEmpty ? <String, Object?>{} : ticketsRowList.first;
    final ticketsEmitidos = (ticketsRow['emitidos'] as num?)?.toInt() ?? 0;
    final ticketsAnulados = (ticketsRow['anulados'] as num?)?.toInt() ?? 0;

    // Entradas sumadas desde caja_diaria (dato cargado al cerrar)
    final filtrosCaja = <String>[];
    final paramsCaja = <Object?>[];
    filtrosCaja.add('fecha BETWEEN ? AND ?');
    paramsCaja.add(_fmtDia(desde));
    paramsCaja.add(_fmtDia(hasta));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtrosCaja.add('disciplina = ?');
      paramsCaja.add(disciplina);
    }
    // Promedio de entradas por caja en el período.
    final sqlEntradas = 'SELECT AVG(entradas) AS entradas FROM caja_diaria WHERE ${filtrosCaja.join(' AND ')}';
    final entradasRowList = await db.rawQuery(sqlEntradas, paramsCaja);
    final entradasRow = entradasRowList.isEmpty ? <String, Object?>{} : entradasRowList.first;
    final totalEntradas = (entradasRow['entradas'] as num?) == null
      ? 0
      : ((entradasRow['entradas'] as num).toDouble()).round();
    final ventasSobrePersonasPct = (totalEntradas > 0 && cantidadVentas > 0)
        ? (cantidadVentas / totalEntradas) * 100
        : 0.0;
    return ReportesKpis(
      totalVentas: totalVentas,
      ticketPromedio: ticketPromedio,
      cantidadVentas: cantidadVentas,
      totalEntradas: totalEntradas,
      ventasSobrePersonasPct: ventasSobrePersonasPct,
      ticketsEmitidos: ticketsEmitidos,
      ticketsAnulados: ticketsAnulados,
    );
  }

  Future<List<MetodoPagoVentas>> obtenerVentasPorMetodo({required DateTime desde, required DateTime hasta, String? disciplina}) async {
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('v.activo=1');
    filtros.add("t.status <> 'Anulado'");
    // Rango por fecha de caja
    filtros.add('c.fecha BETWEEN ? AND ?');
    params.add(_fmtDia(desde));
    params.add(_fmtDia(hasta));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    final sql = '''
      SELECT mp.descripcion AS metodo,
             SUM(t.total_ticket) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id AND v.activo=1
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
    filtros.add("t.status <> 'Anulado'");
    filtros.add('c.fecha BETWEEN ? AND ?');
    params.add(_fmtDia(desde));
    params.add(_fmtDia(hasta));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('c.disciplina = ?');
      params.add(disciplina);
    }
    // Ranking desde tickets (no anulados) para contar unidades correctamente.
    final sql = '''
      SELECT p.id AS producto_id, p.nombre AS nombre,
             COUNT(*) AS unidades,
             SUM(t.total_ticket) AS importe
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id AND v.activo=1
      JOIN caja_diaria c ON c.id = v.caja_id
      JOIN products p ON p.id = t.producto_id
      WHERE ${filtros.join(' AND ')}
      GROUP BY p.id, p.nombre
      ORDER BY unidades DESC
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

  Future<int> contarCajas({required DateTime desde, required DateTime hasta, String? disciplina}) async {
    final db = await _db();
    final filtros = <String>[];
    final params = <Object?>[];
    filtros.add('fecha BETWEEN ? AND ?');
    params.add(_fmtDia(desde));
    params.add(_fmtDia(hasta));
    if (disciplina != null && disciplina.isNotEmpty) {
      filtros.add('disciplina = ?');
      params.add(disciplina);
    }
    final sql = 'SELECT COUNT(*) AS cnt FROM caja_diaria WHERE ' + filtros.join(' AND ');
    final rows = await db.rawQuery(sql, params);
    if (rows.isEmpty) return 0;
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }
}

String _fmtDia(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
