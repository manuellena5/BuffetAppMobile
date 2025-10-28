import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/dao/db.dart';
import '../../services/venta_service.dart';
import '../../services/print_service.dart';
import '../../services/usb_printer_service.dart';
import '../format.dart';
import '../state/cart_model.dart';

class PaymentMethodPage extends StatefulWidget {
  const PaymentMethodPage({super.key});
  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  List<Map<String, dynamic>> _mp = [];
  bool _loading = true;
  final _ventaService = VentaService();
  bool _imprimir = true; // por defecto seleccionado
  final _usb = UsbPrinterService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final data = await db
        .rawQuery('SELECT id, descripcion FROM metodos_pago ORDER BY id');
    setState(() {
      _mp = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartModel>();
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Método de pago')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatCurrency(cart.total),
                style:
                    const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Cantidad total a pagar'),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: cart.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final it = cart.items[i];
                  return ListTile(
                    dense: true,
                    title: Text(it.nombre),
                    subtitle: Text(
                        '${it.cantidad} x ${formatCurrency(it.precioUnitario)}'),
                    trailing:
                        Text(formatCurrency(it.precioUnitario * it.cantidad)),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              value: _imprimir,
              onChanged: (v) => setState(() => _imprimir = v ?? true),
              title: const Text('Imprimir ticket'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            for (final m in _mp)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: cart.isEmpty
                      ? null
                      : () async {
                          final nav = Navigator.of(context);
                          final cartModel = context.read<CartModel>();
                          final items = cart.items
                              .map((e) => {
                                    'producto_id': e.productoId,
                                    'nombre': e.nombre,
                                    'precio_unitario': e.precioUnitario,
                                    'cantidad': e.cantidad,
                                  })
                              .toList();
                          // Validar USB conectada
                          final usbConnected = await _usb.isConnected();
                          final marcarImpreso = _imprimir && usbConnected;
                          if (!usbConnected && _imprimir && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No hay impresora USB conectada. Los tickets se guardarán como No Impreso.')),
                            );
                          }
                          final result = await _ventaService.crearVenta(
                            metodoPagoId: m['id'] as int,
                            items: items,
                            marcarImpreso: marcarImpreso,
                          );
                          if (marcarImpreso) {
                            try {
                              final ventaId = result['ventaId'] as int;
                              final ok = await PrintService().printVentaTicketsForVentaUsbOnly(ventaId);
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Fallo la impresión por USB.')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error al imprimir: $e')),
                                );
                              }
                            }
                          }
                          if (context.mounted) {
                            cartModel.clear();
                            nav.pop(true);
                          }
                        },
                  child: Text((m['descripcion'] as String).toUpperCase()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
