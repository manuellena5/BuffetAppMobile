import 'package:flutter/material.dart';
import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import 'sale_detail_page.dart';
import '../services/caja_service.dart';
import '../../shared/widgets/responsive_container.dart';

class SalesListPage extends StatefulWidget {
  /// Si se pasa [cajaId], muestra solo tickets de esa caja.
  /// Si es null, muestra los tickets de la caja abierta.
  final int? cajaId;
  final String? codigoCaja;
  const SalesListPage({super.key, this.cajaId, this.codigoCaja});
  @override
  State<SalesListPage> createState() => _SalesListPageState();
}

class _SalesListPageState extends State<SalesListPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  // Filtros
  String _estadoFiltro = 'Todos';
  String _productoFiltro = 'Todos';
  String _metodoPagoFiltro = 'Todos';
  String _categoriaFiltro = 'Todos';
  List<String> _productos = const [];
  List<String> _metodosPago = const [];
  List<String> _categorias = const [];
  bool _isVentasView = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance();
    int? cajaId = widget.cajaId;
    if (cajaId == null) {
      final caja = await CajaService().getCajaAbierta();
      cajaId = caja?['id'] as int?;
    }
    final where = cajaId == null ? '' : 'WHERE v.caja_id = ?';
    final args = cajaId == null ? <Object?>[] : <Object?>[cajaId];
    final v = await db.rawQuery('''
      SELECT t.id, t.fecha_hora, t.total_ticket, t.identificador_ticket, t.status,
             v.id AS venta_id, v.metodo_pago_id, mp.descripcion AS metodo_pago_desc,
             COALESCE(p.nombre, c.descripcion) AS item_nombre,
             COALESCE(cp.descripcion, c.descripcion, 'Sin cat.') AS categoria_desc
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      LEFT JOIN Categoria_Producto c ON c.id = t.categoria_id
      LEFT JOIN Categoria_Producto cp ON cp.id = p.categoria_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      $where
      ORDER BY t.fecha_hora DESC
    ''', args);
    // Construir listas únicas para filtros
    final prods = <String>{'Todos'};
    final metodos = <String>{'Todos'};
    final cats = <String>{'Todos'};
    for (final r in v) {
      final it = (r['item_nombre'] as String?)?.trim();
      if (it != null && it.isNotEmpty) prods.add(it);
      final mp = (r['metodo_pago_desc'] as String?)?.trim();
      if (mp != null && mp.isNotEmpty) metodos.add(mp);
      final cat = (r['categoria_desc'] as String?)?.trim();
      if (cat != null && cat.isNotEmpty) cats.add(cat);
    }
    setState(() {
      _rows = v;
      _productos = prods.toList()..sort();
      _metodosPago = metodos.toList()..sort();
      _categorias = cats.toList()..sort();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final filtered = _filteredRows();
    final ventasGrouped = _isVentasView ? _buildVentasGrouped(filtered) : <Map<String, dynamic>>[];
    final appBarTitle = widget.codigoCaja != null
        ? 'Historial · ${widget.codigoCaja}'
        : 'Historial';

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: LandscapeCenteredBody(
        child: Column(
          children: [
            // ─── RESUMEN SUPERIOR ───
            _buildResumen(context),
            // ─── TOGGLE VISTA ───
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Tickets'), icon: Icon(Icons.receipt_long, size: 18)),
                  ButtonSegment(value: true, label: Text('Ventas'), icon: Icon(Icons.shopping_bag, size: 18)),
                ],
                selected: {_isVentasView},
                onSelectionChanged: (s) => setState(() => _isVentasView = s.first),
              ),
            ),
            // ─── FILTROS FILA 1 ───
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    initialValue: _estadoFiltro,
                    items: const ['Todos', 'Impreso', 'Anulado', 'No impreso']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _estadoFiltro = v ?? 'Todos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Método pago',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    initialValue: _metodoPagoFiltro,
                    items: _metodosPago
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _metodoPagoFiltro = v ?? 'Todos'),
                  ),
                ),
              ]),
            ),
            // ─── FILTROS FILA 2 ───
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    initialValue: _categoriaFiltro,
                    items: _categorias
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _categoriaFiltro = v ?? 'Todos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Producto',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    initialValue: _productoFiltro,
                    items: _productos
                        .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _productoFiltro = v ?? 'Todos'),
                  ),
                ),
              ]),
            ),
            // ─── CONTADOR ───
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Text(
                    _isVentasView
                        ? '${ventasGrouped.length} venta${ventasGrouped.length == 1 ? '' : 's'}'
                        : '${filtered.length} ticket${filtered.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // ─── LISTA ───
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _isVentasView
                    ? _buildVentasList(ventasGrouped)
                    : _buildTicketsList(filtered),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── RESUMEN SUPERIOR ───
  Widget _buildResumen(BuildContext context) {
    double totalVendido = 0;
    double totalEfectivo = 0;
    double totalTransferencia = 0;
    int cantAnulados = 0;

    for (final r in _rows) {
      final precio = ((r['total_ticket'] as num?) ?? 0).toDouble();
      final estado = _normEstado((r['status'] as String?) ?? '');
      final mp = ((r['metodo_pago_desc'] as String?) ?? '').toLowerCase();

      if (estado == 'anulado') {
        cantAnulados++;
        continue;
      }

      totalVendido += precio;
      if (mp.contains('efectivo')) {
        totalEfectivo += precio;
      } else if (mp.contains('transfer')) {
        totalTransferencia += precio;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total vendido', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(formatCurrencyNoDecimals(totalVendido), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          _ResumenChip(label: 'Efectivo', value: formatCurrencyNoDecimals(totalEfectivo), color: Colors.green.shade700),
          const SizedBox(width: 10),
          _ResumenChip(label: 'Transf.', value: formatCurrencyNoDecimals(totalTransferencia), color: Colors.blue.shade700),
          if (cantAnulados > 0) ...[
            const SizedBox(width: 10),
            _ResumenChip(label: 'Anulados', value: '$cantAnulados', color: Colors.red.shade600),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredRows() {
    final filtroEstado = _normEstado(_estadoFiltro);
    final filtroProd = _productoFiltro.trim().toLowerCase();
    final filtroMetodo = _metodoPagoFiltro.trim().toLowerCase();
    final filtroCat = _categoriaFiltro.trim().toLowerCase();
    return _rows.where((r) {
      final estado = _normEstado((r['status'] as String?) ?? '');
      final item = ((r['item_nombre'] as String?) ?? '').trim().toLowerCase();
      final metodo = ((r['metodo_pago_desc'] as String?) ?? '').trim().toLowerCase();
      final cat = ((r['categoria_desc'] as String?) ?? '').trim().toLowerCase();
      final okEstado = (filtroEstado == 'todos') || (estado == filtroEstado);
      final okProducto = (_productoFiltro == 'Todos') || (item == filtroProd);
      final okMetodo = (_metodoPagoFiltro == 'Todos') || (metodo == filtroMetodo);
      final okCategoria = (_categoriaFiltro == 'Todos') || (cat == filtroCat);
      return okEstado && okProducto && okMetodo && okCategoria;
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

  // ─── TICKETS LIST ───
  Widget _buildTicketsList(List<Map<String, dynamic>> filtered) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        try {
          final r = filtered[i];
          return _TicketCard(
            monto: ((r['total_ticket'] as num?) ?? 0).toDouble(),
            producto: (r['item_nombre'] as String?) ?? '—',
            medioPago: (r['metodo_pago_desc'] as String?) ?? 'Sin MP',
            fechaHora: (r['fecha_hora'] as String?) ?? '',
            codigo: (r['identificador_ticket'] as String?) ?? '#${r['id']}',
            estado: _normEstado((r['status'] as String?) ?? ''),
            ticketId: r['id'] as int,
            onTap: () async {
              final nav = Navigator.of(context);
              final changed = await nav.push(MaterialPageRoute(
                  builder: (_) =>
                      SaleDetailPage(ticketId: r['id'] as int)));
              if (changed == true) {
                if (!mounted) return;
                _load();
              }
            },
          );
        } catch (e, stack) {
          AppDatabase.logLocalError(
            scope: 'sales_list.render_item',
            error: e.toString(),
            stackTrace: stack,
            payload: {'index': i},
          );
          return Card(
            child: ListTile(
              leading: const Icon(Icons.warning, color: Colors.orange),
              title: const Text('Error al mostrar ticket'),
            ),
          );
        }
      },
    );
  }

  // ─── VENTAS GROUPED LIST ───
  List<Map<String, dynamic>> _buildVentasGrouped(List<Map<String, dynamic>> filtered) {
    final Map<int, List<Map<String, dynamic>>> groups = {};
    for (final r in filtered) {
      final ventaId = r['venta_id'] as int;
      groups.putIfAbsent(ventaId, () => []).add(r);
    }
    final ventas = groups.entries.map((e) {
      final tickets = e.value;
      double total = 0;
      final itemCounts = <String, int>{};
      String medioPago = '';
      String fechaHora = '';
      bool allAnulados = true;

      for (final t in tickets) {
        total += ((t['total_ticket'] as num?) ?? 0).toDouble();
        final item = (t['item_nombre'] as String?) ?? '';
        if (item.isNotEmpty) {
          itemCounts[item] = (itemCounts[item] ?? 0) + 1;
        }
        medioPago = (t['metodo_pago_desc'] as String?) ?? '';
        final fh = (t['fecha_hora'] as String?) ?? '';
        if (fechaHora.isEmpty || (fh.isNotEmpty && fh.compareTo(fechaHora) < 0)) {
          fechaHora = fh;
        }
        if (_normEstado((t['status'] as String?) ?? '') != 'anulado') {
          allAnulados = false;
        }
      }

      // Build items description: "2x Hamburguesa, 1x Coca Cola"
      final itemsDesc = itemCounts.entries
          .map((e) => e.value > 1 ? '${e.value}x ${e.key}' : e.key)
          .join(', ');

      return {
        'venta_id': e.key,
        'total': total,
        'items_desc': itemsDesc,
        'metodo_pago': medioPago,
        'fecha_hora': fechaHora,
        'cant_tickets': tickets.length,
        'all_anulados': allAnulados,
      };
    }).toList();

    // Sort by fecha_hora DESC
    ventas.sort((a, b) =>
        (b['fecha_hora'] as String).compareTo(a['fecha_hora'] as String));
    return ventas;
  }

  Widget _buildVentasList(List<Map<String, dynamic>> ventas) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: ventas.length,
      itemBuilder: (ctx, i) {
        try {
          final v = ventas[i];
          return _VentaCard(
            total: (v['total'] as num).toDouble(),
            itemsDesc: v['items_desc'] as String,
            medioPago: v['metodo_pago'] as String,
            fechaHora: v['fecha_hora'] as String,
            cantTickets: v['cant_tickets'] as int,
            isAnulado: v['all_anulados'] as bool,
          );
        } catch (e, stack) {
          AppDatabase.logLocalError(
            scope: 'sales_list.render_venta',
            error: e.toString(),
            stackTrace: stack,
            payload: {'index': i},
          );
          return Card(
            child: ListTile(
              leading: const Icon(Icons.warning, color: Colors.orange),
              title: const Text('Error al mostrar venta'),
            ),
          );
        }
      },
    );
  }
}

// ─── WIDGET: CHIP DE RESUMEN ───

class _ResumenChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ResumenChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ─── WIDGET: TARJETA DE TICKET ───

class _TicketCard extends StatelessWidget {
  final double monto;
  final String producto;
  final String medioPago;
  final String fechaHora;
  final String codigo;
  final String estado; // normalizado: 'impreso', 'anulado', 'no impreso'
  final int ticketId;
  final VoidCallback? onTap;

  const _TicketCard({
    required this.monto,
    required this.producto,
    required this.medioPago,
    required this.fechaHora,
    required this.codigo,
    required this.estado,
    required this.ticketId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAnulado = estado == 'anulado';
    final isNoImpreso = estado == 'no impreso';

    // Extraer solo la hora de fecha_hora
    final hora = _extractHora(fechaHora);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isAnulado ? 0 : 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isAnulado
            ? BorderSide(color: Colors.red.shade200, width: 1)
            : BorderSide.none,
      ),
      color: isAnulado ? Colors.red.shade50 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LÍNEA 1: Monto + Badge medio de pago ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      formatCurrencyNoDecimals(monto),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: isAnulado ? Colors.red.shade400 : null,
                        decoration: isAnulado ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.red.shade400,
                      ),
                    ),
                  ),
                  _MedioPagoBadge(medioPago: medioPago),
                ],
              ),
              const SizedBox(height: 4),
              // ── LÍNEA 2: Producto ──
              Text(
                producto,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isAnulado ? Colors.grey.shade500 : Colors.grey.shade800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // ── LÍNEA 3: Hora · Código ──
              Text(
                '$hora · $codigo',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // ── LÍNEA 4: Estado (si aplica) ──
              if (isAnulado) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.cancel, size: 15, color: Colors.red.shade600),
                    const SizedBox(width: 4),
                    Text(
                      'ANULADO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
              if (isNoImpreso) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.print_disabled, size: 15, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'NO IMPRESO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _extractHora(String fechaHora) {
    try {
      final dt = DateTime.tryParse(fechaHora);
      if (dt != null) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    final match = RegExp(r'(\d{2}:\d{2})').firstMatch(fechaHora);
    if (match != null) return match.group(1)!;
    return fechaHora;
  }
}

// ─── WIDGET: BADGE DE MEDIO DE PAGO ───

class _MedioPagoBadge extends StatelessWidget {
  final String medioPago;

  const _MedioPagoBadge({required this.medioPago});

  @override
  Widget build(BuildContext context) {
    final mp = medioPago.toLowerCase();
    final Color bg;
    final Color fg;

    if (mp.contains('efectivo')) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    } else if (mp.contains('transfer')) {
      bg = Colors.blue.shade50;
      fg = Colors.blue.shade700;
    } else {
      bg = Colors.grey.shade100;
      fg = Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        medioPago.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── WIDGET: TARJETA DE VENTA (AGRUPADA) ───

class _VentaCard extends StatelessWidget {
  final double total;
  final String itemsDesc;
  final String medioPago;
  final String fechaHora;
  final int cantTickets;
  final bool isAnulado;

  const _VentaCard({
    required this.total,
    required this.itemsDesc,
    required this.medioPago,
    required this.fechaHora,
    required this.cantTickets,
    required this.isAnulado,
  });

  @override
  Widget build(BuildContext context) {
    final hora = _extractHora(fechaHora);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isAnulado ? 0 : 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isAnulado
            ? BorderSide(color: Colors.red.shade200, width: 1)
            : BorderSide.none,
      ),
      color: isAnulado ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LÍNEA 1: Monto + Badge medio de pago ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    formatCurrencyNoDecimals(total),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: isAnulado ? Colors.red.shade400 : null,
                      decoration: isAnulado ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.red.shade400,
                    ),
                  ),
                ),
                _MedioPagoBadge(medioPago: medioPago),
              ],
            ),
            const SizedBox(height: 6),
            // ── LÍNEA 2: Items ──
            Text(
              itemsDesc.isNotEmpty ? itemsDesc : '—',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isAnulado ? Colors.grey.shade500 : Colors.grey.shade800,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // ── LÍNEA 3: Hora · Cant. tickets ──
            Row(
              children: [
                Text(
                  hora,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 8),
                Icon(Icons.receipt_long, size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 3),
                Text(
                  '$cantTickets ticket${cantTickets == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            // ── LÍNEA 4: Estado anulado ──
            if (isAnulado) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.cancel, size: 15, color: Colors.red.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'ANULADO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _extractHora(String fechaHora) {
    try {
      final dt = DateTime.tryParse(fechaHora);
      if (dt != null) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    final match = RegExp(r'(\d{2}:\d{2})').firstMatch(fechaHora);
    if (match != null) return match.group(1)!;
    return fechaHora;
  }
}
