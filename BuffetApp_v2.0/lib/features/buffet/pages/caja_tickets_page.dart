import 'package:flutter/material.dart';
import '../../../data/dao/db.dart';

class CajaTicketsPage extends StatefulWidget {
  final int cajaId;
  final String codigoCaja;
  const CajaTicketsPage({super.key, required this.cajaId, required this.codigoCaja});

  @override
  State<CajaTicketsPage> createState() => _CajaTicketsPageState();
}

class _CajaTicketsPageState extends State<CajaTicketsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = const [];
  List<String> _productos = const [];
  String _estadoFiltro = 'Todos';
  String _productoFiltro = 'Todos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final rows = await db.rawQuery('''
      SELECT
        t.id,
        t.identificador_ticket AS codigo,
        t.fecha_hora,
        t.total_ticket AS precio,
        t.status,
        COALESCE(p.nombre, cp.descripcion, '—') AS item
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      LEFT JOIN Categoria_Producto cp ON cp.id = t.categoria_id
      WHERE v.caja_id = ?
      ORDER BY t.id DESC
    ''', [widget.cajaId]);
    if (!mounted) return;
    // Construir lista de productos únicos para filtro
    final prods = <String>{'Todos'};
    for (final r in rows) {
      final it = (r['item'] as String?)?.trim();
      if (it != null && it.isNotEmpty) prods.add(it);
    }
    setState(() { _rows = rows; _productos = prods.toList()..sort(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Tk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.codigoCaja,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('Sin tickets para esta caja'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Estado'),
                            initialValue: _estadoFiltro,
                            items: const ['Todos', 'Impreso', 'Anulado', 'No impreso']
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) => setState(() => _estadoFiltro = v ?? 'Todos'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Producto'),
                            initialValue: _productoFiltro,
                            items: _productos
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) => setState(() => _productoFiltro = v ?? 'Todos'),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _filteredRows().length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = _filteredRows()[i];
                          final estado = _labelEstado(_normEstado((r['status'] as String?) ?? ''));
                          return ListTile(
                            // sin ícono de impresora para evitar confusión
                            title: Text((r['item'] as String?) ?? ''),
                            subtitle: Text('${r['fecha_hora'] ?? ''} • ${r['codigo'] ?? ''} • $estado'),
                            trailing: Text(_formatCurrency((r['precio'] as num?) ?? 0)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  List<Map<String, dynamic>> _filteredRows() {
    final filtroEstado = _normEstado(_estadoFiltro);
    final filtroProd = _productoFiltro.trim().toLowerCase();
    return _rows.where((r) {
      final estado = _normEstado((r['status'] as String?) ?? '');
      final item = ((r['item'] as String?) ?? '').trim().toLowerCase();
      final okEstado = (filtroEstado == 'todos') || (estado == filtroEstado);
      final okProducto = (_productoFiltro == 'Todos') || (item == filtroProd);
      return okEstado && okProducto;
    }).toList(growable: false);
  }

  String _normEstado(String s) {
    // Comparación en minúsculas y normalizando NBSP
    final t = s.replaceAll('\u00A0', ' ').trim().toLowerCase();
    if (t == 'impreso') return 'impreso';
    if (t == 'anulado') return 'anulado';
    if (t == 'no impreso') return 'no impreso';
    if (t == 'todos') return 'todos';
    return t;
  }

  String _labelEstado(String norm) {
    switch (norm) {
      case 'impreso': return 'Impreso';
      case 'anulado': return 'Anulado';
      case 'no impreso': return 'No impreso';
      case 'todos': return 'Todos';
      default:
        if (norm.isEmpty) return '';
        return norm[0].toUpperCase() + norm.substring(1);
    }
  }

  String _formatCurrency(num v) {
    final s = v.toStringAsFixed(2);
    return '\$ $s';
  }
}
