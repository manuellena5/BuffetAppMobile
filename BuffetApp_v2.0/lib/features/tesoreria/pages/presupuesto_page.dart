import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../services/presupuesto_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla CRUD de partidas presupuestarias anuales.
///
/// Permite definir monto mensual por categoría de ingreso/egreso
/// para una unidad de gestión y año determinados.
class PresupuestoPage extends StatefulWidget {
  const PresupuestoPage({super.key});

  @override
  State<PresupuestoPage> createState() => _PresupuestoPageState();
}

class _PresupuestoPageState extends State<PresupuestoPage> {
  final _service = PresupuestoService.instance;

  int _anio = DateTime.now().year;
  int? _unidadGestionId;
  String? _unidadNombre;
  String _filtroTipo = 'TODOS'; // TODOS | INGRESO | EGRESO

  List<Map<String, dynamic>> _partidas = [];
  Map<String, double> _totales = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      final settings = context.read<AppSettings>();
      _unidadGestionId = settings.unidadGestionActivaId;

      if (_unidadGestionId != null) {
        final db = await AppDatabase.instance();
        final rows = await db.query('unidades_gestion',
            columns: ['nombre'],
            where: 'id=?',
            whereArgs: [_unidadGestionId],
            limit: 1);
        if (rows.isNotEmpty) {
          _unidadNombre = rows.first['nombre']?.toString();
        }
      }
    } catch (_) {}

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (_unidadGestionId == null) {
      setState(() {
        _partidas = [];
        _totales = {};
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final tipo = _filtroTipo == 'TODOS' ? null : _filtroTipo;

      final partidas = await _service.listar(
        unidadGestionId: _unidadGestionId!,
        anio: _anio,
        tipo: tipo,
      );

      final totales = await _service.obtenerTotalesMensuales(
        unidadGestionId: _unidadGestionId!,
        anio: _anio,
      );

      if (mounted) {
        setState(() {
          _partidas = partidas;
          _totales = totales;
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto_page.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar presupuesto. Intente nuevamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TesoreriaScaffold(
      title: 'Presupuesto $_anio',
      currentRouteName: '/presupuesto',
      appBarColor: Colors.teal,
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _mostrarFormulario(),
          tooltip: 'Agregar partida',
        ),
      ],
      body: ResponsiveContainer(
        maxWidth: 900,
        child: Column(
          children: [
            _buildSelectorAnio(),
            if (_unidadNombre != null) _buildUnidadHeader(),
            _buildFiltroTipo(),
            _buildKpis(),
            Expanded(
              child: _loading
                  ? SkeletonLoader.cards(count: 3)
                  : _partidas.isEmpty
                      ? _buildVacio()
                      : _buildLista(),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Selector Año ───────────
  Widget _buildSelectorAnio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _anio--);
              _cargarDatos();
            },
          ),
          Text(
            '$_anio',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _anio >= DateTime.now().year + 1
                ? null
                : () {
                    setState(() => _anio++);
                    _cargarDatos();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() => _anio = DateTime.now().year);
              _cargarDatos();
            },
            tooltip: 'Año actual',
          ),
        ],
      ),
    );
  }

  Widget _buildUnidadHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.purple.shade50,
      child: Text(
        _unidadNombre!,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.purple,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─────────── Filtro Tipo ───────────
  Widget _buildFiltroTipo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'TODOS', label: Text('Todos')),
          ButtonSegment(value: 'INGRESO', label: Text('Ingresos')),
          ButtonSegment(value: 'EGRESO', label: Text('Egresos')),
        ],
        selected: {_filtroTipo},
        onSelectionChanged: (val) {
          setState(() => _filtroTipo = val.first);
          _cargarDatos();
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  // ─────────── KPIs ───────────
  Widget _buildKpis() {
    final ingMensual = _totales['ingresos_mensuales'] ?? 0.0;
    final egrMensual = _totales['egresos_mensuales'] ?? 0.0;
    final saldoMensual = _totales['saldo_mensual'] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _kpi('Ing/Mes', Format.money(ingMensual), Colors.green)),
          const SizedBox(width: 8),
          Expanded(child: _kpi('Egr/Mes', Format.money(egrMensual), Colors.red)),
          const SizedBox(width: 8),
          Expanded(
            child: _kpi(
              'Saldo/Mes',
              Format.money(saldoMensual),
              saldoMensual >= 0 ? Colors.blue : Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _kpi(
              'Anual',
              Format.money(saldoMensual * 12),
              saldoMensual >= 0 ? Colors.blue : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Lista ───────────
  Widget _buildVacio() {
    return EmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: 'No hay partidas presupuestarias',
      action: ElevatedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Agregar partida'),
        onPressed: () => _mostrarFormulario(),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
      ),
    );
  }

  Widget _buildLista() {
    // Separar por tipo
    final ingresos = _partidas.where((p) => p['tipo'] == 'INGRESO').toList();
    final egresos = _partidas.where((p) => p['tipo'] == 'EGRESO').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ingresos.isNotEmpty && _filtroTipo != 'EGRESO') ...[
          _buildSeccion('INGRESOS', Colors.green, ingresos),
          const SizedBox(height: 16),
        ],
        if (egresos.isNotEmpty && _filtroTipo != 'INGRESO') ...[
          _buildSeccion('EGRESOS', Colors.red, egresos),
        ],
      ],
    );
  }

  Widget _buildSeccion(String titulo, Color color, List<Map<String, dynamic>> items) {
    final totalSeccion = items.fold<double>(
      0.0,
      (sum, p) => sum + ((p['monto_mensual'] as num?)?.toDouble() ?? 0.0),
    );

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(
                  titulo == 'INGRESOS' ? Icons.arrow_downward : Icons.arrow_upward,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${Format.money(totalSeccion)}/mes',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                ),
              ],
            ),
          ),
          ...items.map((p) => _buildPartidaItem(p, color)),
        ],
      ),
    );
  }

  Widget _buildPartidaItem(Map<String, dynamic> partida, Color color) {
    final monto = (partida['monto_mensual'] as num?)?.toDouble() ?? 0.0;
    final catNombre = partida['categoria_nombre']?.toString() ?? partida['categoria_codigo']?.toString() ?? '';
    final obs = partida['observacion']?.toString() ?? '';

    return ListTile(
      dense: true,
      title: Text(catNombre, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: obs.isNotEmpty ? Text(obs, style: const TextStyle(fontSize: 12)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${Format.money(monto)}/mes',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'editar', child: Text('Editar')),
              const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
            ],
            onSelected: (accion) {
              if (accion == 'editar') {
                _mostrarFormulario(partida: partida);
              } else if (accion == 'eliminar') {
                _confirmarEliminar(partida);
              }
            },
          ),
        ],
      ),
    );
  }

  // ─────────── Formulario Crear/Editar ───────────
  Future<void> _mostrarFormulario({Map<String, dynamic>? partida}) async {
    if (_unidadGestionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione una unidad de gestión primero.')),
      );
      return;
    }

    final esEdicion = partida != null;
    final montoCtrl = TextEditingController(
      text: esEdicion ? (partida['monto_mensual'] as num?)?.toString() ?? '' : '',
    );
    final obsCtrl = TextEditingController(
      text: esEdicion ? partida['observacion']?.toString() ?? '' : '',
    );

    String tipo = esEdicion ? partida['tipo']?.toString() ?? 'EGRESO' : 'EGRESO';
    String? catCodigo = esEdicion ? partida['categoria_codigo']?.toString() : null;

    // Cargar categorías
    List<Map<String, dynamic>> categorias = [];
    try {
      categorias = await _service.obtenerCategorias(tipo: tipo);
    } catch (_) {}

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();

    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(esEdicion ? 'Editar Partida' : 'Nueva Partida'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!esEdicion) ...[
                        // Tipo
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'INGRESO', label: Text('Ingreso')),
                            ButtonSegment(value: 'EGRESO', label: Text('Egreso')),
                          ],
                          selected: {tipo},
                          onSelectionChanged: (val) async {
                            tipo = val.first;
                            catCodigo = null;
                            try {
                              categorias = await _service.obtenerCategorias(tipo: tipo);
                            } catch (_) {}
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 16),

                        // Categoría
                        DropdownButtonFormField<String>(
                          initialValue: catCodigo,
                          decoration: const InputDecoration(
                            labelText: 'Categoría',
                            border: OutlineInputBorder(),
                          ),
                          items: categorias.map((c) {
                            return DropdownMenuItem<String>(
                              value: c['codigo']?.toString(),
                              child: Text(c['nombre']?.toString() ?? ''),
                            );
                          }).toList(),
                          onChanged: (val) => setDialogState(() => catCodigo = val),
                          validator: (val) => val == null ? 'Seleccione categoría' : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Monto mensual
                      TextFormField(
                        controller: montoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Monto mensual',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Ingrese monto';
                          final n = double.tryParse(val.trim());
                          if (n == null || n < 0) return 'Monto inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Observación
                      TextFormField(
                        controller: obsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Observación (opcional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: Text(esEdicion ? 'Guardar' : 'Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultado != true) return;

    // Guardar
    try {
      final monto = double.parse(montoCtrl.text.trim());
      final obs = obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim();

      if (esEdicion) {
        await _service.actualizar(
          id: partida['id'] as int,
          montoMensual: monto,
          observacion: obs,
        );
      } else {
        await _service.crear(
          unidadGestionId: _unidadGestionId!,
          categoriaCodigo: catCodigo!,
          tipo: tipo,
          anio: _anio,
          montoMensual: monto,
          observacion: obs,
        );
      }

      await _cargarDatos();

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 8),
              Text(esEdicion ? 'Partida Actualizada' : 'Partida Creada'),
            ]),
            content: Text(esEdicion
                ? 'La partida se actualizó correctamente.'
                : 'La partida presupuestaria se creó correctamente.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto_page.guardar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.error, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Error'),
            ]),
            content: const Text('No se pudo guardar la partida. Intente nuevamente.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ─────────── Eliminar ───────────
  Future<void> _confirmarEliminar(Map<String, dynamic> partida) async {
    final catNombre = partida['categoria_nombre']?.toString() ?? '';
    final monto = (partida['monto_mensual'] as num?)?.toDouble() ?? 0.0;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Partida'),
        content: Text('¿Eliminar "$catNombre" (${Format.money(monto)}/mes)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _service.eliminar(partida['id'] as int);
      await _cargarDatos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Partida eliminada.')),
        );
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'presupuesto_page.eliminar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al eliminar. Intente nuevamente.')),
        );
      }
    }
  }
}
