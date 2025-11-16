import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../../services/usb_printer_service.dart';
import '../format.dart';
import 'caja_open_page.dart';
import 'caja_list_page.dart';
import 'caja_page.dart';
import 'pos_main_page.dart';
import 'printer_test_page.dart';
import 'sales_list_page.dart';
import 'products_page.dart';
import 'settings_page.dart';
import 'help_page.dart';
import 'movimientos_page.dart';
import 'error_logs_page.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/dao/db.dart';

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
  bool _showAdvanced = false;

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
      } catch (e, st) {
        AppDatabase.logLocalError(scope: 'home_page.caja_resumen', error: e, stackTrace: st, payload: {'cajaId': c['id']});
      }
    }
    try {
      final sp = await SharedPreferences.getInstance();
      _showAdvanced = sp.getBool('show_advanced_options') ?? false;
    } catch (_) {}
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
        drawer: Drawer(
          child: ListView(
            children: [
              const DrawerHeader(child: Text('BuffetApp')),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Inicio'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: const Text('Ventas'),
                enabled: _caja != null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  if (_caja == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Abrí una caja para vender')),
                    );
                    return;
                  }
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const PosMainPage()),
                  );
                  if (!mounted) return;
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Tickets'),
                enabled: _caja != null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  if (_caja == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Abrí una caja para ver los tickets')),
                    );
                    return;
                  }
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const SalesListPage()),
                  );
                  if (!mounted) return;
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.store),
                title: const Text('Caja'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const CajaPage()),
                  );
                  if (!mounted) return;
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Historial de cajas'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const CajaListPage()),
                  );
                  if (!mounted) return;
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_vert),
                title: const Text('Movimientos caja'),
                enabled: _caja != null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  if (_caja == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Abrí una caja para ver movimientos')),
                    );
                    return;
                  }
                  await nav.push(
                    MaterialPageRoute(builder: (_) => MovimientosPage(cajaId: _caja!['id'] as int)),
                  );
                  if (!mounted) return;
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2),
                title: const Text('Productos'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const ProductsPage()),
                  );
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
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                  if (changed == true && mounted) {
                    await _load();
                  }
                },
              ),
              if (_showAdvanced)
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Logs de errores'),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    nav.pop();
                    await nav.push(
                      MaterialPageRoute(builder: (_) => const ErrorLogsPage()),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Config. impresora'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const PrinterTestPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Ayuda'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const HelpPage()),
                  );
                },
              ),
              // Opción 'Logs de errores' ocultada del menú lateral por ahora
            ],
          ),
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
