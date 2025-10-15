import 'package:flutter/material.dart';
import '../../data/dao/db.dart';
import '../format.dart';
import '../../services/print_service.dart';

class SaleDetailPage extends StatefulWidget {
  final int ticketId;
  const SaleDetailPage({super.key, required this.ticketId});
  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final t = await db.query('tickets', where: 'id=?', whereArgs: [widget.ticketId]);
    if (t.isEmpty) { setState(() { _loading = false; }); return; }
  final ticket = t.first;
  setState(() { _ticket = ticket; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
  final t = _ticket!;
    final total = t['total_ticket'] as num;
    final rawStatus = (t['status'] as String?) ?? 'No Impreso';
    final norm = rawStatus.toLowerCase();
    final isAnulado = norm == 'anulado';
    final isNoImpreso = norm == 'no impreso';
    final displayStatus = isAnulado ? 'Anulado' : (isNoImpreso ? 'No Impreso' : 'Impreso');
    return Scaffold(
      appBar: AppBar(title: Text(t['identificador_ticket'] as String? ?? '#${t['id']}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatCurrency(total), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAnulado ? Colors.redAccent.withOpacity(0.15) : (isNoImpreso ? Colors.orangeAccent.withOpacity(0.15) : Colors.blueGrey.withOpacity(0.15)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(displayStatus, style: TextStyle(color: isAnulado ? Colors.redAccent : (isNoImpreso ? Colors.orangeAccent : Colors.blueGrey), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder(
              future: _loadProducto(t['producto_id'] as int),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Expanded(child: Center(child: CircularProgressIndicator()));
                final prod = snap.data as Map<String, dynamic>;
                return Expanded(
                  child: ListView.separated(
                    itemCount: 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      return ListTile(
                        title: Text(prod['nombre'] as String),
                        subtitle: Text('1 x ${formatCurrency(t['total_ticket'] as num)}${isAnulado ? ' (anulado)' : ''}'),
                        trailing: Text(formatCurrency(t['total_ticket'] as num), style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                );
              },
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(children: [
              if (isNoImpreso)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirmar reimpresión'),
                          content: const Text('¿Desea reimprimir este ticket?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      final db = await AppDatabase.instance();
                      await db.update('tickets', {'status': 'Impreso'}, where: 'id=?', whereArgs: [t['id']]);
                      try { await PrintService().printTicket(t['id'] as int); } catch (_) {}
                      if (context.mounted) {
                        Navigator.pop(context, true);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket marcado como Impreso')));
                      }
                    },
                    child: const Text('REIMPRIMIR'),
                  ),
                ),
              if (isNoImpreso) const SizedBox(width: 12),
              if (!isAnulado)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirmar anulación'),
                          content: const Text('¿Seguro que querés anular este ticket?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anular')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      // Anular: marcamos ticket como 'Anulado' y restauramos stock (si no es ilimitado=999)
                      final db = await AppDatabase.instance();
                      await db.update('tickets', {'status': 'Anulado'}, where: 'id=?', whereArgs: [t['id']]);
                      final pid = t['producto_id'] as int;
                      // Sumar stock en forma atómica solo si no es ilimitado (999)
                      await db.rawUpdate('UPDATE products SET stock_actual = CASE WHEN stock_actual = 999 THEN 999 ELSE stock_actual + 1 END WHERE id = ?', [pid]);
                      if (context.mounted) {
                        Navigator.pop(context, true);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket anulado')));
                      }
                    },
                    child: const Text('ANULAR'),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            )
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadProducto(int id) async {
    final db = await AppDatabase.instance();
    final r = await db.query('products', columns: ['nombre'], where: 'id=?', whereArgs: [id]);
    return r.first;
  }
}
