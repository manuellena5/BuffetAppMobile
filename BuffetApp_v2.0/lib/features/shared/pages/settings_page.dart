import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/responsive_container.dart';
import '../widgets/tesoreria_scaffold.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import '../../../data/dao/db.dart';
import '../services/print_service.dart';
import '../services/usb_printer_service.dart';
import '../state/app_settings.dart';
import '../state/app_mode.dart';
import '../state/drawer_state.dart';
import 'punto_venta_setup_page.dart';
import '../../home/main_menu_page.dart';

enum ProductosLayout { grid, list }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ProductosLayout _layout = ProductosLayout.grid;
  bool _loading = true;
  AppThemeMode _theme = AppThemeMode.system;
  bool _advanced = false;
  double _uiScale = 1.0;

  String? _winPrinterName;
  List<String> _winPrinters = const [];

  bool _dirty = false;
  ProductosLayout _initialLayout = ProductosLayout.grid;
  AppThemeMode _initialTheme = AppThemeMode.system;
  bool _initialAdvanced = false;
  String? _initialWinPrinterName;
  double _initialUiScale = 1.0;

  String _escPosToPreviewText(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      if (b == 0x0A) {
        sb.write('\n');
      } else if (b == 0x0D) {
        // ignorar CR
      } else if (b >= 0x20 && b <= 0x7E) {
        sb.writeCharCode(b);
      } else {
        // ignorar comandos ESC/POS y bytes binarios (logo/raster)
      }
    }
    return sb.toString();
  }

  Future<void> _showEscPosPreviewDialog({
    required String title,
    required Uint8List bytes,
  }) async {
    final text = _escPosToPreviewText(bytes);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '(Sin contenido para previsualizar)' : text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Capturar settings antes de cualquier await para evitar usar context luego
    final settings = context.read<AppSettings?>();
    try {
      await settings?.ensureLoaded();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('productos_layout') ?? 'grid';
    final adv = prefs.getBool('show_advanced_options') ?? false;

    String? winPrinter;
    List<String> winPrinters = const [];
    if (Platform.isWindows) {
      final svc = UsbPrinterService();
      winPrinter = await svc.getDefaultWindowsPrinterName();
      winPrinters = await svc.listWindowsPrinters();
      final saved = winPrinter?.trim() ?? '';
      if (saved.isNotEmpty && !winPrinters.contains(saved)) {
        winPrinters = [saved, ...winPrinters];
      }
    }

    setState(() {
      _layout = v == 'list' ? ProductosLayout.list : ProductosLayout.grid;
      _advanced = adv;
      _winPrinterName = winPrinter;
      _winPrinters = winPrinters;
      _uiScale = (settings?.uiScale ?? (prefs.getDouble('ui_scale') ?? 1.0))
          .toDouble();
      _loading = false;
    });
    // cargar tema actual desde provider (ya capturado antes del await)
    if (settings != null && mounted) setState(() => _theme = settings.theme);

    _initialLayout = _layout;
    _initialAdvanced = _advanced;
    _initialTheme = _theme;
    _initialWinPrinterName = _winPrinterName;
    _initialUiScale = _uiScale;
    _dirty = false;
  }

  void _recomputeDirty() {
    final next = _layout != _initialLayout ||
        _advanced != _initialAdvanced ||
        _theme != _initialTheme ||
        _uiScale != _initialUiScale ||
        (Platform.isWindows && _winPrinterName != _initialWinPrinterName);
    if (next != _dirty) setState(() => _dirty = next);
  }

  Future<void> _showUnsavedChangesModal() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text('Tenés cambios sin guardar. ¿Qué querés hacer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Salir sin guardar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save_exit'),
            child: const Text('Guardar y salir'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'discard') {
      Navigator.pop(context, false);
      return;
    }
    if (action == 'save_exit') {
      await _save();
      return;
    }
  }

  Future<void> _save() async {
    // Capturar dependencias antes de awaits
    final settings = context.read<AppSettings?>();
    final nav = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'productos_layout', _layout == ProductosLayout.list ? 'list' : 'grid');
    await prefs.setBool('show_advanced_options', _advanced);
    // persistir tema
    if (settings != null) {
      await settings.setTheme(_theme);
      await settings.setUiScale(_uiScale);
    } else {
      await prefs.setString('theme_mode', _theme.name);
      await prefs.setDouble('ui_scale', _uiScale);
    }

    if (Platform.isWindows) {
      final svc = UsbPrinterService();
      final selected = _winPrinterName?.trim() ?? '';
      if (selected.isEmpty) {
        await prefs.remove('win_printer_name');
      } else {
        await svc.saveDefaultWindowsPrinter(printerName: selected);
      }
    }
    if (!mounted) return;
    _initialLayout = _layout;
    _initialAdvanced = _advanced;
    _initialTheme = _theme;
    _initialWinPrinterName = _winPrinterName;
    _initialUiScale = _uiScale;
    setState(() => _dirty = false);
    
    // Solo hacer pop si drawer NO está fijo (si está fijo, solo actualizamos dirty state)
    final drawerState = context.read<DrawerState?>();
    if (drawerState == null || !drawerState.isFixed) {
      nav.pop(true);
    }
  }

  String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'Usar ajustes del dispositivo';
      case AppThemeMode.light:
        return 'Desactivado';
      case AppThemeMode.dark:
        return 'Activado';
    }
  }

  Future<void> _pickTheme() async {
    var temp = _theme;
    final picked = await showDialog<AppThemeMode>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Modo oscuro'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: AppThemeMode.system, icon: Icon(Icons.phone)),
                    ButtonSegment(
                        value: AppThemeMode.light,
                        icon: Icon(Icons.light_mode)),
                    ButtonSegment(
                        value: AppThemeMode.dark, icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {temp},
                  onSelectionChanged: (v) {
                    final sel = v.first;
                    setLocal(() => temp = sel);
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, temp),
                  child: const Text('Aplicar'),
                )
              ],
            ),
          );
        });
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _theme = picked;
      });
      _recomputeDirty();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = context.watch<AppSettings?>();
    final modeState = context.watch<AppModeState>();
    final pv = appSettings?.puntoVentaCodigo;
    final alias = appSettings?.aliasDispositivo;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_loading) {
          Navigator.pop(context, false);
          return;
        }
        if (!_dirty) {
          Navigator.pop(context, false);
          return;
        }
        await _showUnsavedChangesModal();
      },
      child: TesoreriaScaffold(
        title: 'Configuraciones',
        currentRouteName: '/settings',
        appBarColor: Colors.grey,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('GUARDAR'),
          ),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ResponsiveContainer(
                maxWidth: 800,
                child: ListView(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    children: [
                  // Cambiar de módulo
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                    child: ListTile(
                      leading: Icon(
                        modeState.isBuffetMode ? Icons.account_balance : Icons.store,
                        color: modeState.isBuffetMode ? Colors.green : Colors.blue,
                      ),
                      title: const Text('Cambiar de módulo'),
                      subtitle: Text(
                        'Actualmente en: ${modeState.isBuffetMode ? "Buffet" : "Tesorería"}',
                      ),
                      trailing: const Icon(Icons.swap_horiz),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        
                        // Confirmar antes de cambiar
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cambiar módulo'),
                            content: Text(
                              'Vas a cambiar al módulo ${modeState.isBuffetMode ? "Tesorería" : "Buffet"}.\n\n'
                              '¿Deseas continuar?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Cambiar'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          // Ir al menú principal
                          nav.pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const MainMenuPage(),
                            ),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Punto de venta (Caja) y dispositivo'),
                    subtitle: Text(
                      (pv == null || pv.trim().isEmpty)
                          ? 'Sin configurar'
                          : '${pv.trim()} • ${(alias ?? '').trim().isEmpty ? 'Alias sin definir' : (alias ?? '').trim()}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final nav = Navigator.of(context);
                      final r = await nav.push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const PuntoVentaSetupPage()),
                      );
                      if (r == true && mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  if (Platform.isWindows) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonFormField<String?>(
                        initialValue: _winPrinterName,
                        decoration: const InputDecoration(
                          labelText: 'Impresora térmica (Windows)',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Sin configurar'),
                          ),
                          ..._winPrinters.map(
                            (p) => DropdownMenuItem<String?>(
                              value: p,
                              child: Text(p),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _winPrinterName = v;
                          _recomputeDirty();
                        }),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final bytes =
                              await PrintService().buildTicketEscPosSample();
                          if (!mounted) return;
                          await _showEscPosPreviewDialog(
                            title: 'Vista previa ticket demo (ESC/POS)',
                            bytes: bytes,
                          );
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text('Vista previa (ticket demo)'),
                      ),
                    ),
                  ],
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<ProductosLayout>(
                      initialValue: _layout,
                      decoration: const InputDecoration(
                        labelText:
                            'Distribución de los artículos en la pantalla de ventas',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ProductosLayout.grid,
                          child: Text('Cuadrícula'),
                        ),
                        DropdownMenuItem(
                          value: ProductosLayout.list,
                          child: Text('Lista'),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _layout = v ?? ProductosLayout.grid;
                        _recomputeDirty();
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final settings = context.read<AppSettings?>();
                        await settings?.ensureLoaded();
                        if (!mounted) return;
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => _VentasGridPreviewPage(
                              initialMinTileWidth:
                                  settings?.winSalesGridMinTileWidth,
                            ),
                          ),
                        );
                        if (changed == true && mounted) {
                          await _load();
                        }
                      },
                      icon: const Icon(Icons.grid_view),
                      label: const Text(
                          'Previsualizar y configurar pantalla de Ventas'),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Modo oscuro'),
                    subtitle: Text(_themeLabel(_theme)),
                    onTap: _pickTheme,
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Zoom de interfaz'),
                            Text('${(_uiScale * 100).round()}%'),
                          ],
                        ),
                        Slider(
                          value: _uiScale.clamp(
                              AppSettings.uiScaleMin, AppSettings.uiScaleMax),
                          min: AppSettings.uiScaleMin,
                          max: AppSettings.uiScaleMax,
                          divisions: ((AppSettings.uiScaleMax -
                                      AppSettings.uiScaleMin) /
                                  0.05)
                              .round(),
                          label: '${(_uiScale * 100).round()}%',
                          onChanged: (v) {
                            setState(() {
                              _uiScale = v;
                              _recomputeDirty();
                            });
                          },
                        ),
                        const Text(
                          'Ajusta el tamaño del texto en toda la app.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('Mostrar opciones avanzadas'),
                    subtitle: const Text('Incluye acceso a logs de errores'),
                    value: _advanced,
                    onChanged: (v) => setState(() {
                      _advanced = v;
                      _recomputeDirty();
                    }),
                  ),
                  if (_advanced) const Divider(),
                  if (_advanced)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mantenimiento de Datos',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.delete_forever),
                            onPressed: _mostrarDialogoPurgar,
                            label: const Text(
                                'Borrar TODAS las cajas y tickets (Irreversible)'),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.restart_alt),
                            onPressed: _mostrarDialogoRestaurarFabrica,
                            label: const Text(
                                'Restaurar de fábrica (Borra TODO y re-inicializa)'),
                          ),
                          const SizedBox(height: 12),
                          const SizedBox.shrink(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }

  Future<void> _mostrarDialogoPurgar() async {
    final cantidadCajas = await AppDatabase.countCajas();
    int segundos = 5;
    bool ejecutando = false;
    Timer? timer;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (segundos > 0) {
              setLocal(() => segundos--);
            } else {
              t.cancel();
            }
          });
          return AlertDialog(
            title: const Text('Confirmar borrado masivo'),
            content: Text(
                'Se eliminarán $cantidadCajas cajas y sus ventas, items, tickets y movimientos asociados. También se limpian eventos de sincronización relacionados. Esta acción es irreversible. ¿Deseas continuar?'),
            actions: [
              TextButton(
                onPressed: ejecutando
                    ? null
                    : () {
                        timer?.cancel();
                        Navigator.pop(ctx);
                      },
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: segundos == 0
                        ? Colors.red.shade700
                        : Colors.red.shade200,
                    foregroundColor: Colors.white),
                onPressed: (segundos == 0 && !ejecutando)
                    ? () async {
                        setLocal(() => ejecutando = true);
                        try {
                          final counts =
                              await AppDatabase.purgeCajasYAsociados();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(counts['caja_diaria'] == 0
                                      ? 'No había cajas para borrar.'
                                      : 'Purgado OK: cajas ${counts['caja_diaria']}, ventas ${counts['ventas']}, tickets ${counts['tickets']}')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al purgar: $e')),
                            );
                          }
                        } finally {
                          timer?.cancel();
                          if (mounted) Navigator.pop(ctx);
                        }
                      }
                    : null,
                child: Text(segundos == 0
                    ? (ejecutando ? 'Ejecutando...' : 'CONFIRMAR')
                    : 'Esperar $segundos s'),
              ),
            ],
          );
        });
      },
    ).then((_) => timer?.cancel());
  }

  Future<void> _mostrarDialogoRestaurarFabrica() async {
    int segundos = 8;
    bool ejecutando = false;
    Timer? timer;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (segundos > 0) {
              setLocal(() => segundos--);
            } else {
              t.cancel();
            }
          });

          return AlertDialog(
            title: const Text('Restaurar de fábrica'),
            content: const Text(
              'Se borrarán TODOS los datos locales (cajas, ventas, tickets, personalización de productos, logs) y se re-inicializarán los catálogos de productos desde fábrica.\n\n'
              'Esta acción es irreversible. ¿Deseas continuar?',
            ),
            actions: [
              TextButton(
                onPressed: ejecutando
                    ? null
                    : () {
                        timer?.cancel();
                        Navigator.pop(ctx);
                      },
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: segundos == 0
                        ? Colors.red.shade900
                        : Colors.red.shade200,
                    foregroundColor: Colors.white),
                onPressed: (segundos == 0 && !ejecutando)
                    ? () async {
                        setLocal(() => ejecutando = true);
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();

                          await AppDatabase.factoryReset();
                          // Fuerza recreación y seeds
                          await AppDatabase.instance();

                          if (!mounted) return;
                          Navigator.pop(ctx); // cerrar el modal antes de salir

                          await showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => AlertDialog(
                              title: const Text('Restauración completa'),
                              content: const Text(
                                'Se borraron los datos locales y se reinicializó la base.\n\n'
                                'La app se cerrará ahora. Volvé a abrirla para continuar.',
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(c);
                                    SystemNavigator.pop();
                                  },
                                  child: const Text('Cerrar app'),
                                ),
                              ],
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al restaurar: $e')),
                          );
                        } finally {
                          timer?.cancel();
                        }
                      }
                    : null,
                child: Text(
                  segundos == 0
                      ? (ejecutando ? 'Ejecutando...' : 'CONFIRMAR')
                      : 'Esperar $segundos s',
                ),
              ),
            ],
          );
        });
      },
    ).then((_) => timer?.cancel());
  }
}

class _VentasGridPreviewPage extends StatefulWidget {
  const _VentasGridPreviewPage({this.initialMinTileWidth});

  final double? initialMinTileWidth;

  @override
  State<_VentasGridPreviewPage> createState() => _VentasGridPreviewPageState();
}

class _VentasGridPreviewPageState extends State<_VentasGridPreviewPage> {
  static const double _min = 140;
  static const double _max = 360;

  double? _minTileWidth;
  ProductosLayout _previewLayout = ProductosLayout.grid;
  /// Para modo lista: 'vertical' (categorías apiladas) o 'columnas' (lado a lado)
  String _listGroupMode = 'vertical';
  List<Map<String, dynamic>> _productos = [];
  bool _loading = true;
  bool _orderDirty = false;

  // Colores por categoría (espejo de BuffetHomePage)
  static const Map<int, MaterialColor> _categorySwatch = {
    1: Colors.orange,
    2: Colors.lightBlue,
  };

  static Color _categoryColor(int? catId) {
    return _categorySwatch[catId] ?? Colors.grey;
  }

  static Color _categoryDarkColor(int? catId) {
    final swatch = _categorySwatch[catId];
    return swatch?.shade700 ?? Colors.grey.shade700;
  }

  static String _categoryName(int? catId) {
    switch (catId) {
      case 1:
        return 'Comida';
      case 2:
        return 'Bebida';
      default:
        return 'Otros';
    }
  }

  @override
  void initState() {
    super.initState();
    _minTileWidth = widget.initialMinTileWidth;
    _loadProducts();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final layout = sp.getString('productos_layout') ?? 'grid';
      final groupMode = sp.getString('list_group_mode') ?? 'vertical';
      if (mounted) {
        setState(() {
          _previewLayout =
              layout == 'list' ? ProductosLayout.list : ProductosLayout.grid;
          _listGroupMode = groupMode;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final db = await AppDatabase.instance();
      final prods = await db.rawQuery(
          'SELECT id, nombre, precio_venta, stock_actual, imagen, categoria_id FROM products WHERE visible=1 ORDER BY orden_visual ASC, id ASC');
      if (mounted) {
        setState(() {
          _productos =
              prods.map((e) => Map<String, dynamic>.from(e)).toList();
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'preview_page.load_products', error: e, stackTrace: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  int _crossAxisCountFor(double width, double uiScale) {
    final s = uiScale <= 0 ? 1.0 : uiScale;
    final effectiveWidth = width / s;

    final minW = (_minTileWidth ?? 0);
    if (minW <= 0) {
      if (effectiveWidth >= 1000) return 5;
      if (effectiveWidth >= 700) return 4;
      if (effectiveWidth >= 500) return 3;
      return 2;
    }
    return (effectiveWidth / minW).floor().clamp(2, 8);
  }

  Future<void> _save() async {
    final settings = context.read<AppSettings?>();
    await settings?.setWinSalesGridMinTileWidth(_minTileWidth);

    // Guardar layout y modo de agrupación
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('productos_layout',
        _previewLayout == ProductosLayout.list ? 'list' : 'grid');
    await prefs.setString('list_group_mode', _listGroupMode);

    // Guardar orden si cambió
    if (_orderDirty) {
      try {
        final db = await AppDatabase.instance();
        for (var i = 0; i < _productos.length; i++) {
          final id = _productos[i]['id'] as int;
          await db.update('products', {'orden_visual': i + 1},
              where: 'id=?', whereArgs: [id]);
        }
      } catch (e, st) {
        await AppDatabase.logLocalError(
            scope: 'preview_page.save_order', error: e, stackTrace: st);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // --- Builders de tarjeta (preview, sin interacción de compra) ---

  Widget _buildPreviewTile(Map<String, dynamic> p) {
    final img = p['imagen'] as String?;
    final name = (p['nombre'] as String?) ?? '';
    final price = p['precio_venta'] as num?;
    final stock = (p['stock_actual'] as int?) ?? 0;
    final catId = p['categoria_id'] as int?;
    final catColor = _categoryColor(catId);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Zona de imagen en gris
            if (img != null && img.isNotEmpty)
              Image.file(File(img), fit: BoxFit.cover)
            else
              Container(color: Colors.grey.shade300),
            // Precio arriba-derecha
            if (price != null)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '\$ ${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // Barra inferior: nombre + stock
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    color: catColor.withValues(alpha: 0.80),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 6),
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (stock != 999)
                    Container(
                      width: double.infinity,
                      color: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Text(
                        'Stock: $stock',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Builders para modo lista (preview) ---

  /// Agrupa productos por categoría respetando el orden actual en _productos
  Map<int, List<Map<String, dynamic>>> _groupByCategory() {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final p in _productos) {
      final catId = (p['categoria_id'] as int?) ?? 0;
      grouped.putIfAbsent(catId, () => []).add(p);
    }
    return grouped;
  }

  List<int> _sortedCategoryKeys(Map<int, List<Map<String, dynamic>>> grouped) {
    return grouped.keys.toList()
      ..sort((a, b) {
        const order = {1: 0, 2: 1};
        return (order[a] ?? 99).compareTo(order[b] ?? 99);
      });
  }

  /// Reordena un producto dentro de su categoría y actualiza _productos global
  void _reorderInCategory(int catId, int oldIndex, int newIndex) {
    // Obtener los productos de esta categoría (en el orden actual de _productos)
    final catProducts = _productos
        .where((p) => ((p['categoria_id'] as int?) ?? 0) == catId)
        .toList();
    if (oldIndex < 0 || oldIndex >= catProducts.length) return;
    if (newIndex > catProducts.length) newIndex = catProducts.length;
    if (oldIndex < newIndex) newIndex--;
    if (oldIndex == newIndex) return;

    final movedItem = catProducts.removeAt(oldIndex);
    catProducts.insert(newIndex, movedItem);

    // Reconstruir _productos manteniendo el orden inter-categorías pero
    // con el nuevo orden intra-categoría
    final newList = <Map<String, dynamic>>[];
    final grouped = _groupByCategory();
    final keys = _sortedCategoryKeys(grouped);
    for (final k in keys) {
      if (k == catId) {
        newList.addAll(catProducts);
      } else {
        newList.addAll(grouped[k]!);
      }
    }
    setState(() {
      _productos = newList;
      _orderDirty = true;
    });
  }

  Widget _buildPreviewListVertical() {
    final grouped = _groupByCategory();
    final sortedKeys = _sortedCategoryKeys(grouped);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      children: [
        for (final catId in sortedKeys) ...[
          _buildCategoryHeader(catId),
          _buildReorderableCategoryList(catId, grouped[catId]!),
        ],
      ],
    );
  }

  Widget _buildPreviewListColumns() {
    final grouped = _groupByCategory();
    final sortedKeys = _sortedCategoryKeys(grouped);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sortedKeys.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildCategoryHeader(sortedKeys[i]),
                ),
                Expanded(
                  child: _buildReorderableCategoryList(
                      sortedKeys[i], grouped[sortedKeys[i]]!),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Widget reordenable para una categoría individual
  Widget _buildReorderableCategoryList(
      int catId, List<Map<String, dynamic>> products) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: products.length,
      onReorder: (oldIndex, newIndex) =>
          _reorderInCategory(catId, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            color: Colors.transparent,
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (ctx, j) {
        final p = products[j];
        final key = ValueKey('cat${catId}_prod${p['id']}');
        return Column(
          key: key,
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: j,
              child: _buildListItem(p, showDragHandle: true),
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _buildCategoryHeader(int catId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: _categoryColor(catId).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: _categoryColor(catId),
            width: 4,
          ),
        ),
      ),
      child: Text(
        _categoryName(catId),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: _categoryDarkColor(catId),
        ),
      ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> p,
      {bool showDragHandle = false}) {
    final stock = (p['stock_actual'] as int?) ?? 0;
    return ListTile(
      leading: _buildLeadingImage(p),
      title: Text(p['nombre'] as String? ?? '',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        Text(
          '\$ ${(p['precio_venta'] as num?)?.toStringAsFixed(0) ?? '0'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(width: 12),
        if (stock != 999)
          Text('Stock: $stock',
              style: TextStyle(color: Colors.grey.shade700)),
      ]),
      trailing: showDragHandle
          ? Icon(Icons.drag_handle, color: Colors.grey.shade400)
          : null,
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings?>();
    final uiScale = settings?.uiScale ?? 1.0;

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = _crossAxisCountFor(width, uiScale);
    final label =
        _minTileWidth == null ? 'Automático' : '${_minTileWidth!.round()} px';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsualización: Ventas'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('GUARDAR'),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Selector de modo ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<ProductosLayout>(
              segments: const [
                ButtonSegment(
                  value: ProductosLayout.grid,
                  icon: Icon(Icons.grid_view),
                  label: Text('Cuadrícula'),
                ),
                ButtonSegment(
                  value: ProductosLayout.list,
                  icon: Icon(Icons.view_list),
                  label: Text('Lista'),
                ),
              ],
              selected: {_previewLayout},
              onSelectionChanged: (v) {
                setState(() => _previewLayout = v.first);
              },
            ),
          ),

          // --- Controles específicos del modo ---
          if (_previewLayout == ProductosLayout.grid) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Tamaño de tarjetas')),
                      Text(label,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: (_minTileWidth ?? 220).clamp(_min, _max),
                    min: _min,
                    max: _max,
                    divisions: ((_max - _min) / 10).round(),
                    label: label,
                    onChanged: (v) => setState(() => _minTileWidth = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Columnas: $crossAxisCount',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _minTileWidth = null),
                        child: const Text('Restablecer'),
                      ),
                    ],
                  ),
                  Text(
                    'Tip: mantené presionado un producto y arrastralo para reordenarlo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agrupación de categorías',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'vertical',
                        icon: Icon(Icons.view_agenda),
                        label: Text('Vertical'),
                      ),
                      ButtonSegment(
                        value: 'columnas',
                        icon: Icon(Icons.view_column),
                        label: Text('Columnas'),
                      ),
                    ],
                    selected: {_listGroupMode},
                    onSelectionChanged: (v) {
                      setState(() => _listGroupMode = v.first);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _listGroupMode == 'vertical'
                        ? 'Las categorías se muestran una debajo de otra.'
                        : 'Las categorías se muestran una al lado de otra en columnas.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tip: arrastrá el ícono ☰ de cada producto para reordenarlo dentro de su categoría.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          // --- Preview ---
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _productos.isEmpty
                    ? const Center(
                        child: Text('No hay productos visibles'))
                    : _previewLayout == ProductosLayout.grid
                        ? _buildGridPreview(crossAxisCount)
                        : _listGroupMode == 'columnas'
                            ? _buildPreviewListColumns()
                            : _buildPreviewListVertical(),
          ),
        ],
      ),
    );
  }

  Widget _buildGridPreview(int crossAxisCount) {
    // Grid con drag-and-drop para reordenar productos
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _productos.length,
      itemBuilder: (ctx, i) {
        final p = _productos[i];
        return LongPressDraggable<int>(
          data: i,
          feedback: SizedBox(
            width: 120,
            height: 120,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: Opacity(
                opacity: 0.85,
                child: _buildPreviewTile(p),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildPreviewTile(p),
          ),
          child: DragTarget<int>(
            onAcceptWithDetails: (details) {
              final fromIndex = details.data;
              if (fromIndex != i) {
                setState(() {
                  final item = _productos.removeAt(fromIndex);
                  _productos.insert(i, item);
                  _orderDirty = true;
                });
              }
            },
            onWillAcceptWithDetails: (details) => details.data != i,
            builder: (ctx, candidateData, rejectedData) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  border: candidateData.isNotEmpty
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildPreviewTile(p),
              );
            },
          ),
        );
      },
    );
  }
}
