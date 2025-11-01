import 'dart:typed_data';
import 'dart:convert';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dao/db.dart';
import 'caja_service.dart';
import 'usb_printer_service.dart';

/// Servicio de impresión/previsualización en formato 80mm
/// Usa el paquete `printing` para abrir el diálogo del sistema o guardar PDF.
class PrintService {
  final _usb = UsbPrinterService();

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
        pw.Center(child: pw.Text('Buffet - C.D.M', style: header)),
        pw.SizedBox(height: 2),
              pw.Text(identificador),
              pw.Text(fechaHora),
              pw.Text(cajaCodigo),
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
  final entradasVendidas = ((c['entradas'] as num?) ?? 0).toInt();

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

    // Cargar icono de la app para incluirlo pequeño en el PDF
    pw.ImageProvider? logo;
    try {
      logo = await imageFromAssetBundle('assets/icons/app_icon_foreground.png');
    } catch (_) {
      logo = null; // si falla, seguimos sin logo
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) ...[
                pw.Center(child: pw.Image(logo, height: 24)),
                pw.SizedBox(height: 6),
              ],
              pw.Text('================================================',
                  style: s(true)),
              pw.Text('                 CIERRE DE CAJA                 ',
                  style: s(true)),
              pw.Text('================================================',
                  style: s(true)),
              pw.SizedBox(height: 6),
        pw.Text(line(' caja:', c['codigo_caja']?.toString()),
                  style: s()),
        if ((c['estado'] as String?) != null)
        pw.Text(line('Estado:', c['estado']?.toString()), style: s()),
        pw.Text(
          line('Fecha apertura:',
            '${c['fecha'] ?? ''} ${c['hora_apertura'] ?? ''}'),
          style: s()),
        pw.Text(
          line('Cajero apertura:', c['cajero_apertura']?.toString()),
          style: s()),
              pw.Text(line('Disciplina:', c['disciplina']?.toString()),
                  style: s()),
              if (descripcionEvento.isNotEmpty)
                pw.Text(line('Descripción del evento:', descripcionEvento), style: s()),
              if ((c['cierre_dt'] as String?) != null)
                pw.Text(line('Fecha cierre:', c['cierre_dt']?.toString()),
                    style: s()),
              if ((c['cajero_cierre'] as String?) != null && (c['cajero_cierre'] as String).isNotEmpty)
                pw.Text(line('Cajero de cierre:', c['cajero_cierre']?.toString()), style: s()),
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
          style: s(true).copyWith(fontSize: 12)),
              pw.SizedBox(height: 6),
              pw.Text('Fondo inicial: ${_formatCurrency(fondo)}', style: s()),
              pw.Text(
          'Diferencia: ${_formatCurrency(diferencia)}',
                  style: s(true)),
        pw.Text('Entradas vendidas: $entradasVendidas', style: s()),
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

  // ========================= ESC/POS (USB) =========================
  /// Construye bytes ESC/POS para ticket individual (80mm ó 58mm)
  Future<Uint8List> buildTicketEscPos(int ticketId, {int lineWidth = 48}) async {
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
      return Uint8List(0);
    }
    final t = rows.first;
    final identificador = (t['identificador_ticket'] as String?) ?? '#${t['id']}';
    final fechaHora = (t['fecha_hora'] as String?) ?? '';
    final cajaCodigo = (t['codigo_caja'] as String?) ?? '-';
    final producto = (t['producto'] as String?) ?? 'Producto';
    final total = ((t['total_ticket'] as num?) ?? 0).toDouble();

    final b = BytesBuilder();
    void init() {
      b.add([0x1B, 0x40]); // init
      // Alineación por defecto izquierda
      b.add([0x1B, 0x61, 0x00]);
    }

  void alignCenter() => b.add([0x1B, 0x61, 0x01]);
    void boldOn() => b.add([0x1B, 0x45, 0x01]);
    void boldOff() => b.add([0x1B, 0x45, 0x00]);
    void sizeNormal() => b.add([0x1D, 0x21, 0x00]);
  // sizeDoubleWH() ya no se usa para reducir el alto del ticket
  void sizeDoubleH() => b.add([0x1D, 0x21, 0x01]);
  void fontA() => b.add([0x1B, 0x4D, 0x00]); // normal
  void fontB() => b.add([0x1B, 0x4D, 0x01]); // un punto más chico
    void feed([int n = 1]) => b.add(List<int>.filled(n, 0x0A));

    String clean(String s) {
      // Reemplazo simple para evitar problemas de codepage
      const map = {
        'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
        'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U',
        'ñ': 'n', 'Ñ': 'N', 'ü': 'u', 'Ü': 'U'
      };
      return s.split('').map((c) => map[c] ?? c).join();
    }

    void text(String s) { b.add(utf8.encode(clean(s))); feed(); }

    init();
    alignCenter();
    boldOn(); sizeDoubleH();
    text('Buffet - C.D.M');
    sizeNormal(); boldOff();
    fontB(); // fechas y códigos más chicos
    text(identificador);
    text(fechaHora);
    text(cajaCodigo);
    fontA();
    feed();
    boldOn();
    // tamaño grande como antes para descripción e importe
    b.add([0x1D, 0x21, 0x11]); // sizeDoubleWH
    text(producto.toUpperCase());
    text(_formatCurrency(total));
    sizeNormal();
    boldOff();
    feed(1);
    // Corte parcial
    b.add([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(b.toBytes());
  }

  /// Construye bytes ESC/POS de un cierre de caja de ejemplo (sin datos reales)
  Future<Uint8List> buildCajaResumenEscPosSample({int lineWidth = 48}) async {
    final b = BytesBuilder();
    void init() { b.add([0x1B, 0x40]); }
    void alignCenter() => b.add([0x1B, 0x61, 0x01]);
    void alignLeft() => b.add([0x1B, 0x61, 0x00]);
    void boldOn() => b.add([0x1B, 0x45, 0x01]);
    void boldOff() => b.add([0x1B, 0x45, 0x00]);
    void sizeNormal() => b.add([0x1D, 0x21, 0x00]);
    void sizeDouble() => b.add([0x1D, 0x21, 0x11]);
    void feed([int n = 1]) => b.add(List<int>.filled(n, 0x0A));
    String sep() => ''.padLeft(lineWidth, '=');
    void text(String s) { b.add(utf8.encode(s)); feed(); }

    init();
    // Logo si está disponible
    try {
      final data = await rootBundle.load('assets/icons/app_icon_foreground.png');
      final decoded = img.decodeImage(Uint8List.view(data.buffer));
      if (decoded != null) {
        final targetW = lineWidth >= 48 ? 576 : 384;
        final scaled = img.copyResize(decoded, width: targetW, interpolation: img.Interpolation.average);
        _appendRasterImage(b, scaled);
        feed();
      }
    } catch (_) {}

    alignCenter(); boldOn();
    text(sep());
    sizeDouble(); text('CIERRE DE CAJA'); sizeNormal();
    text(sep());
    alignLeft(); boldOff();
    final now = DateTime.now();
    final fecha = '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';
    final hora = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
    text('Codigo caja: DEMO-001');
    text('Estado: Cerrada');
    text('Fecha apertura: $fecha $hora');
    text('Cajero apertura: Demo User');
    text('Disciplina: General');
    feed();
    boldOn(); text('TOTALES POR MEDIO DE PAGO'); boldOff();
    text('Efectivo: ${_formatCurrency(32450)}');
    text('Transferencia: ${_formatCurrency(18750)}');
    sizeDouble(); boldOn(); text('TOTAL: ${_formatCurrency(51200)}'); boldOff(); sizeNormal();
    feed();
    text('Fondo inicial: ${_formatCurrency(5000)}');
    boldOn(); text('Diferencia: ${_formatCurrency(0)}'); boldOff();
    text('Tickets anulados: 0');
    feed();
    boldOn(); text('ITEMS VENDIDOS:'); boldOff();
    text('(Hamburguesa x 12) = ${_formatCurrency(24000)}');
    text('(Gaseosa x 20) = ${_formatCurrency(16000)}');
    text('(Papas x 8) = ${_formatCurrency(11200)}');
    feed(2);
    b.add([0x1D, 0x56, 0x42, 0x00]);
    return Uint8List.fromList(b.toBytes());
  }

  /// Imprime solo por USB el cierre de caja de ejemplo
  Future<bool> printCajaResumenSampleUsbOnly() async {
    try {
      final bytes = await buildCajaResumenEscPosSample();
      if (bytes.isEmpty) return false;
      return await _usb.printBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  /// Construye bytes ESC/POS para cierre/resumen de caja
  Future<Uint8List> buildCajaResumenEscPos(int cajaId, {int lineWidth = 48}) async {
    final db = await AppDatabase.instance();
    final caja = await db.query('caja_diaria', where: 'id=?', whereArgs: [cajaId], limit: 1);
    final resumen = await CajaService().resumenCaja(cajaId);
    final c = caja.isNotEmpty ? caja.first : <String, Object?>{};
    final fondo = ((c['fondo_inicial'] as num?) ?? 0).toDouble();
    final obsApertura = (c['observaciones_apertura'] as String?) ?? '';
    final obsCierre = (c['obs_cierre'] as String?) ?? '';
    final descripcionEvento = (c['descripcion_evento'] as String?) ?? '';
    final diferencia = ((c['diferencia'] as num?) ?? 0).toDouble();
  final entradasVendidas = ((c['entradas'] as num?) ?? 0).toInt();

    final totalesMp = (resumen['por_mp'] as List).cast<Map<String, Object?>>();
    final porProd = (resumen['por_producto'] as List).cast<Map<String, Object?>>();

  final b = BytesBuilder();
  void init() { b.add([0x1B, 0x40]); }
    void alignCenter() => b.add([0x1B, 0x61, 0x01]);
    void alignLeft() => b.add([0x1B, 0x61, 0x00]);
    void boldOn() => b.add([0x1B, 0x45, 0x01]);
    void boldOff() => b.add([0x1B, 0x45, 0x00]);
    void sizeNormal() => b.add([0x1D, 0x21, 0x00]);
    void sizeDouble() => b.add([0x1D, 0x21, 0x11]);
    void feed([int n = 1]) => b.add(List<int>.filled(n, 0x0A));
    String clean(String s) {
      const map = {
        'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
        'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U',
        'ñ': 'n', 'Ñ': 'N', 'ü': 'u', 'Ü': 'U'
      };
      return s.split('').map((c) => map[c] ?? c).join();
    }
    void text(String s) { b.add(utf8.encode(clean(s))); feed(); }
    void writeWrapped(String prefix, String value) {
      final full = clean('$prefix$value');
      final runes = full.runes.toList();
      for (var i = 0; i < runes.length; i += lineWidth) {
        final end = (i + lineWidth < runes.length) ? i + lineWidth : runes.length;
        final chunk = String.fromCharCodes(runes.sublist(i, end));
        text(chunk);
      }
    }
    String sep() => ''.padLeft(lineWidth, '=');

    init();
    // Preferencia: imprimir logo en cierre (ESC/POS)
    bool withLogo = true;
    try {
      final sp = await SharedPreferences.getInstance();
      withLogo = sp.getBool('print_logo_escpos') ?? true;
    } catch (_) {}
    // Intentar imprimir logo pequeño arriba
    if (withLogo) {
      try {
        final data = await rootBundle.load('assets/icons/app_icon_foreground.png');
        final decoded = img.decodeImage(Uint8List.view(data.buffer));
        if (decoded != null) {
          // Elegir ancho objetivo según lineWidth (80mm ~ 576px, 58mm ~ 384px)
          final targetW = lineWidth >= 48 ? 576 : 384;
          final scaled = img.copyResize(decoded, width: targetW, interpolation: img.Interpolation.average);
          _appendRasterImage(b, scaled);
          feed();
        }
      } catch (_) {}
    }
    alignCenter(); boldOn();
    text(sep());
    sizeDouble(); text('CIERRE DE CAJA'); sizeNormal();
    text(sep());
    alignLeft(); boldOff();
    text('Codigo caja: ${c['codigo_caja'] ?? ''}');
    if ((c['estado'] as String?) != null) text('Estado: ${c['estado']}');
    text('Fecha apertura: ${(c['fecha'] ?? '')} ${(c['hora_apertura'] ?? '')}');
  text('Cajero apertura: ${c['cajero_apertura'] ?? ''}');
    text('Disciplina: ${c['disciplina'] ?? ''}');
    if (descripcionEvento.isNotEmpty) writeWrapped('Descripcion evento: ', descripcionEvento);
    final cierreDt = (c['cierre_dt'] as String?);
  if (cierreDt != null) text('Fecha cierre: $cierreDt');
  final cajCierre = (c['cajero_cierre'] as String?);
  if (cajCierre != null && cajCierre.isNotEmpty) text('Cajero de cierre: $cajCierre');
    if (obsApertura.isNotEmpty) writeWrapped('Obs. apertura: ', obsApertura);
    if (obsCierre.isNotEmpty) writeWrapped('Obs. cierre: ', obsCierre);
    feed();
    boldOn(); text('TOTALES POR MEDIO DE PAGO'); boldOff();
    for (final m in totalesMp) {
      final mpdesc = (m['mp_desc'] as String?) ?? 'MP ${m['mp']}';
      final tot = ((m['total'] as num?) ?? 0).toDouble();
      text('$mpdesc: ${_formatCurrency(tot)}');
    }
  // TOTAL más grande
  sizeDouble(); boldOn(); text('TOTAL: ${_formatCurrency(((resumen['total'] as num?) ?? 0).toDouble())}'); boldOff(); sizeNormal();
    feed();
    text('Fondo inicial: ${_formatCurrency(fondo)}');
    boldOn(); text('Diferencia: ${_formatCurrency(diferencia)}'); boldOff();
  text('Entradas vendidas: $entradasVendidas');
    text('Tickets anulados: ${(resumen['tickets']['anulados'] ?? 0)}');
    feed();
    boldOn(); text('ITEMS VENDIDOS:'); boldOff();
    for (final p in porProd) {
      final name = (p['nombre'] ?? '').toString();
      final cant = (p['cantidad'] ?? 0).toString();
      final tot = ((p['total'] as num?) ?? 0).toDouble();
  text('($name x $cant) = ${_formatCurrency(tot)}');
    }
    feed(2);
    b.add([0x1D, 0x56, 0x42, 0x00]); // corte parcial
    return Uint8List.fromList(b.toBytes());
  }

  // Convierte una imagen en formato ESC/POS raster (GS v 0)
  void _appendRasterImage(BytesBuilder b, img.Image image) {
    // Convertir a blanco y negro con umbral simple
    final grayscale = img.grayscale(image);
    // Reducir altura si es muy grande (para tickets)
    final maxH = 160; // aprox. 160px de alto
    final input = grayscale.height > maxH
        ? img.copyResize(grayscale, height: maxH, interpolation: img.Interpolation.average)
        : grayscale;

    final width = input.width;
    final height = input.height;
    final bytesPerRow = (width + 7) >> 3; // width/8 redondeado hacia arriba

    // Preparar encabezado ESC/POS: GS v 0 m xL xH yL yH
    // m=0 -> normal
    b.add([0x1D, 0x76, 0x30, 0x00]);
    final xL = bytesPerRow & 0xFF;
    final xH = (bytesPerRow >> 8) & 0xFF;
    final yL = height & 0xFF;
    final yH = (height >> 8) & 0xFF;
    b.add([xL, xH, yL, yH]);

    // Volcar pixeles, 1=negro
    for (int y = 0; y < height; y++) {
      int bit = 0;
      int byteVal = 0;
      for (int x = 0; x < width; x++) {
        final p = input.getPixel(x, y);
        final luma = img.getLuminance(p); // 0..255
        final isBlack = luma < 180; // umbral
        byteVal = (byteVal << 1) | (isBlack ? 1 : 0);
        bit++;
        if (bit == 8) {
          b.add([byteVal]);
          bit = 0;
          byteVal = 0;
        }
      }
      if (bit != 0) {
        // Relleno final de la fila si no múltiplo de 8
        byteVal <<= (8 - bit);
        b.add([byteVal]);
      }
    }
  }

  /// Intenta imprimir por USB; si falla, abre PDF del sistema
  Future<bool> printTicketUsbOrPdf(int ticketId) async {
    try {
      final bytes = await buildTicketEscPos(ticketId);
      if (bytes.isNotEmpty) {
        final ok = await _usb.printBytes(bytes);
        if (ok) return true;
      }
    } catch (_) {
      // fallback a PDF
    }
    await printTicket(ticketId);
    return false; // no se pudo por USB
  }

  /// Solo USB: retorna true si imprimió; no hace fallback
  Future<bool> printTicketUsbOnly(int ticketId) async {
    try {
      final bytes = await buildTicketEscPos(ticketId);
      if (bytes.isEmpty) return false;
      return await _usb.printBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  Future<bool> printVentaTicketsForVentaUsbOrPdf(int ventaId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('tickets', columns: ['id'], where: 'venta_id=?', whereArgs: [ventaId], orderBy: 'id');
    bool anyUsb = false;
    for (final r in rows) {
      final id = r['id'] as int;
      final ok = await printTicketUsbOrPdf(id);
      anyUsb = anyUsb || ok;
    }
    return anyUsb;
  }

  Future<bool> printVentaTicketsForVentaUsbOnly(int ventaId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('tickets', columns: ['id'], where: 'venta_id=?', whereArgs: [ventaId], orderBy: 'id');
    bool allOk = true;
    for (final r in rows) {
      final id = r['id'] as int;
      final ok = await printTicketUsbOnly(id).timeout(const Duration(seconds: 4), onTimeout: () => false);
      allOk = allOk && ok;
    }
    return allOk;
  }

  Future<bool> printCajaResumenUsbOrPdf(int cajaId) async {
    try {
      final bytes = await buildCajaResumenEscPos(cajaId);
      if (bytes.isNotEmpty) {
        final ok = await _usb.printBytes(bytes);
        if (ok) return true;
      }
    } catch (_) {}
    await printCajaResumen(cajaId);
    return false;
  }

  Future<bool> printCajaResumenUsbOnly(int cajaId) async {
    try {
      final bytes = await buildCajaResumenEscPos(cajaId);
      if (bytes.isEmpty) return false;
      return await _usb.printBytes(bytes);
    } catch (_) {
      return false;
    }
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
