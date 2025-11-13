import 'package:flutter/material.dart';
import '../../services/movimiento_service.dart';
import '../../services/caja_service.dart';
import '../format.dart';
import 'package:intl/intl.dart';
import '../../data/dao/db.dart';

class MovimientosPage extends StatefulWidget {
  final int cajaId;
  const MovimientosPage({super.key, required this.cajaId});
  @override
  State<MovimientosPage> createState() => _MovimientosPageState();
}

class _MovimientosPageState extends State<MovimientosPage> {
  final _svc = MovimientoService();
  final _cajaSvc = CajaService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  Map<String, dynamic>? _caja;
  Map<String, double> _totales = {'ingresos': 0, 'retiros': 0};

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
      AppDatabase.logLocalError(scope: 'movimientos_page.load', error: e, stackTrace: st, payload: {'cajaId': widget.cajaId});
    }
    setState(() {
      _caja = caja;
      _rows = rows;
      _totales = tot;
      _loading = false;
    });
  }

  void _nuevo() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => _MovimientoDialog(cajaId: widget.cajaId));
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm == true) {
      await _svc.eliminar(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento eliminado')));
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
                    Text('Caja: ${caja['codigo_caja']} • Estado: ${caja['estado']}'),
                    const SizedBox(height: 4),
                    Text('Ingresos: ${formatCurrency(_totales['ingresos'] ?? 0)}  •  Retiros: ${formatCurrency(_totales['retiros'] ?? 0)}'),
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
                      final color = tipo == 'INGRESO' ? Colors.green.shade100 : Colors.red.shade100;
                      return Card(
                        color: color,
                        child: ListTile(
                          title: Text('$tipo: ${formatCurrency(monto)}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (obs.isNotEmpty) Text(obs),
                              Text(fecha, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                          trailing: (caja != null && caja['estado'] == 'ABIERTA')
                              ? PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _editar(m);
                                    if (v == 'del') _eliminar(m['id'] as int);
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                                    const PopupMenuItem(value: 'del', child: Text('Eliminar')),
                                  ],
                                )
                              : null,
                          onTap: () => _editar(m),
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
      _monto.text = ((mov['monto'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto debe ser > 0')));
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.movimiento == null) {
        await _svc.crear(cajaId: widget.cajaId, tipo: _tipo, monto: monto, observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim());
      } else {
        await _svc.actualizar(id: widget.movimiento!['id'] as int, tipo: _tipo, monto: monto, observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim());
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      AppDatabase.logLocalError(scope: 'movimientos_dialog.save', error: e, stackTrace: st, payload: {'cajaId': widget.cajaId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.movimiento == null ? 'Nuevo movimiento' : 'Editar movimiento'),
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
            decoration: const InputDecoration(labelText: 'Observación (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _guardar,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar'),
        ),
      ],
    );
  }
}
