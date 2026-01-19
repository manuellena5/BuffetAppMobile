import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/responsive_container.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import '../../../data/dao/db.dart';
import '../services/print_service.dart';
import '../services/usb_printer_service.dart';
import '../state/app_settings.dart';
import '../state/app_mode.dart';
import 'punto_venta_setup_page.dart';
import '../../home/mode_selector_page.dart';

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
    _dirty = false;
    nav.pop(true);
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
      child: Scaffold(
        appBar: AppBar(title: const Text('Configuraciones'), actions: [
          TextButton(
              onPressed: _loading ? null : _save, child: const Text('GUARDAR')),
        ]),
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
                        
                        if (confirm == true && mounted) {
                          // Ir al selector de modo
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const ModeSelectorPage(),
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
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final settings = context.read<AppSettings?>();
                          await settings?.ensureLoaded();
                          if (!mounted) return;
                          await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => _VentasGridPreviewPage(
                                initialMinTileWidth:
                                    settings?.winSalesGridMinTileWidth,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.grid_view),
                        label: const Text(
                            'Previsualizar pantalla de Ventas (tarjetas)'),
                      ),
                    ),
                  ],
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

  @override
  void initState() {
    super.initState();
    _minTileWidth = widget.initialMinTileWidth;
  }

  int _crossAxisCountFor(double width, double uiScale) {
    final s = uiScale <= 0 ? 1.0 : uiScale;
    final effectiveWidth = width / s;

    final minW = (_minTileWidth ?? 0);
    if (minW <= 0) {
      // Fallback legacy (igual que en BuffetHomePage)
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
    if (!mounted) return;
    Navigator.of(context).pop(true);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Tamaño de tarjetas (Windows)'),
                    ),
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Slider(
                  value: (_minTileWidth ?? 220).clamp(_min, _max),
                  min: _min,
                  max: _max,
                  divisions: ((_max - _min) / 10).round(),
                  label: label,
                  onChanged: (v) {
                    setState(() {
                      _minTileWidth = v;
                    });
                  },
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
                      onPressed: () => setState(() => _minTileWidth = null),
                      child: const Text('Restablecer'),
                    ),
                  ],
                ),
                Text(
                  'Tip: esto sólo cambia el tamaño de la cuadrícula de productos (no el zoom general).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: 18,
              itemBuilder: (ctx, i) {
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.grey.shade300),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Colors.green.shade700.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            r'$ 999',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 6),
                          child: Text(
                            'Producto ${i + 1}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
