import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../../services/usb_printer_service.dart';
import '../format.dart';
import 'caja_open_page.dart';
import 'caja_list_page.dart';
import 'caja_page.dart';
import 'pos_main_page.dart';
import 'printer_test_page.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _caja;
  double? _cajaTotal;
  bool _loading = true;
  bool _usbConnected = false;
  final _usb = UsbPrinterService();
  Timer? _timer;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _load();
    _startUsbPolling();
  }

  Future<void> _load() async {
    final svc = CajaService();
    final c = await svc.getCajaAbierta();
    double? total;
    if (c != null) {
      try {
        final r = await svc.resumenCaja(c['id'] as int);
        total = (r['total'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {}
    }
    setState(() {
      _caja = c;
      _cajaTotal = total;
      _loading = false;
    });
  }

  void _startUsbPolling() {
    // Refresca el estado de conexión cada 2s
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final ok = await _usb.isConnected();
      if (!mounted) return;
      if (ok != _usbConnected) {
        setState(() => _usbConnected = ok);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Volvé a tocar atrás para salir de la app')),
          );
          return;
        }
        await SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BuffetApp'),
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo pequeño
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Image.asset(
                      'assets/icons/app_icon_foreground.png',
                      width: 96,
                      height: 96,
                    ),
                  ),
                  if (_caja != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.store, size: 18),
                          const SizedBox(width: 6),
                          Text('Caja ${_caja!['codigo_caja']} • Total: '),
                          Text(
                            formatCurrency((_cajaTotal ?? 0)),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  if (_caja != null) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PosMainPage()));
                        if (!mounted) return;
                        await _load();
                      },
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Ventas'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CajaPage()));
                        if (!mounted) return;
                        await _load();
                      },
                      icon: const Icon(Icons.lock),
                      label: const Text('Cerrar caja'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PrinterTestPage()),
                        );
                        if (!mounted) return;
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Conexión impresora'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CajaListPage()));
                        if (!mounted) return;
                        await _load();
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Historial de cajas'),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CajaOpenPage()));
                        if (!mounted) return;
                        await _load();
                      },
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Abrir caja'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PrinterTestPage()),
                        );
                        if (!mounted) return;
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Conexión impresora'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CajaListPage()));
                        if (!mounted) return;
                        await _load();
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Historial de cajas'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Pie con estado de impresora
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, size: 12, color: _usbConnected ? Colors.green : Colors.red),
                      const SizedBox(width: 6),
                      Text(_usbConnected ? 'Impresora conectada' : 'Impresora desconectada'),
                    ],
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
