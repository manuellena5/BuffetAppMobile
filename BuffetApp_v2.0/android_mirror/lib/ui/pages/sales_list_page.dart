import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/dao/db.dart';
import '../format.dart';
import 'sale_detail_page.dart';
import '../../services/caja_service.dart';

class SalesListPage extends StatefulWidget {
  const SalesListPage({super.key});
  @override
  State<SalesListPage> createState() => _SalesListPageState();
}

class _SalesListPageState extends State<SalesListPage> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String _filtro = 'Todos'; // Todos | No Impreso | Impreso | Anulado

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final caja = await CajaService().getCajaAbierta();
    final cajaId = caja?['id'];
    final where = (_filtro == 'Todos') ? '' : "WHERE t.status = ?";
    final argsBase = (_filtro == 'Todos') ? <Object?>[] : <Object?>[_filtro];
    final joinCaja = cajaId == null ? '' : 'AND v.caja_id = ?';
    final args = cajaId == null ? argsBase : [...argsBase, cajaId];
    final v = await db.rawQuery('''
      SELECT t.id, t.fecha_hora, t.total_ticket, t.identificador_ticket, t.status, v.metodo_pago_id
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      $where ${where.isEmpty ? 'WHERE' : 'AND'} 1=1 $joinCaja
      ORDER BY t.fecha_hora DESC
    ''', args);
    setState(() { _tickets = v; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    String? currentDateHeader;
    return Scaffold(
      appBar: AppBar(title: const Text('Recibos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(spacing: 8, children: [
              for (final s in ['Todos','No Impreso','Impreso','Anulado'])
                ChoiceChip(
                  label: Text(s),
                  selected: _filtro == s,
                  onSelected: (sel) { if (!sel) return; setState(() { _filtro = s; _loading = true; }); _load(); },
                ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
        itemCount: _tickets.length,
        itemBuilder: (ctx, i) {
          final v = _tickets[i];
          final dt = DateTime.tryParse(v['fecha_hora'] as String? ?? '') ?? DateTime.now();
          final dateHeader = DateFormat.yMMMMEEEEd('es_AR').format(DateTime(dt.year, dt.month, dt.day));
          final timeStr = DateFormat.Hm('es_AR').format(dt);
          final tiles = <Widget>[];
          if (currentDateHeader != dateHeader) {
            currentDateHeader = dateHeader;
            tiles.add(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(dateHeader, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
            ));
          }
          IconData icon = Icons.money; // efectivo
          if ((v['metodo_pago_id'] as int?) == 2) icon = Icons.credit_card; // transferencia asimilada a tarjeta
          final status = (v['status'] as String?) ?? '';
          Color? statusColor;
          if (status == 'Anulado') statusColor = Colors.redAccent;
          else if (status == 'Impreso') statusColor = Colors.blueGrey;
          else statusColor = Colors.orangeAccent; // No Impreso
          tiles.add(ListTile(
            leading: Icon(icon),
            title: Text(formatCurrency(v['total_ticket'] as num)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(timeStr),
              const SizedBox(height: 2),
              Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
            ]),
            trailing: Text(v['identificador_ticket'] as String? ?? '#${v['id']}'),
            onTap: () async {
              final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailPage(ticketId: v['id'] as int)));
              if (changed == true) {
                _load();
              }
            },
          ));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
        },
      ),
            ),
          ),
        ],
      ),
    );
  }
}
