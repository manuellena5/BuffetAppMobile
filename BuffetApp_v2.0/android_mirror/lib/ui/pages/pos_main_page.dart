import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/dao/db.dart';
import '../format.dart';
import '../state/cart_model.dart';
import 'cart_page.dart';
import 'payment_method_page.dart';
import 'sales_list_page.dart';
import 'products_page.dart';
import 'caja_page.dart';
import 'caja_list_page.dart';
import '../../services/caja_service.dart';
import 'printer_test_page.dart';
import 'home_page.dart';

class PosMainPage extends StatefulWidget {
  const PosMainPage({super.key});
  @override
  State<PosMainPage> createState() => _PosMainPageState();
}

class _PosMainPageState extends State<PosMainPage> {
  List<Map<String, dynamic>> _productos = [];
  bool _loading = true;
  double? _cajaTotal;
  String? _cajaCodigo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final prods = await db.rawQuery('SELECT id, nombre, precio_venta, stock_actual FROM products WHERE visible=1 ORDER BY id');
    // cargar info de caja abierta y total acumulado
    double? cajaTotal;
    String? cajaCodigo;
    try {
      final caja = await CajaService().getCajaAbierta();
      if (caja != null) {
        cajaCodigo = caja['codigo_caja'] as String?;
        final resumen = await CajaService().resumenCaja(caja['id'] as int);
        final t = resumen['total'] as num?;
        cajaTotal = t?.toDouble() ?? 0.0;
      }
    } catch (_) {
      // ignorar errores de caja en POS; mantener UI funcional
    }
    setState(() {
      _productos = prods.map((e) => Map<String, dynamic>.from(e)).toList();
      _cajaTotal = cajaTotal;
      _cajaCodigo = cajaCodigo;
      _loading = false;
    });
  }

  Future<bool> _tryDecreaseStock(int id) async {
    final db = await AppDatabase.instance();
    final updated = await db.rawUpdate('UPDATE products SET stock_actual = stock_actual - 1 WHERE id = ? AND stock_actual > 0', [id]);
    if (updated > 0) {
      final idx = _productos.indexWhere((e) => e['id'] == id);
      if (idx >= 0) setState(() => _productos[idx]['stock_actual'] = (_productos[idx]['stock_actual'] as int) - 1);
      return true;
    }
    return false;
  }

  int _gridCountForWidth(double w) {
    if (w >= 1000) return 5; // tablet landscape
    if (w >= 700) return 4;  // tablet portrait
    if (w >= 500) return 3;  // phones grandes
    return 2;                // phones chicos
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartModel>();
    final width = MediaQuery.of(context).size.width;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Ticket'),
          const SizedBox(width: 6),
          InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
              // ignore: use_build_context_synchronously
              if (!mounted) return;
              // refrescar lista por si hubo cambios de stock desde carrito
              await _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
              child: Text('${cart.count}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        actions: [
          TextButton.icon(
            onPressed: cart.isEmpty ? null : () async {
              final paid = await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentMethodPage()));
              if (paid == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta registrada')));
                await _load();
              }
            },
            icon: const Icon(Icons.attach_money, color: Colors.white),
            label: Text(formatCurrency(cart.total), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(child: Text('BuffetApp')),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Inicio'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (route) => false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Ticket actual'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Recibos'),
              onTap: () async {
                Navigator.pop(context);
                final caja = await CajaService().getCajaAbierta();
                if (caja == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abrí una caja para ver los tickets')));
                  return;
                }
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesListPage()));
                if (!mounted) return;
                await _load();
              },
            ),
            // Se quita la opción "Importar catálogo (próx.)"
            ListTile(
              leading: const Icon(Icons.point_of_sale),
              title: const Text('Caja'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Historial de cajas'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaListPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2),
              title: const Text('Productos (ABM)'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsPage()));
                if (!mounted) return;
                await _load();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Prueba de impresora'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterTestPage()));
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_cajaCodigo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.store, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Caja $_cajaCodigo • Total: ${formatCurrency((_cajaTotal ?? 0))}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: cart.isEmpty ? null : () async {
                  final paid = await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentMethodPage()));
                  if (paid == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta registrada')));
                    await _load();
                  }
                },
                child: Text('COBRAR  ${formatCurrency(cart.total)}', style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridCountForWidth(width),
                childAspectRatio: 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: _productos.length,
              itemBuilder: (ctx, i) {
                final p = _productos[i];
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.all(8),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  onPressed: () async {
                    final id = p['id'] as int;
                    final stock = (p['stock_actual'] as int?) ?? 0;
                    if (stock == 999) {
                      // No se controla stock: solo agregar a carrito
                      context.read<CartModel>().add(id, p['nombre'] as String, (p['precio_venta'] as num).toDouble());
                    } else {
                      final ok = await _tryDecreaseStock(id);
                      if (!ok) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin stock')));
                        return;
                      }
                      context.read<CartModel>().add(id, p['nombre'] as String, (p['precio_venta'] as num).toDouble());
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p['nombre'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(formatCurrency(p['precio_venta'] as num), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (((p['stock_actual'] as int?) ?? 0) != 999)
                        Text('[${p['stock_actual']}]', style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }
}
