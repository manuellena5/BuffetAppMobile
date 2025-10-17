import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/dao/db.dart';
import '../format.dart';
import '../state/cart_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cart_page.dart';
import 'payment_method_page.dart';
import 'sales_list_page.dart';
import 'products_page.dart';
import 'caja_page.dart';
import 'caja_list_page.dart';
import '../../services/caja_service.dart';
import 'printer_test_page.dart';
import 'home_page.dart';
import 'settings_page.dart';
import '../../app_version.dart';
import 'help_page.dart';
import 'dart:io';

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
  bool _useList = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
  final prods = await db.rawQuery(
    'SELECT id, nombre, precio_venta, stock_actual, imagen FROM products WHERE visible=1 ORDER BY id');
    // cargar preferencia de layout
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getString('productos_layout');
      _useList = (v == 'list');
    } catch (_) {}
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
    // versión app fija desde constantes
    _appVersion = '${AppBuildInfo.version}+${AppBuildInfo.buildNumber}';
    setState(() {
      _productos = prods.map((e) => Map<String, dynamic>.from(e)).toList();
      _cajaTotal = cajaTotal;
      _cajaCodigo = cajaCodigo;
      _loading = false;
    });
  }

  Future<bool> _tryDecreaseStock(int id) async {
    final db = await AppDatabase.instance();
    final updated = await db.rawUpdate(
        'UPDATE products SET stock_actual = stock_actual - 1 WHERE id = ? AND stock_actual > 0',
        [id]);
    if (updated > 0) {
      final idx = _productos.indexWhere((e) => e['id'] == id);
      if (idx >= 0) {
        setState(() => _productos[idx]['stock_actual'] =
            (_productos[idx]['stock_actual'] as int) - 1);
      }
      return true;
    }
    return false;
  }

  int _gridCountForWidth(double w) {
    if (w >= 1000) return 5; // tablet landscape
    if (w >= 700) return 4; // tablet portrait
    if (w >= 500) return 3; // phones grandes
    return 2; // phones chicos
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
              final nav = Navigator.of(context);
              await nav.push(
                  MaterialPageRoute(builder: (_) => const CartPage()));
              if (!mounted) return;
              // refrescar lista por si hubo cambios de stock desde carrito
              await _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6)),
              child: Text('${cart.count}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        actions: [
          TextButton.icon(
            onPressed: cart.isEmpty
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final paid = await nav.push(
                        MaterialPageRoute(
                            builder: (_) => const PaymentMethodPage()));
                    if (paid == true && mounted) {
                      messenger.showSnackBar(
                          const SnackBar(content: Text('Venta registrada')));
                      await _load();
                    }
                  },
            icon: const Icon(Icons.attach_money, color: Colors.white),
            label: Text(formatCurrency(cart.total),
                style: const TextStyle(color: Colors.white)),
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
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const CartPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Recibos'),
              onTap: () async {
                final nav = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                nav.pop();
                final caja = await CajaService().getCajaAbierta();
                if (caja == null) {
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Abrí una caja para ver los tickets')));
                  return;
                }
                await nav.push(
                    MaterialPageRoute(builder: (_) => const SalesListPage()));
                if (!mounted) return;
                await _load();
              },
            ),
            // Se quita la opción "Importar catálogo (próx.)"
            ListTile(
              leading: const Icon(Icons.point_of_sale),
              title: const Text('Caja'),
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                await nav.push(
                    MaterialPageRoute(builder: (_) => const CajaPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Historial de cajas'),
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                await nav.push(
                    MaterialPageRoute(builder: (_) => const CajaListPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2),
              title: const Text('Productos (ABM)'),
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                await nav.push(
                    MaterialPageRoute(builder: (_) => const ProductsPage()));
                if (!mounted) return;
                await _load();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configuraciones'),
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                final changed = await nav.push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()));
                if (changed == true && mounted) {
                  await _load();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Prueba de impresora'),
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                await nav.push(MaterialPageRoute(
                    builder: (_) => const PrinterTestPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Ayuda'),
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                await nav.push(
                    MaterialPageRoute(builder: (_) => const HelpPage()));
              },
            ),
            const SizedBox(height: 8),
            if (_appVersion != null)
              Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 16, top: 8),
                child: Text('Versión: $_appVersion',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: cart.isEmpty
                    ? null
                    : () async {
                          final nav = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final paid = await nav.push(
                              MaterialPageRoute(
                                  builder: (_) => const PaymentMethodPage()));
                          if (paid == true && mounted) {
                            messenger.showSnackBar(
                                const SnackBar(content: Text('Venta registrada')));
                          await _load();
                        }
                      },
                child: Text('COBRAR  ${formatCurrency(cart.total)}',
                    style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _useList ? _buildList() : _buildGrid(width),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(double width) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridCountForWidth(width),
        childAspectRatio: 1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _productos.length,
      itemBuilder: (ctx, i) => _productButton(_productos[i], isGrid: true),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: _productos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = _productos[i];
        return ListTile(
          onTap: () => _onTapProduct(p),
          leading: _buildLeadingImage(p),
          title: Text(p['nombre'] as String,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Row(children: [
            Text(formatCurrency(p['precio_venta'] as num),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            if (((p['stock_actual'] as int?) ?? 0) != 999)
              Text('Stock: ${p['stock_actual']}',
                  style: TextStyle(color: Colors.grey.shade700)),
          ]),
          // trailing vacío para un look más limpio en lista
        );
      },
    );
  }

  Widget _productButton(Map<String, dynamic> p, {bool isGrid = false}) {
    return ElevatedButton(
      onPressed: () => _onTapProduct(p),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade200,
        foregroundColor: Colors.black87,
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: _buildTileImage(p),
      ),
    );
  }

  Widget _buildLeadingImage(Map<String, dynamic> p) {
    final img = p['imagen'] as String?;
    if (img == null || img.isEmpty) {
      return const CircleAvatar(
        backgroundColor: Colors.grey,
        child: Icon(Icons.image, color: Colors.white),
      );
    }
    return CircleAvatar(
      backgroundColor: Colors.grey.shade300,
      backgroundImage: FileImage(File(img)),
    );
  }

  Widget _buildTileImage(Map<String, dynamic> p) {
    final img = p['imagen'] as String?;
    final name = (p['nombre'] as String?) ?? '';
    final price = p['precio_venta'] as num?;
    final stock = (p['stock_actual'] as int?) ?? 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img != null && img.isNotEmpty)
          Image.file(File(img), fit: BoxFit.cover)
        else
          Container(color: Colors.grey.shade300),
        // chip de stock (arriba-izquierda), oculto si 999 (ilimitado)
        if (stock != 999)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Stock: $stock',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        // chip de precio (arriba-derecha)
        if (price != null)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                formatCurrency(price),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        // overlay con nombre siempre visible
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onTapProduct(Map<String, dynamic> p) async {
    final id = p['id'] as int;
    final stock = (p['stock_actual'] as int?) ?? 0;
    final cartModel = context.read<CartModel>();
    if (stock == 999) {
      cartModel.add(
          id, p['nombre'] as String, (p['precio_venta'] as num).toDouble());
    } else {
      final ok = await _tryDecreaseStock(id);
      if (!ok) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(const SnackBar(content: Text('Sin stock')));
        return;
      }
      cartModel.add(
          id, p['nombre'] as String, (p['precio_venta'] as num).toDouble());
    }
  }
}
