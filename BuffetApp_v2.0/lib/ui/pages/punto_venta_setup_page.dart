import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../data/dao/db.dart';
import '../../services/caja_service.dart';
import '../state/app_settings.dart';
import 'home_page.dart';
import 'pos_main_page.dart';

class PuntoVentaSetupPage extends StatefulWidget {
  final bool initialFlow;
  const PuntoVentaSetupPage({super.key, this.initialFlow = false});

  @override
  State<PuntoVentaSetupPage> createState() => _PuntoVentaSetupPageState();
}

class _PuntoVentaSetupPageState extends State<PuntoVentaSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _aliasCtrl = TextEditingController();
  final _aliasCajaCtrl = TextEditingController();
  final _svc = CajaService();

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _dirtyListenersAttached = false;

  String? _initialPv;
  String _initialAlias = '';
  String _initialAliasCaja = '';
  String? _puntoVentaCodigo;
  List<Map<String, String?>> _puntos = const []; // {codigo, nombre, alias_caja}

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _aliasCajaCtrl.dispose();
    super.dispose();
  }

  void _attachDirtyListenersIfNeeded() {
    if (_dirtyListenersAttached) return;
    _dirtyListenersAttached = true;
    _aliasCtrl.addListener(_recomputeDirty);
    _aliasCajaCtrl.addListener(_recomputeDirty);
  }

  void _recomputeDirty() {
    if (!mounted) return;
    if (_loading) return;
    final pv = (_puntoVentaCodigo ?? '').trim();
    final alias = _aliasCtrl.text.trim();
    final aliasCaja = _aliasCajaCtrl.text.trim();
    final next = (pv != (_initialPv ?? '').trim()) ||
        (alias != _initialAlias) ||
        (aliasCaja != _initialAliasCaja);
    if (next != _dirty) setState(() => _dirty = next);
  }

  Future<bool> _confirmarSalirConCambios() async {
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

    if (action == 'save_exit') {
      await _guardar();
      return false; // _guardar navega/pop por su cuenta
    }
    if (action == 'discard') {
      if (widget.initialFlow) {
        await SystemNavigator.pop();
        return false;
      }
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    // Capturar settings antes del await
    final settings = context.read<AppSettings?>();
    final configuredPv = settings?.puntoVentaCodigo;
    final configuredAlias = settings?.aliasDispositivo;

    List<Map<String, dynamic>> pv = const [];
    try {
      await settings?.ensureLoaded();
      pv = await _svc.listarPuntosVenta();
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'pv_setup.load', error: e, stackTrace: st);
    }

    final puntos = pv
        .map((e) => {
              'codigo': (e['codigo'] as String),
              'nombre': (e['nombre'] as String),
              'alias_caja': (e['alias_caja'] as String?),
            })
        .toList();

    String? selected = configuredPv;
    if (selected == null || selected.trim().isEmpty) {
      selected = puntos.isNotEmpty ? puntos.first['codigo'] : null;
    } else {
      final exists = puntos.any((p) => p['codigo'] == selected);
      if (!exists) selected = puntos.isNotEmpty ? puntos.first['codigo'] : selected;
    }

    String alias = (configuredAlias ?? '').trim();
    if (alias.isEmpty) {
      alias = await _suggestDeviceAlias();
    }

    if (!mounted) return;
    setState(() {
      _puntos = puntos;
      _puntoVentaCodigo = selected;
      _aliasCtrl.text = alias;
      final sel = selected;
      final aliasCaja = sel == null
          ? ''
          : (puntos
                  .firstWhere(
                    (p) => p['codigo'] == sel,
                    orElse: () => const {'alias_caja': ''},
                  )['alias_caja'] ??
              '');
      _aliasCajaCtrl.text = aliasCaja.trim();
      _loading = false;
    });

    _initialPv = (_puntoVentaCodigo ?? '').trim();
    _initialAlias = _aliasCtrl.text.trim();
    _initialAliasCaja = _aliasCajaCtrl.text.trim();
    _dirty = false;
    _attachDirtyListenersIfNeeded();
  }

  Future<String> _suggestDeviceAlias() async {
    try {
      final info = DeviceInfoPlugin();
      final pkg = await PackageInfo.fromPlatform();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final brand = (a.brand).trim();
        final model = (a.model).trim();
        final short = [brand, model].where((s) => s.isNotEmpty).join(' ');
        return short.isEmpty ? 'Android • app ${pkg.version}' : '$short • app ${pkg.version}';
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        final name = (i.name).trim();
        final model = (i.utsname.machine).trim();
        final short = [name, model].where((s) => s.isNotEmpty).join(' ');
        return short.isEmpty ? 'iOS • app ${pkg.version}' : '$short • app ${pkg.version}';
      }
      return '${Platform.operatingSystem} • app ${pkg.version}';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  Future<void> _guardar() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final pv = (_puntoVentaCodigo ?? '').trim();
    final alias = _aliasCtrl.text.trim();
    final aliasCaja = _aliasCajaCtrl.text.trim();

    setState(() => _saving = true);
    try {
      await context.read<AppSettings>().setPuntoVentaConfig(
            puntoVentaCodigo: pv,
            aliasDispositivo: alias,
          );

      // Persistir alias de caja por punto_venta
      try {
        final db = await AppDatabase.instance();
        await db.update(
          'punto_venta',
          {'alias_caja': aliasCaja.isEmpty ? null : aliasCaja},
          where: 'codigo = ?',
          whereArgs: [pv],
        );
      } catch (e, st) {
        await AppDatabase.logLocalError(
            scope: 'pv_setup.save_alias_caja', error: e, stackTrace: st);
      }

      if (!mounted) return;

      if (widget.initialFlow) {
        // Re-evaluar si hay caja abierta para respetar el flujo actual.
        try {
          final caja = await CajaService().getCajaAbierta();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => caja == null ? const HomePage() : const PosMainPage()),
          );
        } catch (e, st) {
          await AppDatabase.logLocalError(scope: 'pv_setup.after_save', error: e, stackTrace: st);
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
        }
      } else {
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(scope: 'pv_setup.save', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la configuración: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmarCambioCodigoCaja({required String from, required String to}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar código de caja'),
        content: Text(
          'Vas a cambiar el código de caja de "$from" a "$to".\n\n'
          'Importante: este código NO debe repetirse en otros dispositivos, para evitar mezclar datos entre cajas.\n\n'
          '¿Confirmás el cambio?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_dirty) {
          Navigator.pop(context);
          return;
        }
        final shouldPop = await _confirmarSalirConCambios();
        if (shouldPop && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Punto de venta'),
        actions: [
          TextButton(
            onPressed: (_loading || _saving) ? null : _guardar,
            child: const Text('GUARDAR'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _puntoVentaCodigo,
                      decoration: const InputDecoration(
                        labelText: 'Código de caja (Punto de venta)',
                        helperText:
                            'Importante: no repitas este código en otros dispositivos (evita mezclar cajas).',
                        helperMaxLines: 3,
                      ),
                      items: _puntos
                          .map(
                            (p) => DropdownMenuItem<String>(
                              value: p['codigo'],
                              child: Text('${p['codigo']} — ${p['nombre']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) async {
                        final vv = v;
                        if (vv == null) return;

                        final current = (_puntoVentaCodigo ?? '').trim();
                        final next = vv.trim();
                        if (current.isNotEmpty && next == current) return;

                        if (settings.isPuntoVentaConfigured && current.isNotEmpty) {
                          final ok = await _confirmarCambioCodigoCaja(from: current, to: next);
                          if (!ok) return;
                        }

                        final aliasCaja = (_puntos
                                    .firstWhere(
                                      (p) => p['codigo'] == vv,
                                      orElse: () => const {'alias_caja': ''},
                                    )['alias_caja'] ??
                                '')
                            .toString();

                        if (!mounted) return;
                        setState(() {
                          _puntoVentaCodigo = vv;

                        _recomputeDirty();
                          _aliasCajaCtrl.text = aliasCaja.trim();
                        });
                      },
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Seleccioná un punto de venta';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _aliasCajaCtrl,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Alias de caja',
                        hintText: 'Ej: Barra principal',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Ingresá un alias de caja';
                        if (s.length > 100) return 'Máximo 100 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _aliasCtrl,
                      decoration: const InputDecoration(
                        labelText: 'AliasDispositivo',
                        hintText: 'Ej: Lenovo Caja1',
                      ),
                      textInputAction: TextInputAction.done,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Ingresá un alias para identificar el dispositivo';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (settings.isPuntoVentaConfigured)
                      Text(
                        'Configuración actual: ${settings.puntoVentaCodigo} • ${settings.aliasDispositivo}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_loading || _saving) ? null : _guardar,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Guardando…' : 'Guardar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ));
  }
}
