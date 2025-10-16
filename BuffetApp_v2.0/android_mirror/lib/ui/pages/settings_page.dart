import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
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
    setState(() {
      _layout = v == 'list' ? ProductosLayout.list : ProductosLayout.grid;
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
                RadioListTile<AppThemeMode>(
                  title: const Text('Usar ajustes del dispositivo'),
                  value: AppThemeMode.system,
                  groupValue: temp,
                  onChanged: (v) {
                    setLocal(() => temp = v ?? AppThemeMode.system);
                    Navigator.pop(ctx, temp);
                  },
                ),
                RadioListTile<AppThemeMode>(
                  title: const Text('Desactivado'),
                  value: AppThemeMode.light,
                  groupValue: temp,
                  onChanged: (v) {
                    setLocal(() => temp = v ?? AppThemeMode.light);
                    Navigator.pop(ctx, temp);
                  },
                ),
                RadioListTile<AppThemeMode>(
                  title: const Text('Activado'),
                  value: AppThemeMode.dark,
                  groupValue: temp,
                  onChanged: (v) {
                    setLocal(() => temp = v ?? AppThemeMode.dark);
                    Navigator.pop(ctx, temp);
                  },
                ),
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
              ],
            ),
    );
  }
}
