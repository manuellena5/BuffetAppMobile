import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/dao/db.dart';
import 'caja_service.dart';

/// Servicio de impresión/previsualización en formato 80mm
/// Usa el paquete `printing` para abrir el diálogo del sistema o guardar PDF.
class PrintService {
  /// Construye el PDF de un ticket por ÍTEM
  Future<Uint8List> buildTicketPdf(int ticketId) async {
    final db = await AppDatabase.instance();
    final rows = await db.rawQuery('''
      SELECT t.id, t.identificador_ticket, t.fecha_hora, t.total_ticket, 
             p.nombre as producto, v.caja_id, c.codigo_caja
      FROM tickets t
      JOIN products p ON p.id = t.producto_id
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN caja_diaria c ON c.id = v.caja_id
      WHERE t.id = ?
    ''', [ticketId]);
    if (rows.isEmpty) {
      // PDF vacío con mensaje
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (ctx) =>
            pw.Center(child: pw.Text('Ticket no encontrado: #$ticketId')),
      ));
      return doc.save();
    }
    final t = rows.first;
    final identificador =
        (t['identificador_ticket'] as String?) ?? '#${t['id']}';
    final fechaHora = (t['fecha_hora'] as String?) ?? '';
    final cajaCodigo = (t['codigo_caja'] as String?) ?? '-';
    final producto = (t['producto'] as String?) ?? 'Producto';
    final total = (t['total_ticket'] as num?)?.toDouble() ?? 0;

    final doc = pw.Document();
    final bold = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
    final header = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('BUFFET', style: header),
              pw.SizedBox(height: 2),
              pw.Text('Nº $identificador'),
              pw.Text(fechaHora),
              pw.Text('Caja $cajaCodigo'),
              pw.SizedBox(height: 10),
              pw.Text(producto.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 26, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text(_formatCurrency(total), style: bold),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// Construye el PDF del cierre/resumen de caja
  Future<Uint8List> buildCajaResumenPdf(int cajaId) async {
    final db = await AppDatabase.instance();
    final caja = await db.query('caja_diaria',
        where: 'id=?', whereArgs: [cajaId], limit: 1);
    final resumen = await CajaService().resumenCaja(cajaId);
    final c = caja.isNotEmpty ? caja.first : <String, Object?>{};
  final fondo = ((c['fondo_inicial'] as num?) ?? 0).toDouble();
  final obsApertura = (c['observaciones_apertura'] as String?) ?? '';
  final obsCierre = (c['obs_cierre'] as String?) ?? '';
  final descripcionEvento = (c['descripcion_evento'] as String?) ?? '';
  final diferencia = ((c['diferencia'] as num?) ?? 0).toDouble();

    final doc = pw.Document();
    pw.TextStyle s([bool b = false]) => pw.TextStyle(
        fontSize: 9, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal);

    String line([String title = '', String? value]) {
      if (value == null) return title;
      return '$title $value';
    }

    final totalesMp = (resumen['por_mp'] as List).cast<Map<String, Object?>>();
    final porProd =
        (resumen['por_producto'] as List).cast<Map<String, Object?>>();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('================================================',
                  style: s(true)),
              pw.Text('                 CIERRE DE CAJA                 ',
                  style: s(true)),
              pw.Text('================================================',
                  style: s(true)),
              pw.SizedBox(height: 6),
              pw.Text(line('Codigo caja:', c['codigo_caja']?.toString()),
                  style: s()),
              pw.Text(
                  line('Fecha apertura:',
                      '${c['fecha'] ?? ''} ${c['hora_apertura'] ?? ''}'),
                  style: s()),
              pw.Text(
                  line('Usuario apertura:', c['usuario_apertura']?.toString()),
                  style: s()),
              pw.Text(line('Disciplina:', c['disciplina']?.toString()),
                  style: s()),
              if (descripcionEvento.isNotEmpty)
                pw.Text(line('Descripción del evento:', descripcionEvento), style: s()),
              if ((c['cierre_dt'] as String?) != null)
                pw.Text(line('Fecha cierre:', c['cierre_dt']?.toString()),
                    style: s()),
              if (obsApertura.isNotEmpty)
                pw.Text('Obs. apertura: $obsApertura', style: s()),
              if (obsCierre.isNotEmpty)
                pw.Text('Obs. cierre: $obsCierre', style: s()),
              pw.SizedBox(height: 6),
              pw.Text('TOTALES POR MEDIO DE PAGO', style: s(true)),
              pw.SizedBox(height: 4),
              ...totalesMp.map((m) => pw.Text(
                    '${(m['mp_desc'] as String?) ?? 'MP ${m['mp']}'}: ${_formatCurrency(((m['total'] as num?) ?? 0).toDouble())}',
                    style: s(),
                  )),
              pw.SizedBox(height: 4),
              pw.Text(
                  'TOTAL: ${_formatCurrency(((resumen['total'] as num?) ?? 0).toDouble())}',
                  style: s(true)),
              pw.SizedBox(height: 6),
              pw.Text('Fondo inicial: ${_formatCurrency(fondo)}', style: s()),
              pw.Text(
          'Diferencia: ${_formatCurrency(diferencia)}',
                  style: s(true)),
              pw.Text(
                  'Tickets anulados: ${(resumen['tickets']['anulados'] ?? 0)}',
                  style: s()),
              pw.SizedBox(height: 6),
              pw.Text('ITEMS VENDIDOS:', style: s(true)),
              pw.SizedBox(height: 2),
              ...porProd.map((p) => pw.Text(
                    '(${(p['nombre'] ?? '')} x ${(p['cantidad'] ?? 0)}) = ${_formatCurrency(((p['total'] as num?) ?? 0).toDouble())}',
                    style: s(),
                  )),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Abre el diálogo de impresión del sistema para un ticket
  Future<void> printTicket(int ticketId) async {
    await Printing.layoutPdf(
      onLayout: (format) async => buildTicketPdf(ticketId),
      name: 'ticket_$ticketId.pdf',
    );
  }

  /// Imprime todos los tickets de una venta (uno por ítem)
  Future<void> printVentaTicketsForVenta(int ventaId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('tickets',
        columns: ['id'],
        where: 'venta_id=?',
        whereArgs: [ventaId],
        orderBy: 'id');
    for (final r in rows) {
      final id = r['id'] as int;
      await printTicket(id);
    }
  }

  /// Abre el diálogo de impresión con el resumen/cierre de caja
  Future<void> printCajaResumen(int cajaId) async {
    await Printing.layoutPdf(
      onLayout: (format) async => buildCajaResumenPdf(cajaId),
  name: 'cierre_caja_$cajaId.pdf',
    );
  }

  String _formatCurrency(num v) {
    // Formato simple $ 1234.56 (rápido y portable)
    final s = v.toStringAsFixed(2);
    return '\$ $s';
  }
}
