import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../format.dart';
import '../../data/dao/db.dart';
import '../state/cart_model.dart';
import 'payment_method_page.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartModel>();
    return Scaffold(
      appBar: AppBar(title: Text('Ticket  (${cart.count})')),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: cart.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = cart.items[i];
                return ListTile(
                  title: Text('${it.nombre} x ${it.cantidad}'),
                  subtitle: Text(formatCurrency(it.precioUnitario)),
                  trailing: Text(formatCurrency(it.subtotal),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  leading: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: () async {
                          final db = await AppDatabase.instance();
                          final row = (await db.rawQuery(
                                  'SELECT stock_actual FROM products WHERE id=?',
                                  [it.productoId]))
                              .first;
                          final stock = (row['stock_actual'] as int?) ?? 0;
                          if (stock != 999) {
                            await db.rawUpdate(
                                'UPDATE products SET stock_actual = stock_actual + 1 WHERE id = ?',
                                [it.productoId]);
                          }
                          // ignore: use_build_context_synchronously
                          context.read<CartModel>().dec(it.productoId);
                        },
                        icon: const Icon(Icons.remove_circle_outline)),
                    IconButton(
                        onPressed: () async {
                          final db = await AppDatabase.instance();
                          final row = (await db.rawQuery(
                                  'SELECT stock_actual FROM products WHERE id=?',
                                  [it.productoId]))
                              .first;
                          final stock = (row['stock_actual'] as int?) ?? 0;
                          if (stock == 999) {
                            // Solo incrementar carrito
                            // ignore: use_build_context_synchronously
                            context.read<CartModel>().inc(it.productoId);
                            return;
                          }
                          final updated = await db.rawUpdate(
                              'UPDATE products SET stock_actual = stock_actual - 1 WHERE id = ? AND stock_actual > 0',
                              [it.productoId]);
                          if (updated == 0) {
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Sin stock')));
                            return;
                          }
                          // ignore: use_build_context_synchronously
                          context.read<CartModel>().inc(it.productoId);
                        },
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cart.isEmpty
                          ? null
                          : () async {
                              final db = await AppDatabase.instance();
                              // Restaurar stock por cada item no ilimitado
                              for (final it in List.of(cart.items)) {
                                // SUMA (cantidad) al stock si no es ilimitado
                                await db.rawUpdate(
                                  'UPDATE products SET stock_actual = CASE WHEN stock_actual = 999 THEN 999 ELSE stock_actual + ? END WHERE id = ?',
                                  [it.cantidad, it.productoId],
                                );
                              }
                              // ignore: use_build_context_synchronously
                              context.read<CartModel>().clear();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Carrito limpiado')));
                              }
                            },
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text('Limpiar carrito'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(formatCurrency(cart.total),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: cart.isEmpty
                      ? null
                      : () async {
                          final paid = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PaymentMethodPage()));
                          if (paid == true && context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Venta registrada')));
                          }
                        },
                  child: Text('COBRAR  ${formatCurrency(cart.total)}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
