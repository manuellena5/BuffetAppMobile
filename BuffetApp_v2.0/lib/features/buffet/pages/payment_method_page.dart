import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/dao/db.dart';
import '../services/caja_service.dart';
import '../services/venta_service.dart';
import '../../shared/services/print_service.dart';
import '../../shared/services/usb_printer_service.dart';
import '../../shared/format.dart';
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
  bool _processing = false;

  static final Set<int> _suppressNoUsbWarningForCajaIds = <int>{};

  Future<int?> _getCajaAbiertaId() async {
    final caja = await CajaService().getCajaAbierta();
    return caja?['id'] as int?;
  }

  Future<_NoUsbDialogResult?> _showNoUsbPrintDialog() {
    bool dontShowAgain = false;
    return showDialog<_NoUsbDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Impresora no conectada'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No hay una impresora conectada. El ticket se guardará como "No Impreso".',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (v) =>
                        setState(() => dontShowAgain = v ?? false),
                    title: const Text('No volver a mostrar este mensaje'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    _NoUsbDialogResult(
                      confirmed: true,
                      dontShowAgain: dontShowAgain,
                    ),
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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
            if (_processing) const LinearProgressIndicator(minHeight: 3),
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
                  onPressed: cart.isEmpty || _processing
                      ? null
                      : () async {
                          setState(() => _processing = true);
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
                          try {
                            bool usbConnected = false;
                            try {
                              usbConnected = await _usb.isConnected().timeout(
                                  const Duration(seconds: 2),
                                  onTimeout: () => false);
                            } catch (_) {
                              usbConnected =
                                  false; // en emulador o sin plugin, continuar sin impresión
                            }

                            if (_imprimir && !usbConnected && context.mounted) {
                              final cajaId = await _getCajaAbiertaId();
                              final suppressed = cajaId != null &&
                                  _suppressNoUsbWarningForCajaIds
                                      .contains(cajaId);
                              if (!suppressed) {
                                final res = await _showNoUsbPrintDialog();
                                if (res == null || res.confirmed != true) {
                                  return;
                                }
                                if (res.dontShowAgain && cajaId != null) {
                                  _suppressNoUsbWarningForCajaIds.add(cajaId);
                                }
                              }
                            }

                            final marcarImpreso = _imprimir && usbConnected;
                            final result = await _ventaService.crearVenta(
                              metodoPagoId: m['id'] as int,
                              items: items,
                              marcarImpreso: marcarImpreso,
                            );
                            if (marcarImpreso) {
                              try {
                                final ventaId = result['ventaId'] as int;
                                final ok = await PrintService()
                                    .printVentaTicketsForVentaUsbOnly(ventaId)
                                    .timeout(const Duration(seconds: 10),
                                        onTimeout: () => false);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Fallo la impresión por USB.')),
                                  );
                                }
                              } catch (e, st) {
                                AppDatabase.logLocalError(
                                    scope: 'payment.print_tickets',
                                    error: e,
                                    stackTrace: st);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Error al imprimir: $e')),
                                  );
                                }
                              }
                            }
                            if (context.mounted) {
                              cartModel.clear();
                              nav.pop(true);
                            }
                          } catch (e, st) {
                            AppDatabase.logLocalError(
                                scope: 'payment.crear_venta',
                                error: e,
                                stackTrace: st);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'No se pudo registrar la venta: $e')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _processing = false);
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

class _NoUsbDialogResult {
  final bool confirmed;
  final bool dontShowAgain;
  const _NoUsbDialogResult(
      {required this.confirmed, required this.dontShowAgain});
}
