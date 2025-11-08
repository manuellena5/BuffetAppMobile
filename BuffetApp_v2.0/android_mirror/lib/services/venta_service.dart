import 'package:uuid/uuid.dart';
import '../data/dao/db.dart';
import 'caja_service.dart';
// Nota: sincronización con la nube se hace fuera del flujo de venta.

class VentaService {
  final _uuid = const Uuid();

  /// Crea la venta y retorna el id de venta y los ids de tickets generados
  Future<Map<String, dynamic>> crearVenta(
      {required int metodoPagoId,
      required List<Map<String, dynamic>> items,
      bool marcarImpreso = true}) async {
    try {
      final db = await AppDatabase.instance();
      final caja = await CajaService().getCajaAbierta();
      return await db.transaction((txn) async {
        double total = 0;
        for (final it in items) {
          total += ((it['precio_unitario'] as num) * (it['cantidad'] as num))
              .toDouble();
        }
        final now = DateTime.now();
        final fecha =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final hora =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        final idVenta = await txn.insert('ventas', {
          'uuid': _uuid.v4(),
          'fecha_hora': '$fecha $hora',
          'total_venta': total,
          'status': 'No impreso',
          'activo': 1,
          'metodo_pago_id': metodoPagoId,
          'caja_id': caja?['id'],
        });
        final generatedTickets = <int>[];
        for (final it in items) {
          await txn.insert('venta_items', {
            'venta_id': idVenta,
            'producto_id': it['producto_id'],
            'cantidad': it['cantidad'],
            'precio_unitario': it['precio_unitario'],
            'subtotal': ((it['precio_unitario'] as num) * (it['cantidad'] as num))
                .toDouble(),
          });

          // Crear tickets por ÍTEM (uno por unidad)
          final pid = it['producto_id'] as int;
          final qty = it['cantidad'] as int;
          // Obtener datos del producto (codigo y categoria)
          final prod = (await txn.query('products',
                  columns: ['codigo_producto', 'categoria_id', 'precio_venta'],
                  where: 'id=?',
                  whereArgs: [pid]))
              .first;
          final codigo = (prod['codigo_producto'] as String?) ?? 'PRD$pid';
          final categoriaId = prod['categoria_id'];
          // la categoría se usa solo para impresión/export y no en este flujo
          final unit = (it['precio_unitario'] as num).toDouble();
          final ddmmyyyy =
              '${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString()}';
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
            await txn.update('tickets', {'identificador_ticket': ident},
                where: 'id=?', whereArgs: [ticketId]);
            generatedTickets.add(ticketId);
          }
        }
        return {'ventaId': idVenta, 'ticketIds': generatedTickets};
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'venta.crear',
        error: e,
        stackTrace: st,
        payload: {
          'metodoPagoId': metodoPagoId,
          'items': items.length,
          'marcarImpreso': marcarImpreso,
        },
      );
      rethrow;
    }
  }
}
