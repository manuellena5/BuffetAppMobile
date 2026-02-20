import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../buffet/services/caja_service.dart';
import '../shared/services/usb_printer_service.dart';
import '../shared/format.dart';
import '../buffet/pages/caja_open_page.dart';
import '../buffet/pages/caja_page.dart';
import '../buffet/pages/buffet_home_page.dart';
import '../shared/pages/printer_test_page.dart';
import '../buffet/pages/sales_list_page.dart';
import '../buffet/pages/products_page.dart';
import '../shared/pages/settings_page.dart';
import '../shared/pages/help_page.dart';
import '../tesoreria/pages/movimientos_page.dart';
import '../shared/pages/error_logs_page.dart';
import '../eventos/pages/eventos_page.dart';
import 'main_menu_page.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/dao/db.dart';
import '../shared/state/app_settings.dart';
import '../tesoreria/pages/unidad_gestion_selector_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.enableUsbPolling = true,
    this.cajaServiceOverride,
    this.enableContextDbLookups = true,
  });

  /// En tests conviene desactivar el polling para evitar timers periódicos.
  final bool enableUsbPolling;

  /// Solo para tests/DI: si se provee, se usa en lugar de crear uno nuevo.
  final CajaService? cajaServiceOverride;

  /// Si es false, no consulta SQLite para resolver nombres/ids del contexto.
  /// Útil en widget tests para evitar dependencias de DB.
  final bool enableContextDbLookups;
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

  String? _disciplinaActivaNombre;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.enableUsbPolling) {
      _startUsbPolling();
    }
  }

  Future<void> _load() async {
    final svc = widget.cajaServiceOverride ?? CajaService();

    Map<String, dynamic>? c;
    double? total;
    String? disciplinaNombre;

    try {
      final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
      final timeout =
          isTest ? const Duration(seconds: 2) : const Duration(seconds: 5);
      c = await svc.getCajaAbierta().timeout(timeout, onTimeout: () {
        AppDatabase.logLocalError(
            scope: 'home_page.getCajaAbierta.timeout',
            error: 'Timeout esperando getCajaAbierta()');
        return null;
      });

      if (c != null) {
        try {
          final r = await svc.resumenCaja(c['id'] as int);
          total = (r['total'] as num?)?.toDouble() ?? 0.0;
        } catch (e, st) {
          AppDatabase.logLocalError(
              scope: 'home_page.caja_resumen',
              error: e,
              stackTrace: st,
              payload: {'cajaId': c['id']});
        }
      }

      try {
        final sp = await SharedPreferences.getInstance();
        _showAdvanced = sp.getBool('show_advanced_options') ?? false;
      } catch (_) {}

      // Contexto activo: disciplina (best-effort)
      try {
        final settings = context.read<AppSettings>();
        await settings.ensureLoaded();

        // Si hay caja abierta y todavía no hay disciplina activa persistida,
        // intentamos mapear por nombre contra `disciplinas`.
        if (widget.enableContextDbLookups &&
            c != null &&
            settings.disciplinaActivaId == null) {
          final nombreCaja = (c['disciplina'] ?? '').toString().trim();
          if (nombreCaja.isNotEmpty) {
            final db = await AppDatabase.instance();
            final rows = await db.query(
              'disciplinas',
              columns: ['id', 'nombre'],
              where: 'nombre = ?',
              whereArgs: [nombreCaja],
              limit: 1,
            );
            if (rows.isNotEmpty) {
              final id = rows.first['id'] as int;
              await settings.setDisciplinaActivaId(id);
            }
          }
        }

        final disciplinaId = settings.disciplinaActivaId;
        if (widget.enableContextDbLookups && disciplinaId != null) {
          final db = await AppDatabase.instance();
          final rows = await db.query(
            'disciplinas',
            columns: ['nombre'],
            where: 'id = ?',
            whereArgs: [disciplinaId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            disciplinaNombre = (rows.first['nombre'] ?? '').toString();
          }
        }

        // Si no se resolvió por disciplina, intentar con Unidad de Gestión activa
        if (disciplinaNombre == null || disciplinaNombre!.trim().isEmpty) {
          final ugId = settings.unidadGestionActivaId;
          if (widget.enableContextDbLookups && ugId != null) {
            final db = await AppDatabase.instance();
            final rows = await db.query(
              'unidades_gestion',
              columns: ['nombre'],
              where: 'id = ?',
              whereArgs: [ugId],
              limit: 1,
            );
            if (rows.isNotEmpty) {
              disciplinaNombre = (rows.first['nombre'] ?? '').toString();
            }
          }
        }
      } catch (e, st) {
        AppDatabase.logLocalError(
            scope: 'home_page.contexto_activo', error: e, stackTrace: st);
      }
    } catch (e, st) {
      // No romper Home: si falla acceso a DB, seguimos sin caja.
      AppDatabase.logLocalError(
          scope: 'home_page.load', error: e, stackTrace: st);
    }

    if (!mounted) return;
    setState(() {
      _caja = c;
      _cajaTotal = total;
      _disciplinaActivaNombre = disciplinaNombre;
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
    final cs = Theme.of(context).colorScheme;
    final hasCaja = _caja != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Volvé a tocar atrás para salir de la app')),
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
                      const SnackBar(
                          content: Text('Abrí una caja para vender')),
                    );
                    return;
                  }
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const BuffetHomePage()),
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
                      const SnackBar(
                          content: Text('Abrí una caja para ver los tickets')),
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
                  if (_caja == null) {
                    await nav.push(
                      MaterialPageRoute(builder: (_) => const CajaOpenPage()),
                    );
                  } else {
                    await nav.push(
                      MaterialPageRoute(builder: (_) => const CajaPage()),
                    );
                  }
                  if (!mounted) return;
                  await _load();
                },
              ),
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Eventos / Listado Cajas'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(
                    MaterialPageRoute(builder: (_) => const EventosPage()),
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
                      const SnackBar(
                          content: Text('Abrí una caja para ver movimientos')),
                    );
                    return;
                  }
                  await nav.push(
                    MaterialPageRoute(
                        builder: (_) =>
                            MovimientosPage(cajaId: _caja!['id'] as int)),
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
              // Menú Principal
              ListTile(
                leading:
                    const Icon(Icons.home_outlined, color: Colors.deepPurple),
                title: const Text('Menú Principal'),
                subtitle: const Text('Volver al selector de módulos'),
                onTap: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const MainMenuPage(),
                    ),
                    (route) => false,
                  );
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
            : SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 132,
                            height: 132,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.6)),
                            ),
                            child: Image.asset(
                              'assets/icons/app_icon_foreground.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Bienvenido',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),

                          // BLOQUE NUEVO: Contexto Operativo
                          Card(
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const UnidadGestionSelectorPage(),
                                  ),
                                );
                                if (changed == true && mounted) {
                                  await _load();
                                }
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    dense: true,
                                    leading:
                                        const Icon(Icons.business_outlined),
                                    title: const Text('Unidad de gestión'),
                                    trailing: const Icon(Icons.chevron_right),
                                    subtitle: Text(
                                      hasCaja
                                          ? (_caja?['disciplina'] ?? '')
                                              .toString()
                                          : (_disciplinaActivaNombre
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? _disciplinaActivaNombre!
                                              : 'Sin seleccionar'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          const SizedBox(height: 8),
                          if (hasCaja) ...[
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.store, size: 18),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '${(_caja?['disciplina'] ?? '').toString()} | ${(_caja?['fecha'] ?? '').toString()} • Total: ${formatCurrency((_cajaTotal ?? 0))}',
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 22),
                          if (hasCaja) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.point_of_sale,
                                    size: 26, color: cs.primary),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const BuffetHomePage()),
                                  );
                                  if (!mounted) return;
                                  await _load();
                                },
                                label: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Text(
                                    'Buffet / Ventas',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: Icon(
                                hasCaja ? Icons.lock : Icons.lock_open,
                                size: 26,
                              ),
                              onPressed: () async {
                                if (hasCaja) {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const CajaPage()),
                                  );
                                } else {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const CajaOpenPage()),
                                  );
                                }
                                if (!mounted) return;
                                await _load();
                              },
                              label: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  hasCaja ? 'Cerrar caja' : 'Abrir caja',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // TODO: NUEVO módulo de Tesorería - MovimientoCreatePage será creado en la siguiente fase
                          /* 
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.add_circle_outline,
                                  size: 26, color: cs.primary),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const MovimientoCreatePage()),
                                );
                                if (!mounted) return;
                                await _load();
                              },
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Cargar movimiento',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          */

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.event,
                                  size: 26, color: cs.primary),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const EventosPage()),
                                );
                                if (!mounted) return;
                                await _load();
                              },
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Column(
                                  children: [
                                    Text(
                                      'Eventos / Listado Cajas',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.print,
                                  size: 26, color: cs.primary),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const PrinterTestPage()),
                                );
                                if (!mounted) return;
                                await _load();
                              },
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Conexión impresora',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: _usbConnected
                                  ? Colors.green.withValues(alpha: 0.10)
                                  : Colors.red.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _usbConnected
                                    ? Colors.green.withValues(alpha: 0.25)
                                    : Colors.red.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _usbConnected
                                        ? Colors.green
                                        : Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _usbConnected
                                      ? 'Impresora conectada'
                                      : 'Impresora desconectada',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        bottomNavigationBar: _loading
            ? null
            : NavigationBar(
                selectedIndex: 0,
                onDestinationSelected: (i) async {
                  final nav = Navigator.of(context);
                  if (i == 0) return;
                  if (i == 1) {
                    if (_caja == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Abrí una caja para vender')),
                      );
                      return;
                    }
                    await nav.push(
                      MaterialPageRoute(builder: (_) => const BuffetHomePage()),
                    );
                    if (!mounted) return;
                    await _load();
                    return;
                  }
                  if (i == 2) {
                    if (_caja == null) {
                      await nav.push(
                        MaterialPageRoute(builder: (_) => const CajaOpenPage()),
                      );
                    } else {
                      await nav.push(
                        MaterialPageRoute(builder: (_) => const CajaPage()),
                      );
                    }
                    if (!mounted) return;
                    await _load();
                    return;
                  }
                  if (i == 3) {
                    final changed = await nav.push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                    if (!mounted) return;
                    if (changed == true) await _load();
                  }
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.point_of_sale_outlined),
                    selectedIcon: Icon(Icons.point_of_sale),
                    label: 'Ventas',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.store_outlined),
                    selectedIcon: Icon(Icons.store),
                    label: 'Caja',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Ajustes',
                  ),
                ],
              ),
      ),
    );
  }
}
