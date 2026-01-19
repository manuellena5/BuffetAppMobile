import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import '../../shared/services/print_service.dart';
import '../../shared/services/usb_printer_service.dart';
import '../../shared/services/supabase_sync_service.dart';
import '../../shared/pages/printer_test_page.dart';

class SaleDetailPage extends StatefulWidget {
  final int ticketId;
  const SaleDetailPage({super.key, required this.ticketId});
  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;

  String _formatFechaHora(dynamic raw) {
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return '-';

    DateTime? dt;
    dt = DateTime.tryParse(text);
    dt ??= _tryParseDate(text, 'yyyy-MM-dd HH:mm:ss');
    dt ??= _tryParseDate(text, 'yyyy-MM-dd HH:mm');

    if (dt == null) return text;
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  DateTime? _tryParseDate(String text, String pattern) {
    try {
      return DateFormat(pattern).parseLoose(text);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    final t =
        await db.query('tickets', where: 'id=?', whereArgs: [widget.ticketId]);
    if (t.isEmpty) {
      setState(() {
        _loading = false;
      });
      return;
    }
    final ticket = t.first;
    setState(() {
      _ticket = ticket;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = _ticket!;
    final total = t['total_ticket'] as num;
    final rawStatus = (t['status'] as String?) ?? 'No Impreso';
    final norm = rawStatus.toLowerCase();
    final isAnulado = norm == 'anulado';
    final isNoImpreso = norm == 'no impreso';
    final displayStatus =
        isAnulado ? 'Anulado' : (isNoImpreso ? 'No Impreso' : 'Impreso');
    final createdAt = _formatFechaHora(t['fecha_hora']);
    return Scaffold(
      appBar: AppBar(
          title: Text(t['identificador_ticket'] as String? ?? '#${t['id']}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(formatCurrency(total),
                style:
                    const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAnulado
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : (isNoImpreso
                            ? Colors.orangeAccent.withValues(alpha: 0.15)
                            : Colors.blueGrey.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(displayStatus,
                      style: TextStyle(
                          color: isAnulado
                              ? Colors.redAccent
                              : (isNoImpreso
                                  ? Colors.orangeAccent
                                  : Colors.blueGrey),
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Creado: $createdAt',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            FutureBuilder(
              future: _loadItemNombre(
                  productoId: t['producto_id'] as int?,
                  categoriaId: t['categoria_id'] as int?),
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Expanded(
                      child: Center(child: CircularProgressIndicator()));
                }
                final itemNombre = snap.data as String;
                return Expanded(
                  child: ListView.separated(
                    itemCount: 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      return ListTile(
                        title: Text(itemNombre),
                        subtitle: Text(
                            '1 x ${formatCurrency(t['total_ticket'] as num)}${isAnulado ? ' (anulado)' : ''}'),
                        trailing: Text(formatCurrency(t['total_ticket'] as num),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                );
              },
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(children: [
              if (!isAnulado)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        // Validar USB conectada antes de confirmar
                        bool connected = false;
                        try {
                          connected = await UsbPrinterService()
                              .isConnected()
                              .timeout(const Duration(seconds: 2),
                                  onTimeout: () => false);
                        } catch (_) {
                          connected = false;
                        }

                        if (!connected && context.mounted) {
                          final action = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Impresora no conectada'),
                              content: const Text(
                                  'No hay una impresora USB conectada.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, 'config'),
                                  child: const Text('Config impresora'),
                                ),
                              ],
                            ),
                          );
                          if (action == 'config' && context.mounted) {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const PrinterTestPage()),
                            );
                          }
                          return;
                        }

                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Confirmar reimpresión'),
                            content:
                                const Text('¿Desea reimprimir este ticket?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar')),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Confirmar')),
                            ],
                          ),
                        );
                        if (ok != true) return;

                        final usb = await PrintService()
                            .printTicketUsbOnly(t['id'] as int);
                        if (!usb) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('No se pudo imprimir por USB.')),
                            );
                          }
                          return;
                        }

                        // Sólo marcar como Impreso si la reimpresión fue exitosa.
                        if (isNoImpreso) {
                          final db = await AppDatabase.instance();
                          await db.update('tickets', {'status': 'Impreso'},
                              where: 'id=?', whereArgs: [t['id']]);
                        }
                      } catch (e, st) {
                        await AppDatabase.logLocalError(
                            scope: 'sale_detail.print_ticket',
                            error: e,
                            stackTrace: st,
                            payload: {'ticketId': t['id']});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al imprimir: $e')),
                          );
                        }
                        return;
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                      if (isNoImpreso) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Ticket marcado como Impreso')),
                        );
                      }
                    },
                    child: const Text('REIMPRIMIR'),
                  ),
                ),
              if (!isAnulado) const SizedBox(width: 12),
              if (!isAnulado)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirmar anulación'),
                          content: const Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('¿Desea anularlo?'),
                              SizedBox(height: 8),
                              Text(
                                  'Si usted anula el ticket no va a poder revertir esta situación'),
                            ],
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar')),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Anular')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      // Anular: marcamos ticket como 'Anulado' y restauramos stock (si no es ilimitado=999)
                      final db = await AppDatabase.instance();
                      await db.update('tickets', {'status': 'Anulado'},
                          where: 'id=?', whereArgs: [t['id']]);
                      final pid = t['producto_id'] as int?;
                      if (pid != null) {
                        // Sumar stock en forma atómica solo si no es ilimitado (999)
                        await db.rawUpdate(
                            'UPDATE products SET stock_actual = CASE WHEN stock_actual = 999 THEN 999 ELSE stock_actual + 1 END WHERE id = ?',
                            [pid]);
                      }
                      // Encolar anulación para Supabase (upsert del item con status)
                      final venta = await db.query('ventas',
                          columns: ['caja_id'],
                          where: 'id=(SELECT venta_id FROM tickets WHERE id=?)',
                          whereArgs: [t['id']],
                          limit: 1);
                      String? codigoCaja;
                      if (venta.isNotEmpty) {
                        final cajaId = venta.first['caja_id'] as int?;
                        if (cajaId != null) {
                          final caja = await db.query('caja_diaria',
                              columns: ['codigo_caja'],
                              where: 'id=?',
                              whereArgs: [cajaId],
                              limit: 1);
                          if (caja.isNotEmpty)
                            codigoCaja = caja.first['codigo_caja'] as String?;
                        }
                      }
                      // obtener categoría para el payload
                      String? categoriaDesc;
                      final catId = t['categoria_id'] as int?;
                      if (catId != null) {
                        final cat = await db.query('Categoria_Producto',
                            columns: ['descripcion'],
                            where: 'id=?',
                            whereArgs: [catId],
                            limit: 1);
                        if (cat.isNotEmpty)
                          categoriaDesc = cat.first['descripcion'] as String?;
                      }
                      await SupaSyncService.I.enqueueItem({
                        'codigo_caja': codigoCaja,
                        'ticket_id': t['id'],
                        'fecha': t['fecha_hora'],
                        'producto_id': t['producto_id'],
                        'producto_nombre': await _loadItemNombre(
                            productoId: t['producto_id'] as int?,
                            categoriaId: t['categoria_id'] as int?),
                        'categoria': categoriaDesc,
                        'cantidad': 1,
                        'precio_unitario': t['total_ticket'],
                        'total': t['total_ticket'],
                        'metodo_pago': null,
                        'status': 'Anulado',
                      });
                      if (context.mounted) {
                        Navigator.pop(context, true);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ticket anulado')));
                      }
                    },
                    child: const Text('Anular', style: TextStyle(fontSize: 12)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(formatCurrency(total),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
            )
          ],
        ),
      ),
    );
  }

  Future<String> _loadItemNombre({int? productoId, int? categoriaId}) async {
    final db = await AppDatabase.instance();
    if (productoId != null) {
      final r = await db.query('products',
          columns: ['nombre'], where: 'id=?', whereArgs: [productoId]);
      if (r.isNotEmpty) return r.first['nombre'] as String;
    }
    if (categoriaId != null) {
      final r = await db.query('Categoria_Producto',
          columns: ['descripcion'], where: 'id=?', whereArgs: [categoriaId]);
      if (r.isNotEmpty) return r.first['descripcion'] as String;
    }
    return 'Producto';
  }
}
