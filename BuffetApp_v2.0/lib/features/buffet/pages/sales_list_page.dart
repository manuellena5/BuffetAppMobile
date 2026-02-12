import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import 'sale_detail_page.dart';
import '../services/caja_service.dart';
import '../../shared/widgets/responsive_container.dart';

class SalesListPage extends StatefulWidget {
  const SalesListPage({super.key});
  @override
  State<SalesListPage> createState() => _SalesListPageState();
}

class _SalesListPageState extends State<SalesListPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  // Filtros alineados con CajaTicketsPage
  String _estadoFiltro = 'Todos'; // Todos | Impreso | Anulado | No impreso
  String _productoFiltro = 'Todos';
  List<String> _productos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final caja = await CajaService().getCajaAbierta();
    final cajaId = caja?['id'];
    final where = cajaId == null ? '' : 'WHERE v.caja_id = ?';
    final args = cajaId == null ? <Object?>[] : <Object?>[cajaId];
    final v = await db.rawQuery('''
      SELECT t.id, t.fecha_hora, t.total_ticket, t.identificador_ticket, t.status,
             v.metodo_pago_id, mp.descripcion AS metodo_pago_desc,
             COALESCE(p.nombre, c.descripcion) AS item_nombre
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      LEFT JOIN Categoria_Producto c ON c.id = t.categoria_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      $where
      ORDER BY t.fecha_hora DESC
    ''', args);
    // Construir lista de productos únicos para filtro
    final prods = <String>{'Todos'};
    for (final r in v) {
      final it = (r['item_nombre'] as String?)?.trim();
      if (it != null && it.isNotEmpty) prods.add(it);
    }
    setState(() {
      _rows = v;
      _productos = prods.toList()..sort();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    String? currentDateHeader;
    return Scaffold(
      appBar: AppBar(title: const Text('Tickets')),
      body: LandscapeCenteredBody(
        child: Column(
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
                    onChanged: (v) =>
                        setState(() => _estadoFiltro = v ?? 'Todos'),
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
                    onChanged: (v) =>
                        setState(() => _productoFiltro = v ?? 'Todos'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  itemCount: _filteredRows().length,
                  itemBuilder: (ctx, i) {
                    final v = _filteredRows()[i];
                    final dt =
                        DateTime.tryParse(v['fecha_hora'] as String? ?? '') ??
                            DateTime.now();
                    final dateHeader = DateFormat.yMMMMEEEEd('es_AR')
                        .format(DateTime(dt.year, dt.month, dt.day));
                    final timeStr = DateFormat.Hm('es_AR').format(dt);
                    final tiles = <Widget>[];
                    if (currentDateHeader != dateHeader) {
                      currentDateHeader = dateHeader;
                      tiles.add(Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(dateHeader,
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ));
                    }
                    IconData icon = Icons.money; // efectivo
                    if ((v['metodo_pago_id'] as int?) == 2) {
                      icon = Icons
                          .credit_card; // transferencia asimilada a tarjeta
                    }
                    final status = (v['status'] as String?) ?? '';
                    Color? statusColor;
                    final norm = _normEstado(status);
                    if (norm == 'anulado') {
                      statusColor = Colors.redAccent;
                    } else if (norm == 'impreso') {
                      statusColor = Colors.blueGrey;
                    } else {
                      statusColor = Colors.orangeAccent; // No Impreso
                    }
                    tiles.add(ListTile(
                      leading: Icon(icon),
                      title: Text(formatCurrency(v['total_ticket'] as num)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((v['item_nombre'] as String?)?.isNotEmpty ==
                                true)
                              Text(v['item_nombre'] as String)
                            else
                              const Text('Producto'),
                            if ((v['metodo_pago_desc'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              Text(v['metodo_pago_desc'] as String,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic)),
                            Text(timeStr),
                            const SizedBox(height: 2),
                            Text(_labelEstado(norm),
                                style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600)),
                          ]),
                      trailing: Text(v['identificador_ticket'] as String? ??
                          '#${v['id']}'),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        final changed = await nav.push(MaterialPageRoute(
                            builder: (_) =>
                                SaleDetailPage(ticketId: v['id'] as int)));
                        if (changed == true) {
                          if (!mounted) return;
                          _load();
                        }
                      },
                    ));
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: tiles);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredRows() {
    final filtroEstado = _normEstado(_estadoFiltro);
    final filtroProd = _productoFiltro.trim().toLowerCase();
    return _rows.where((r) {
      final estado = _normEstado((r['status'] as String?) ?? '');
      final item = ((r['item_nombre'] as String?) ?? '').trim().toLowerCase();
      final okEstado = (filtroEstado == 'todos') || (estado == filtroEstado);
      final okProducto = (_productoFiltro == 'Todos') || (item == filtroProd);
      return okEstado && okProducto;
    }).toList(growable: false);
  }

  String _normEstado(String s) {
    final t = s.replaceAll('\u00A0', ' ').trim().toLowerCase();
    if (t == 'impreso') return 'impreso';
    if (t == 'anulado') return 'anulado';
    if (t == 'no impreso') return 'no impreso';
    if (t == 'todos') return 'todos';
    return t;
  }

  String _labelEstado(String norm) {
    switch (norm) {
      case 'impreso':
        return 'Impreso';
      case 'anulado':
        return 'Anulado';
      case 'no impreso':
        return 'No impreso';
      case 'todos':
        return 'Todos';
      default:
        if (norm.isEmpty) return '';
        return norm[0].toUpperCase() + norm.substring(1);
    }
  }
}
