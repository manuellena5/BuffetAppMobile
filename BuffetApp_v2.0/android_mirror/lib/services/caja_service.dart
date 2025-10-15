import '../data/dao/db.dart';

class CajaService {
  Future<Map<String, dynamic>?> getCajaAbierta() async {
    final db = await AppDatabase.instance();
    final r = await db.query('caja_diaria', where: "estado = 'ABIERTA'", limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  Future<int> abrirCaja({required String usuario, required double fondoInicial, required String disciplina, required String descripcionEvento, String? observacion, required String puntoVentaCodigo}) async {
    final db = await AppDatabase.instance();
    final now = DateTime.now();
    final fecha = '${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final hora = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
    String discCode = 'OTRO';
    if (disciplina.toLowerCase().contains('infantil')) { discCode = 'FUTI'; }
    else if (disciplina.toLowerCase().contains('mayor')) { discCode = 'FUTM'; }
    else if (disciplina.toLowerCase().contains('evento')) { discCode = 'EVEN'; }
    final fechaCompact = fecha.replaceAll('-', '');
    final baseCodigo = '$puntoVentaCodigo-$fechaCompact-$discCode';
    // Generar código único: si existe el base, agregar sufijo -2, -3, ...
    String codigo = baseCodigo;
    final existentes = await db.query(
      'caja_diaria',
      columns: ['codigo_caja'],
      where: 'codigo_caja LIKE ?',
      whereArgs: ['${baseCodigo}%'],
    );
    if (existentes.isNotEmpty) {
      int maxSufijo = 1; // 1 implica que existe el base sin sufijo
      for (final row in existentes) {
        final cc = (row['codigo_caja'] as String?) ?? '';
        if (cc == baseCodigo) {
          if (maxSufijo < 1) maxSufijo = 1;
          continue;
        }
        if (cc.startsWith('$baseCodigo-')) {
          final parts = cc.split('-');
          final last = parts.isNotEmpty ? parts.last : '';
          final n = int.tryParse(last);
          if (n != null && n > maxSufijo) {
            maxSufijo = n;
          }
        }
      }
      // si encontramos el base usado (maxSufijo>=1), proponer el siguiente entero
      if (maxSufijo >= 1) {
        codigo = '$baseCodigo-${maxSufijo + 1}';
      }
    }
    final aperturaDesc = descripcionEvento.isNotEmpty
        ? (observacion != null && observacion.isNotEmpty ? '$descripcionEvento — $observacion' : descripcionEvento)
        : (observacion ?? '');
    return await db.insert('caja_diaria', {
      'codigo_caja': codigo,
      'disciplina': disciplina,
      'fecha': fecha,
      'usuario_apertura': usuario,
      'hora_apertura': hora,
      'apertura_dt': '$fecha $hora',
      'fondo_inicial': fondoInicial,
      'estado': 'ABIERTA',
      'observaciones_apertura': aperturaDesc,
      'diferencia': 0,
      'ingresos': 0,
      'retiros': 0,
      'total_tickets': 0,
    });
  }

  Future<void> cerrarCaja({required int cajaId, required double efectivoEnCaja, required double transferencias, required String usuarioCierre, String? observacion}) async {
    final db = await AppDatabase.instance();
    final now = DateTime.now();
    final hora = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
    // calcular diferencia: (efectivo + transferencias) - totalVentasSistema (excluyendo tickets anulados)
    final tot = await db.rawQuery('''
      SELECT COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
    ''', [cajaId]);
    final totalVentas = (tot.first['total'] as num?)?.toDouble() ?? 0.0;
    final diferencia = (efectivoEnCaja + transferencias) - totalVentas;
    await db.update('caja_diaria', {
      'estado': 'CERRADA',
      'hora_cierre': hora,
      'cierre_dt': '${now.toIso8601String().substring(0,19).replaceAll('T',' ')}',
      'obs_cierre': observacion,
      'diferencia': diferencia,
    }, where: 'id=?', whereArgs: [cajaId]);
    // Se podría registrar un movimiento resumen si hiciera falta; por ahora solo cerramos estado
  }

  Future<Map<String, dynamic>> resumenCaja(int cajaId) async {
    final db = await AppDatabase.instance();
    final totalPorMp = await db.rawQuery('''
      SELECT v.metodo_pago_id as mp, m.descripcion as mp_desc, COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN metodos_pago m ON m.id = v.metodo_pago_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY v.metodo_pago_id
    ''', [cajaId]);
    final ticketsCont = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN t.status = 'Anulado' THEN 1 ELSE 0 END) as anulados,
        SUM(CASE WHEN t.status <> 'Anulado' THEN 1 ELSE 0 END) as emitidos
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ?
    ''', [cajaId]);
    final ventasPorProducto = await db.rawQuery('''
      SELECT p.nombre, COUNT(t.id) as cantidad, COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      JOIN products p ON p.id = t.producto_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY p.id
      ORDER BY cantidad DESC
    ''', [cajaId]);
    final totales = await db.rawQuery('''
      SELECT COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ? AND v.activo = 1 AND t.status <> 'Anulado'
    ''', [cajaId]);
    return {
      'total': totales.first['total'] ?? 0,
      'por_mp': totalPorMp,
      'tickets': ticketsCont.isNotEmpty ? ticketsCont.first : {'anulados':0,'emitidos':0},
      'por_producto': ventasPorProducto,
    };
  }

  Future<List<Map<String, dynamic>>> listarCajas() async {
    final db = await AppDatabase.instance();
    final r = await db.query(
      'caja_diaria',
      columns: ['id','codigo_caja','fecha','observaciones_apertura','estado','apertura_dt'],
      orderBy: 'apertura_dt DESC, id DESC',
    );
    return r.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> getCajaById(int id) async {
    final db = await AppDatabase.instance();
    final r = await db.query('caja_diaria', where: 'id=?', whereArgs: [id], limit: 1);
    return r.isNotEmpty ? r.first : null;
  }
}
