import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/print_service.dart';
import '../../services/caja_service.dart';
import '../../data/dao/db.dart';

class PrinterTestPage extends StatefulWidget {
  const PrinterTestPage({super.key});
  @override
  State<PrinterTestPage> createState() => _PrinterTestPageState();
}

class _PrinterTestPageState extends State<PrinterTestPage> {
  Printer? _selected;
  List<Printer> _printers = const [];

  Future<void> _refreshPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      setState(() => _printers = printers);
    } catch (_) {
      // Algunos dispositivos no exponen lista; seguimos con pickPrinter
      setState(() => _printers = const []);
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshPrinters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba de impresora')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                final p = await Printing.pickPrinter(context: context);
                setState(() => _selected = p);
              },
              icon: const Icon(Icons.print),
              label: Text(_selected == null ? 'Elegir impresora' : 'Impresora: ${_selected!.name}'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Disponibles:'),
                const SizedBox(width: 8),
                IconButton(onPressed: _refreshPrinters, icon: const Icon(Icons.refresh)),
              ],
            ),
            Expanded(
              child: _printers.isEmpty
                  ? const Center(child: Text('No se detectaron impresoras. Podés seleccionar una con "Elegir impresora" y se usará el diálogo del sistema o previsualización PDF.'))
                  : ListView.builder(
                      itemCount: _printers.length,
                      itemBuilder: (ctx, i) {
                        final p = _printers[i];
                        final selected = _selected?.name == p.name;
                        return ListTile(
                          title: Text(p.name),
                          trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                          onTap: () => setState(() => _selected = p),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                // Buscar último ticket o generar uno de prueba en memoria
                final db = await AppDatabase.instance();
                final last = await db.query('tickets', columns: ['id'], orderBy: 'id DESC', limit: 1);
                final id = last.isNotEmpty ? last.first['id'] as int : null;
                if (id == null) {
                  // Construir un PDF de ejemplo y mostrar
                  await Printing.layoutPdf(
                    onLayout: (f) async => await PrintService().buildTicketPdf(await _crearTicketDummy()),
                    name: 'ticket_demo.pdf',
                  );
                } else {
                  await Printing.layoutPdf(
                    onLayout: (f) => PrintService().buildTicketPdf(id),
                    name: 'ticket_$id.pdf',
                  );
                }
              },
              child: const Text('Test Ticket de venta'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                // Tomar caja abierta o la última cerrada
                final svc = CajaService();
                final abierta = await svc.getCajaAbierta();
                int? cajaId = abierta?['id'] as int?;
                if (cajaId == null) {
                  final db = await AppDatabase.instance();
                  final last = await db.query('caja_diaria', columns: ['id'], orderBy: 'id DESC', limit: 1);
                  cajaId = last.isNotEmpty ? last.first['id'] as int : null;
                }
                if (cajaId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay cajas para imprimir.')));
                  return;
                }
                await Printing.layoutPdf(
                  onLayout: (f) => PrintService().buildCajaResumenPdf(cajaId!),
                  name: 'cierre_caja_$cajaId.pdf',
                );
              },
              child: const Text('Test Cierre de caja'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _crearTicketDummy() async {
    // Genera un ticket temporal con producto/ticket de prueba si el DB está vacío
    final db = await AppDatabase.instance();
    final p = await db.query('products', columns: ['id'], limit: 1);
    int productoId;
    if (p.isEmpty) {
      productoId = await db.insert('products', {
        'codigo_producto': 'DEMO',
        'nombre': 'Hamburguesa',
        'precio_venta': 1500,
        'stock_actual': 999,
        'stock_minimo': 0,
        'categoria_id': null,
        'visible': 1,
        'color': null,
      });
    } else {
      productoId = p.first['id'] as int;
    }
    final now = DateTime.now();
    final fecha = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final hora = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final ventaId = await db.insert('ventas', {
      'uuid': 'demo',
      'fecha_hora': '$fecha $hora',
      'total_venta': 1500,
      'status': 'No impreso',
      'activo': 1,
      'metodo_pago_id': 1,
      'caja_id': null,
    });
    final ticketId = await db.insert('tickets', {
      'venta_id': ventaId,
      'categoria_id': null,
      'producto_id': productoId,
      'fecha_hora': '$fecha $hora',
      'status': 'Impreso',
      'total_ticket': 1500,
      'identificador_ticket': null,
    });
    await db.update('tickets', {'identificador_ticket': 'DEMO-${now.year}${now.month}${now.day}-$ticketId'}, where: 'id=?', whereArgs: [ticketId]);
    return ticketId;
  }
}
