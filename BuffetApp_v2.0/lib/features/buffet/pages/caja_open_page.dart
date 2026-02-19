import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/caja_service.dart';
import '../../shared/format.dart';
import 'buffet_home_page.dart';
import 'bulk_edit_products_page.dart';
import '../../../data/dao/db.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/pages/punto_venta_setup_page.dart';
import '../../tesoreria/pages/unidad_gestion_selector_page.dart';

class CajaOpenPage extends StatefulWidget {
  const CajaOpenPage({super.key});
  @override
  State<CajaOpenPage> createState() => _CajaOpenPageState();
}

class _CajaOpenPageState extends State<CajaOpenPage> {
  final _form = GlobalKey<FormState>();
  final _usuario = TextEditingController(text: '');
  final _fondo = TextEditingController(text: '');
  final _desc = TextEditingController();
  final _obs = TextEditingController();

  // Unidad de Gestión seleccionada para esta caja
  int? _unidadGestionId;
  String? _unidadGestionNombre;
  bool _needsUnidadGestionSetup = false;

  String? _puntoVentaCodigo; // Caj01/Caj02/Caj03
  List<Map<String, String>> _puntos = const []; // {codigo, nombre, alias_caja}
  final _svc = CajaService();
  bool _loading = true;

  @override
  void dispose() {
    _usuario.dispose();
    _fondo.dispose();
    _desc.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkUnidadGestionAndLoad();
  }

  Future<void> _checkUnidadGestionAndLoad() async {
    setState(() => _loading = true);

    try {
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();

      // Siempre mostrar selector de Unidad de Gestión al abrir caja nueva
      // (cada caja debe tener su propia selección)
      setState(() {
        _needsUnidadGestionSetup = true;
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'caja_open.check_unidad_gestion',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _needsUnidadGestionSetup = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _cargarCatalogos() async {
    // Capturar configuración antes del await
    final settings = context.read<AppSettings?>();
    final preferredPv = settings?.puntoVentaCodigo;

    List<Map<String, dynamic>> pv = const [];
    try {
      await settings?.ensureLoaded();
      pv = await _svc.listarPuntosVenta();
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'caja_open.load_catalogs', error: e, stackTrace: st);
    }
    if (!mounted) return;
    setState(() {
      _puntos = pv
          .map((e) => {
                'codigo': (e['codigo'] as String),
                'nombre': (e['nombre'] as String),
                'alias_caja': ((e['alias_caja'] as String?) ?? ''),
              })
          .toList();
      final existsPreferred =
          preferredPv != null && _puntos.any((p) => p['codigo'] == preferredPv);
      // Si no hay PV configurado en el dispositivo, NO autoseleccionamos.
      // Debe configurarse explícitamente.
      _puntoVentaCodigo = existsPreferred ? preferredPv : null;
    });
  }

  Future<void> _abrirSelectorUnidadGestion() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UnidadGestionSelectorPage(isInitialFlow: false),
      ),
    );

    if (result == true && mounted) {
      // Cargar los datos de la unidad seleccionada
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();

      if (settings.unidadGestionActivaId != null) {
        final db = await AppDatabase.instance();
        final rows = await db.rawQuery(
          'SELECT nombre FROM unidades_gestion WHERE id = ?',
          [settings.unidadGestionActivaId],
        );

        if (mounted) {
          setState(() {
            _unidadGestionId = settings.unidadGestionActivaId;
            _unidadGestionNombre =
                rows.isNotEmpty ? rows.first['nombre'] as String? : null;
            _needsUnidadGestionSetup = false;
          });
          await _cargarCatalogos();
        }
      }
    }
  }

  String _pvAliasForSelected() {
    final code = (_puntoVentaCodigo ?? '').trim();
    if (code.isEmpty) return '';
    final row = _puntos.firstWhere(
      (p) => (p['codigo'] ?? '').trim() == code,
      orElse: () => const {'alias_caja': ''},
    );
    return (row['alias_caja'] ?? '').trim();
  }

  Future<void> _showPvRequiredDialog({required bool aliasMissing}) async {
    if (!mounted) return;
    final msg = aliasMissing
        ? 'Para abrir una caja tenés que configurar el Punto de venta y completar el Alias de caja.'
        : 'Para abrir una caja tenés que configurar el Punto de venta.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar Punto de venta'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const PuntoVentaSetupPage()),
              );
              if (!mounted) return;
              if (changed == true) {
                await _cargarCatalogos();
              }
            },
            child: const Text('Configurar ahora'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrir() async {
    if (!_form.currentState!.validate()) return;

    // Validar Unidad de Gestión
    if (_unidadGestionId == null || _unidadGestionNombre == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una Unidad de Gestión')),
      );
      return;
    }

    final fondo = parseLooseDouble(_fondo.text);
    final pvCode = (_puntoVentaCodigo ?? '').trim();

    // PV obligatorio: si no está configurado o falta alias_caja, no se puede abrir.
    if (pvCode.isEmpty) {
      await _showPvRequiredDialog(aliasMissing: false);
      return;
    }
    final aliasCaja = _pvAliasForSelected();
    if (aliasCaja.isEmpty) {
      await _showPvRequiredDialog(aliasMissing: true);
      return;
    }

    try {
      // Verificar si ya hay una caja abierta
      final abierta = await _svc.getCajaAbierta();
      if (abierta != null) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Caja ya abierta'),
            content: Text(
                'Ya existe una caja abierta: ${abierta['codigo_caja']}. Cerrala o usá otra.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
            ],
          ),
        );
        return;
      }

      // Validar si hoy ya existe una caja para la misma Unidad de Gestión.
      // Esto hace que ambas queden bajo el mismo "evento" (fecha + unidad).
      final now = DateTime.now();
      final hoy =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      // Usar nombre de Unidad de Gestión como "disciplina" para compatibilidad
      final disciplina = _unidadGestionNombre ?? 'Otros';
      final existentes =
          await _svc.listarCajasPorEvento(fecha: hoy, disciplina: disciplina);
      if (existentes.isNotEmpty) {
        final codes = existentes
            .map((e) => (e['codigo_caja'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
        final msg = codes.isEmpty
            ? 'Ya existe al menos una caja hoy para "$disciplina".'
            : 'Ya existe${codes.length == 1 ? '' : 'n'} ${codes.length} caja${codes.length == 1 ? '' : 's'} hoy para "$disciplina":\n${codes.join('\n')}';
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Evento ya existente'),
            content: Text(
              '$msg\n\nSi abrís otra caja con la misma fecha y Unidad de Gestión, ambas van a aparecer bajo el mismo evento.\n\n¿Querés abrir igual?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abrir igual'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }

      // --- Modal de confirmación con resumen de datos ---
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 28),
              SizedBox(width: 10),
              Text('Confirmar apertura'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revisá los datos antes de abrir la caja:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _confirmRow('Cajero', _usuario.text.trim()),
              _confirmRow('Fondo inicial', formatCurrency(fondo)),
              _confirmRow('Unidad de Gestión', disciplina),
              _confirmRow('Descripción evento', _desc.text.trim()),
              _confirmRow('Punto de venta', _pvDisplay()),
              if (_obs.text.trim().isNotEmpty)
                _confirmRow('Observación', _obs.text.trim()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar y abrir'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;

      await _svc.abrirCaja(
        usuario: _usuario.text.trim(),
        fondoInicial: fondo,
        disciplina: disciplina,
        descripcionEvento: _desc.text.trim(),
        observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
        puntoVentaCodigo: pvCode,
      );
      if (!mounted) return;
      // Preguntar si desea cargar stock ahora
      final goToStock = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Caja abierta'),
          content: const Text('¿Querés cargar precios y stock ahora?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Ir a ventas')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cargar precios/stock')),
          ],
        ),
      );
      if (!mounted) return;
      if (goToStock == true) {
        // Ir a edición masiva de precios y stock
        // ignore: use_build_context_synchronously
        if (!context.mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const BulkEditProductsPage()));
      } else {
        if (!context.mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const BuffetHomePage()));
      }
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'caja_open.abrir_caja', error: e, stackTrace: st);
      if (!context.mounted) return;
      final msg = e.toString();
      String uiMsg = 'No se pudo abrir la caja.';
      if (msg.contains('UNIQUE') && msg.contains('codigo_caja')) {
        uiMsg =
            'Ya existe una caja con el mismo código para hoy. Probá con otro Punto de venta o disciplina.';
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al abrir caja'),
          content: Text(uiMsg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'))
          ],
        ),
      );
    }
  }

  /// Fila de resumen para el modal de confirmación
  static Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black54)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _pvDisplay() {
    final code = (_puntoVentaCodigo ?? '').trim();
    if (code.isEmpty) return 'Sin configurar';

    final row = _puntos.firstWhere(
      (p) => (p['codigo'] ?? '').trim() == code,
      orElse: () => const {'codigo': '', 'alias_caja': ''},
    );
    final alias = (row['alias_caja'] ?? '').trim();
    return alias.isNotEmpty ? '$code — $alias' : '$code — (sin alias)';
  }

  @override
  Widget build(BuildContext context) {
    // Si necesita seleccionar Unidad de Gestión, mostrar selector
    if (_needsUnidadGestionSetup) {
      return UnidadGestionSelectorPage(
        isInitialFlow: true,
        onComplete: () async {
          final settings = context.read<AppSettings>();
          await settings.ensureLoaded();

          if (settings.unidadGestionActivaId != null) {
            final db = await AppDatabase.instance();
            final rows = await db.rawQuery(
              'SELECT nombre FROM unidades_gestion WHERE id = ?',
              [settings.unidadGestionActivaId],
            );

            if (mounted) {
              setState(() {
                _unidadGestionId = settings.unidadGestionActivaId;
                _unidadGestionNombre =
                    rows.isNotEmpty ? rows.first['nombre'] as String? : null;
                _needsUnidadGestionSetup = false;
              });
              await _cargarCatalogos();
            }
          }
        },
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Apertura de caja')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Apertura de caja')),
      body: LandscapeCenteredBody(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: ListView(
              children: [
                TextFormField(
                  controller: _usuario,
                  decoration:
                      const InputDecoration(labelText: 'Cajero apertura'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _fondo,
                  decoration: const InputDecoration(labelText: 'Fondo inicial'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final val = parseLooseDouble(v ?? '');
                    return (val < 0) ? '>= 0' : null;
                  },
                ),
                const SizedBox(height: 8),
                // Unidad de Gestión (solo lectura + botón modificar)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey(
                            'unidad_gestion_${_unidadGestionNombre ?? ''}'),
                        initialValue: _unidadGestionNombre ?? 'Sin seleccionar',
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de Gestión',
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton(
                        onPressed: _abrirSelectorUnidadGestion,
                        child: const Text('Modificar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _desc,
                  decoration: const InputDecoration(
                    labelText: 'Descripción del evento',
                    hintText: 'Partido vs Piamonte',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('pv_display_${_pvDisplay()}'),
                        initialValue: _pvDisplay(),
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Punto de venta (configurado)',
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton(
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PuntoVentaSetupPage(),
                            ),
                          );
                          if (!mounted) return;
                          if (changed == true) {
                            await _cargarCatalogos();
                          }
                        },
                        child: const Text('Editar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _obs,
                  decoration: const InputDecoration(
                    labelText: 'Observación',
                    hintText: 'No funciona la impresora',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                    onPressed: _abrir, child: const Text('Abrir caja')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
