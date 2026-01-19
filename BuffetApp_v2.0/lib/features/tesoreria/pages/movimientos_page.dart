import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/services/movimiento_service.dart';
import '../../buffet/services/caja_service.dart';
import '../../shared/format.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../shared/state/app_settings.dart';
import '../services/categoria_movimiento_service.dart';

class MovimientosPage extends StatefulWidget {
  final int cajaId;
  const MovimientosPage({super.key, required this.cajaId});
  @override
  State<MovimientosPage> createState() => _MovimientosPageState();
}

class MovimientoCreatePage extends StatefulWidget {
  const MovimientoCreatePage({super.key});

  @override
  State<MovimientoCreatePage> createState() => _MovimientoCreatePageState();
}

class _MovimientoCreatePageState extends State<MovimientoCreatePage> {
  final _svc = EventoMovimientoService();

  String _tipo = 'INGRESO';
  String? _codigoCategoria;
  final _montoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _metodosPago = const [];
  List<Map<String, dynamic>> _categorias = [];
  int? _medioPagoId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.query('metodos_pago', orderBy: 'id ASC');
      await _cargarCategorias();
      setState(() {
        _metodosPago = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        _medioPagoId =
            _metodosPago.isNotEmpty ? (_metodosPago.first['id'] as int?) : null;
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'mov_ext.load', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _cargarCategorias() async {
    try {
      final cats = await CategoriaMovimientoService.obtenerCategoriasPorTipo(tipo: _tipo);
      setState(() {
        _categorias = cats;
        // Verificar si la categoría actual sigue siendo válida
        if (_codigoCategoria != null) {
          final esValida = _categorias.any((cat) => cat['codigo'] == _codigoCategoria);
          if (!esValida) {
            _codigoCategoria = null; // Limpiar si no es válida
          }
        }
      });
    } catch (e) {
      // Error silencioso, categorías opcionales
    }
  }

  Future<String?> _disciplinaNombre(int disciplinaId) async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.query('disciplinas',
          columns: ['nombre'],
          where: 'id=?',
          whereArgs: [disciplinaId],
          limit: 1);
      if (rows.isEmpty) return null;
      return (rows.first['nombre'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardar() async {
    final settings = context.read<AppSettings>();
    final disciplinaId = settings.disciplinaActivaId;
    if (disciplinaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Seleccioná una subcomisión (Eventos)')));
      return;
    }
    final monto =
        double.tryParse(_montoCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monto debe ser > 0')));
      return;
    }
    if (_medioPagoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccioná un medio de pago')));
      return;
    }

    setState(() => _saving = true);
    try {
      await _svc.crear(
        disciplinaId: disciplinaId,
        eventoId: settings.eventoActivoId,
        tipo: _tipo,
        categoria: _codigoCategoria,
        monto: monto,
        medioPagoId: _medioPagoId!,
        observacion: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Movimiento guardado')));
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'mov_ext.save', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final disciplinaId = settings.disciplinaActivaId;

    return Scaffold(
      appBar: AppBar(title: const Text('Cargar movimiento')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Contexto',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(height: 6),
                          if (disciplinaId == null)
                            const Text('Subcomisión: sin seleccionar')
                          else
                            FutureBuilder<String?>(
                              future: _disciplinaNombre(disciplinaId),
                              builder: (ctx, snap) {
                                final nombre = snap.data ?? '...';
                                return Text('Subcomisión: $nombre');
                              },
                            ),
                          const SizedBox(height: 2),
                          Text(
                            settings.eventoActivoId == null
                                ? 'Evento: sin evento'
                                : 'Evento: ${settings.eventoActivoFecha ?? ''}${settings.eventoActivoEsEspecial ? ' (sin partido)' : ''}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (disciplinaId == null) ...[
                    const Text(
                        'Para cargar movimientos, primero elegí una subcomisión desde Eventos.'),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.event),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Ir a Eventos'),
                        ),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: _tipo,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: const [
                        DropdownMenuItem(
                            value: 'INGRESO', child: Text('Ingreso')),
                        DropdownMenuItem(
                            value: 'EGRESO', child: Text('Egreso')),
                      ],
                      onChanged: (v) {
                        setState(() => _tipo = v ?? 'INGRESO');
                        _cargarCategorias();
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _codigoCategoria,
                      decoration: const InputDecoration(
                        labelText: 'Categoría (opcional)',
                        hintText: 'Seleccionar categoría',
                      ),
                      items: _categorias.map((cat) {
                        final codigo = cat['codigo'] as String;
                        final nombre = cat['nombre'] as String;
                        return DropdownMenuItem<String>(
                          value: codigo,
                          child: Text('$nombre ($codigo)'),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _codigoCategoria = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _montoCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Monto'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: _medioPagoId,
                      decoration:
                          const InputDecoration(labelText: 'Medio de pago'),
                      items: _metodosPago
                          .map((m) => DropdownMenuItem<int>(
                                value: m['id'] as int,
                                child:
                                    Text((m['descripcion'] ?? '').toString()),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _medioPagoId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _obsCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Observación (opcional)'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _guardar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Guardar',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _MovimientosPageState extends State<MovimientosPage> {
  final _svc = MovimientoService();
  final _cajaSvc = CajaService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  Map<String, dynamic>? _caja;
  Map<String, double> _totales = {'ingresos': 0, 'retiros': 0};

  static const _tileTitleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.black,
  );

  static const _tileObsStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  static const _tileDateStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );

  String _formatCreatedTs(dynamic v) {
    try {
      DateTime dt;
      if (v == null) return '';
      if (v is int) {
        var ms = v;
        if (ms < 1000000000000) ms = ms * 1000; // segundos -> ms
        dt = DateTime.fromMillisecondsSinceEpoch(ms);
      } else if (v is num) {
        var ms = v.toInt();
        if (ms < 1000000000000) ms = ms * 1000;
        dt = DateTime.fromMillisecondsSinceEpoch(ms);
      } else if (v is String) {
        final s = v.trim();
        final asInt = int.tryParse(s);
        if (asInt != null) {
          var ms = asInt;
          if (ms < 1000000000000) ms = ms * 1000;
          dt = DateTime.fromMillisecondsSinceEpoch(ms);
        } else if (RegExp(r"\d{4}-\d{2}-\d{2}").hasMatch(s)) {
          dt = DateTime.tryParse(s) ?? DateTime.now();
        } else {
          return s;
        }
      } else {
        return v.toString();
      }
      return DateFormat('dd/MM/yyyy HH:mm', 'es_AR').format(dt);
    } catch (_) {
      return v?.toString() ?? '';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic>? caja;
    List<Map<String, dynamic>> rows = [];
    Map<String, double> tot = {'ingresos': 0, 'retiros': 0};
    try {
      caja = await _cajaSvc.getCajaById(widget.cajaId);
      rows = await _svc.listarPorCaja(widget.cajaId);
      tot = await _svc.totalesPorCaja(widget.cajaId);
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'movimientos_page.load',
          error: e,
          stackTrace: st,
          payload: {'cajaId': widget.cajaId});
    }
    setState(() {
      _caja = caja;
      _rows = rows;
      _totales = tot;
      _loading = false;
    });
  }

  void _nuevo() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _MovimientoDialog(cajaId: widget.cajaId));
    if (ok == true) _load();
  }

  void _editar(Map<String, dynamic> mov) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MovimientoDialog(
        cajaId: widget.cajaId,
        movimiento: mov,
      ),
    );
    if (ok == true) _load();
  }

  void _eliminar(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: const Text('¿Desea eliminar el movimiento seleccionado?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm == true) {
      await _svc.eliminar(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Movimiento eliminado')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final caja = _caja;
    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos de Caja')),
      floatingActionButton: (_caja != null && (caja!['estado'] == 'ABIERTA'))
          ? FloatingActionButton(
              onPressed: _nuevo,
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (caja != null) ...[
                    Text(
                        'Caja: ${caja['codigo_caja']} • Estado: ${caja['estado']}'),
                    const SizedBox(height: 4),
                    Text(
                        'Ingresos: ${formatCurrency(_totales['ingresos'] ?? 0)}  •  Retiros: ${formatCurrency(_totales['retiros'] ?? 0)}'),
                    const Divider(height: 20),
                  ],
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('Sin movimientos registrados')),
                    )
                  else
                    ..._rows.map((m) {
                      final tipo = (m['tipo'] ?? '').toString();
                      final monto = (m['monto'] as num?)?.toDouble() ?? 0;
                      final obs = (m['observacion'] as String?) ?? '';
                      final fecha = _formatCreatedTs(m['created_ts']);
                      final color = tipo == 'INGRESO'
                          ? Colors.green.shade200
                          : Colors.red.shade200;
                      final canEdit =
                          (caja != null && caja['estado'] == 'ABIERTA');
                      return Card(
                        color: color,
                        child: ListTile(
                          title: Text(
                            '$tipo: ${formatCurrency(monto)}',
                            style: _tileTitleStyle,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (obs.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 2, bottom: 2),
                                  child: Text(obs, style: _tileObsStyle),
                                ),
                              Text(fecha, style: _tileDateStyle),
                            ],
                          ),
                          trailing: canEdit
                              ? PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _editar(m);
                                    if (v == 'del') _eliminar(m['id'] as int);
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                        value: 'edit', child: Text('Editar')),
                                    const PopupMenuItem(
                                        value: 'del', child: Text('Eliminar')),
                                  ],
                                )
                              : null,
                          onTap: canEdit ? () => _editar(m) : null,
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _MovimientoDialog extends StatefulWidget {
  final int cajaId;
  final Map<String, dynamic>? movimiento;
  const _MovimientoDialog({required this.cajaId, this.movimiento});
  @override
  State<_MovimientoDialog> createState() => _MovimientoDialogState();
}

class _MovimientoDialogState extends State<_MovimientoDialog> {
  final _svc = MovimientoService();
  late String _tipo;
  final _monto = TextEditingController();
  final _obs = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final mov = widget.movimiento;
    _tipo = (mov != null ? mov['tipo'] : 'INGRESO') ?? 'INGRESO';
    if (mov != null) {
      _monto.text =
          ((mov['monto'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
      _obs.text = (mov['observacion'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    _monto.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monto debe ser > 0')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.movimiento == null) {
        await _svc.crear(
            cajaId: widget.cajaId,
            tipo: _tipo,
            monto: monto,
            observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim());
      } else {
        await _svc.actualizar(
            id: widget.movimiento!['id'] as int,
            tipo: _tipo,
            monto: monto,
            observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim());
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'movimientos_dialog.save',
          error: e,
          stackTrace: st,
          payload: {'cajaId': widget.cajaId});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.movimiento == null ? 'Nuevo movimiento' : 'Editar movimiento'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            items: const [
              DropdownMenuItem(value: 'INGRESO', child: Text('Ingreso')),
              DropdownMenuItem(value: 'RETIRO', child: Text('Retiro')),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? 'INGRESO'),
            decoration: const InputDecoration(labelText: 'Tipo'),
          ),
          TextField(
            controller: _monto,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Monto'),
          ),
          TextField(
            controller: _obs,
            decoration:
                const InputDecoration(labelText: 'Observación (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _guardar,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
