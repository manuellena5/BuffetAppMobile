import 'package:uuid/uuid.dart';
import '../data/dao/db.dart';
import 'caja_service.dart';

class VentaService {
  final _uuid = const Uuid();

  Future<int> crearVenta({required int metodoPagoId, required List<Map<String, dynamic>> items, bool marcarImpreso = true}) async {
    final db = await AppDatabase.instance();
    final caja = await CajaService().getCajaAbierta();
    return await db.transaction((txn) async {
      double total = 0;
      for (final it in items) {
        total += ((it['precio_unitario'] as num) * (it['cantidad'] as num)).toDouble();
      }
      final now = DateTime.now();
      final fecha = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hora = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final idVenta = await txn.insert('ventas', {
        'uuid': _uuid.v4(),
        'fecha_hora': '$fecha $hora',
        'total_venta': total,
        'status': 'No impreso',
        'activo': 1,
        'metodo_pago_id': metodoPagoId,
        'caja_id': caja?['id'],
      });
      for (final it in items) {
        await txn.insert('venta_items', {
          'venta_id': idVenta,
          'producto_id': it['producto_id'],
          'cantidad': it['cantidad'],
          'precio_unitario': it['precio_unitario'],
          'subtotal': ((it['precio_unitario'] as num) * (it['cantidad'] as num)).toDouble(),
        });

        // Crear tickets por ÍTEM (uno por unidad)
        final pid = it['producto_id'] as int;
        final qty = it['cantidad'] as int;
        // Obtener datos del producto (codigo y categoria)
        final prod = (await txn.query('products', columns: ['codigo_producto','categoria_id','precio_venta'], where: 'id=?', whereArgs: [pid])).first;
        final codigo = (prod['codigo_producto'] as String?) ?? 'PRD$pid';
        final categoriaId = prod['categoria_id'];
        final unit = (it['precio_unitario'] as num).toDouble();
        final ddmmyyyy = '${now.day.toString().padLeft(2,'0')}${now.month.toString().padLeft(2,'0')}${now.year.toString()}';
        for (var k = 0; k < qty; k++) {
          final ticketId = await txn.insert('tickets', {
            'venta_id': idVenta,
            'categoria_id': categoriaId,
            'producto_id': pid,
            'fecha_hora': '$fecha $hora',
            'status': marcarImpreso ? 'Impreso' : 'No Impreso',
            'total_ticket': unit,
            'identificador_ticket': null,
          });
          final ident = '$codigo-$ddmmyyyy-$ticketId';
          await txn.update('tickets', {'identificador_ticket': ident}, where: 'id=?', whereArgs: [ticketId]);
        }
      }
      return idVenta;
    });
  }
}
