import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../data/dao/db.dart';
import '../state/app_settings.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Capturar settings antes de cualquier await para evitar usar context luego
    final settings = context.read<AppSettings?>();
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('productos_layout') ?? 'grid';
    final adv = prefs.getBool('show_advanced_options') ?? false;
    setState(() {
      _layout = v == 'list' ? ProductosLayout.list : ProductosLayout.grid;
      _advanced = adv;
      _loading = false;
    });
    // cargar tema actual desde provider (ya capturado antes del await)
    if (settings != null && mounted) setState(() => _theme = settings.theme);
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
    } else {
      await prefs.setString('theme_mode', _theme.name);
    }
    if (!mounted) return;
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
                        value: AppThemeMode.light, icon: Icon(Icons.light_mode)),
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
      setState(() => _theme = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuraciones'), actions: [
        TextButton(
            onPressed: _loading ? null : _save, child: const Text('GUARDAR')),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              children: [
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
                    onChanged: (v) =>
                        setState(() => _layout = v ?? ProductosLayout.grid),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Modo oscuro'),
                  subtitle: Text(_themeLabel(_theme)),
                  onTap: _pickTheme,
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('Mostrar opciones avanzadas'),
                  subtitle: const Text('Incluye acceso a logs de errores'),
                  value: _advanced,
                  onChanged: (v) => setState(() => _advanced = v),
                ),
                if (_advanced) const Divider(),
                if (_advanced)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mantenimiento de Datos', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.delete_forever),
                          onPressed: _mostrarDialogoPurgar,
                          label: const Text('Borrar TODAS las cajas y tickets (Irreversible)'),
                        ),
                        const SizedBox(height: 12),
                        SizedBox.shrink(),
                      ],
                    ),
                  ),
              ],
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
              'Se eliminarán $cantidadCajas cajas y sus ventas, items, tickets y movimientos asociados. También se limpian eventos de sincronización relacionados. Esta acción es irreversible. ¿Deseas continuar?'
            ),
            actions: [
              TextButton(
                onPressed: ejecutando ? null : () {
                  timer?.cancel();
                  Navigator.pop(ctx);
                },
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: segundos == 0 ? Colors.red.shade700 : Colors.red.shade200,
                ),
                onPressed: (segundos == 0 && !ejecutando) ? () async {
                  setLocal(() => ejecutando = true);
                  try {
                    final counts = await AppDatabase.purgeCajasYAsociados();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(
                          counts['caja_diaria'] == 0
                            ? 'No había cajas para borrar.'
                            : 'Purgado OK: cajas ${counts['caja_diaria']}, ventas ${counts['ventas']}, tickets ${counts['tickets']}'
                        )),
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
                } : null,
                child: Text(segundos == 0 ? (ejecutando ? 'Ejecutando...' : 'CONFIRMAR') : 'Esperar $segundos s'),
              ),
            ],
          );
        });
      },
    ).then((_) => timer?.cancel());
  }
}
