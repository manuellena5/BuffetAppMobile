import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../shared/format.dart';

/// Servicio de generación de PDFs para reportes de Tesorería.
///
/// Genera documentos PDF para:
/// - Resumen mensual (12 meses del año)
/// - Resumen por categorías
/// - Reporte plantel mensual
///
/// Sigue el patrón de PrintService (buffet) con funciones `build*Pdf()` → `Future<Uint8List>`.
class ReportePdfService {
  ReportePdfService._();
  static final instance = ReportePdfService._();

  // ───────────── Estilos ─────────────
  static pw.TextStyle _title() => pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.teal800,
      );

  static pw.TextStyle _subtitle() => pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.normal,
        color: PdfColors.grey700,
      );

  static pw.TextStyle _headerCell() => pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      );

  static pw.TextStyle _cell() => const pw.TextStyle(fontSize: 9);

  static pw.TextStyle _cellBold() => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.TextStyle _totalRow() => pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.teal900,
      );

  // ───────────── Helpers comunes ─────────────
  pw.Widget _buildHeader({
    required String titulo,
    String? unidadGestion,
  }) {
    final fecha = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(titulo, style: _title()),
        if (unidadGestion != null)
          pw.Text('Unidad de Gestión: $unidadGestion', style: _subtitle()),
        pw.Text('Generado: $fecha',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'BuffetApp — Tesorería',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
        pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
      ],
    );
  }

  // ───────────── D.3: Resumen Mensual ─────────────

  /// Genera PDF con el resumen mes a mes (ingresos, egresos, saldo) de un año.
  ///
  /// [datos] es la lista de mapas con keys: mes, ingresos, egresos, saldo.
  /// [year] es el año del reporte.
  Future<Uint8List> buildResumenMensualPdf({
    required List<Map<String, dynamic>> datos,
    required int year,
    String? unidadGestion,
  }) async {
    final doc = pw.Document(
      title: 'Resumen Mensual $year',
      author: 'BuffetApp',
    );

    double totalIngresos = 0;
    double totalEgresos = 0;

    final tableRows = <List<String>>[];
    for (final dato in datos) {
      final mes = dato['mes'] as int;
      final mesNombre = DateFormat('MMMM', 'es_AR').format(DateTime(year, mes));
      final ingresos = (dato['ingresos'] as num?)?.toDouble() ?? 0.0;
      final egresos = (dato['egresos'] as num?)?.toDouble() ?? 0.0;
      final saldo = (dato['saldo'] as num?)?.toDouble() ?? 0.0;

      totalIngresos += ingresos;
      totalEgresos += egresos;

      tableRows.add([
        '${mesNombre[0].toUpperCase()}${mesNombre.substring(1)}',
        Format.money(ingresos),
        Format.money(egresos),
        Format.money(saldo),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: _buildFooter,
        build: (context) => [
          _buildHeader(
            titulo: 'Resumen Mensual — Año $year',
            unidadGestion: unidadGestion,
          ),
          pw.TableHelper.fromTextArray(
            context: context,
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerRight,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            headerStyle: _headerCell(),
            cellStyle: _cell(),
            headerCount: 1,
            headers: ['Mes', 'Ingresos', 'Egresos', 'Saldo'],
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            data: [
              ...tableRows,
              // Fila totales
              [
                'TOTAL',
                Format.money(totalIngresos),
                Format.money(totalEgresos),
                Format.money(totalIngresos - totalEgresos),
              ],
            ],
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Imprime el resumen mensual con diálogo del sistema.
  Future<void> printResumenMensual({
    required List<Map<String, dynamic>> datos,
    required int year,
    String? unidadGestion,
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) => buildResumenMensualPdf(
        datos: datos,
        year: year,
        unidadGestion: unidadGestion,
      ),
      name: 'resumen_mensual_$year.pdf',
    );
  }

  /// Comparte el resumen mensual como PDF.
  Future<void> shareResumenMensual({
    required List<Map<String, dynamic>> datos,
    required int year,
    String? unidadGestion,
  }) async {
    final bytes = await buildResumenMensualPdf(
      datos: datos,
      year: year,
      unidadGestion: unidadGestion,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'resumen_mensual_$year.pdf',
    );
  }

  // ───────────── D.4: Reporte por Categorías ─────────────

  /// Genera PDF con el resumen por categoría de movimientos.
  ///
  /// [datos] lista de mapas con keys: categoria, ingresos, egresos, saldo, cantidad.
  /// [totales] mapa con keys: ingresos, egresos, saldo, cantidad.
  /// [mesAnio] descripción del período (ej: "Marzo 2026" o "Enero - Marzo 2026").
  Future<Uint8List> buildReporteCategoriasPdf({
    required List<Map<String, dynamic>> datos,
    required Map<String, dynamic> totales,
    required String mesAnio,
    String? unidadGestion,
  }) async {
    final doc = pw.Document(
      title: 'Reporte por Categorías - $mesAnio',
      author: 'BuffetApp',
    );

    final tableRows = <List<String>>[];
    for (final dato in datos) {
      final categoria = dato['categoria']?.toString() ?? 'Sin categoría';
      final ingresos = (dato['ingresos'] as num?)?.toDouble() ?? 0.0;
      final egresos = (dato['egresos'] as num?)?.toDouble() ?? 0.0;
      final saldo = (dato['saldo'] as num?)?.toDouble() ?? 0.0;
      final cantidad = (dato['cantidad'] as num?)?.toInt() ?? 0;

      tableRows.add([
        categoria,
        cantidad.toString(),
        Format.money(ingresos),
        Format.money(egresos),
        Format.money(saldo),
      ]);
    }

    final totalIngresos = (totales['ingresos'] as num?)?.toDouble() ?? 0.0;
    final totalEgresos = (totales['egresos'] as num?)?.toDouble() ?? 0.0;
    final totalSaldo = (totales['saldo'] as num?)?.toDouble() ?? 0.0;
    final totalCantidad = (totales['cantidad'] as num?)?.toInt() ?? 0;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: _buildFooter,
        build: (context) => [
          _buildHeader(
            titulo: 'Reporte por Categorías — $mesAnio',
            unidadGestion: unidadGestion,
          ),
          // KPIs
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildKpiBox('Ingresos', Format.money(totalIngresos), PdfColors.green700),
              _buildKpiBox('Egresos', Format.money(totalEgresos), PdfColors.red700),
              _buildKpiBox('Saldo', Format.money(totalSaldo),
                  totalSaldo >= 0 ? PdfColors.blue700 : PdfColors.orange700),
              _buildKpiBox('Movimientos', totalCantidad.toString(), PdfColors.grey700),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            context: context,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            headerStyle: _headerCell(),
            cellStyle: _cell(),
            headers: ['Categoría', 'Cant.', 'Ingresos', 'Egresos', 'Saldo'],
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            data: [
              ...tableRows,
              [
                'TOTAL',
                totalCantidad.toString(),
                Format.money(totalIngresos),
                Format.money(totalEgresos),
                Format.money(totalSaldo),
              ],
            ],
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Comparte el reporte de categorías como PDF.
  Future<void> shareReporteCategorias({
    required List<Map<String, dynamic>> datos,
    required Map<String, dynamic> totales,
    required String mesAnio,
    String? unidadGestion,
  }) async {
    final bytes = await buildReporteCategoriasPdf(
      datos: datos,
      totales: totales,
      mesAnio: mesAnio,
      unidadGestion: unidadGestion,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'reporte_categorias_${mesAnio.replaceAll(' ', '_')}.pdf',
    );
  }

  // ───────────── D.5: Reporte Plantel Mensual ─────────────

  /// Genera PDF con el reporte de plantel para un mes.
  ///
  /// [entidades] lista de mapas con info de cada entidad del plantel.
  /// [resumen] mapa con totales: totalComprometido, totalPagado, totalPendiente.
  /// [mes] y [anio] para el título.
  Future<Uint8List> buildReportePlantelPdf({
    required List<Map<String, dynamic>> entidades,
    required Map<String, dynamic> resumen,
    required int mes,
    required int anio,
    String? unidadGestion,
  }) async {
    final doc = pw.Document(
      title: 'Reporte Plantel - ${DateFormat('MMMM yyyy', 'es_AR').format(DateTime(anio, mes))}',
      author: 'BuffetApp',
    );

    final mesNombre = DateFormat('MMMM yyyy', 'es_AR').format(DateTime(anio, mes));
    final mesCapitalizado = '${mesNombre[0].toUpperCase()}${mesNombre.substring(1)}';

    final totalComprometido = (resumen['totalComprometido'] as num?)?.toDouble() ?? 0.0;
    final totalPagado = (resumen['totalPagado'] as num?)?.toDouble() ?? 0.0;
    final totalPendiente = (resumen['totalPendiente'] as num?)?.toDouble() ?? 0.0;

    final tableRows = <List<String>>[];
    for (final e in entidades) {
      final nombre = e['nombre']?.toString() ?? '';
      final alias = e['alias']?.toString() ?? '';
      final displayName = alias.isNotEmpty ? '$nombre ($alias)' : nombre;
      final rol = e['rol']?.toString() ?? '';
      final comprometido = (e['totalComprometido'] as num?)?.toDouble() ?? 0.0;
      final pagado = (e['pagado'] as num?)?.toDouble() ?? 0.0;
      final pendiente = (e['esperado'] as num?)?.toDouble() ?? 0.0;
      final movIngresos = (e['movimientos_ingresos'] as num?)?.toDouble() ?? 0.0;
      final movEgresos = (e['movimientos_egresos'] as num?)?.toDouble() ?? 0.0;

      tableRows.add([
        displayName,
        rol,
        Format.money(comprometido),
        Format.money(pagado),
        Format.money(pendiente),
        Format.money(movIngresos - movEgresos),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        footer: _buildFooter,
        build: (context) => [
          _buildHeader(
            titulo: 'Reporte Plantel — $mesCapitalizado',
            unidadGestion: unidadGestion,
          ),
          // KPIs
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildKpiBox('Comprometido', Format.money(totalComprometido), PdfColors.blue700),
              _buildKpiBox('Pagado', Format.money(totalPagado), PdfColors.green700),
              _buildKpiBox('Pendiente', Format.money(totalPendiente), PdfColors.orange700),
              _buildKpiBox('Entidades', entidades.length.toString(), PdfColors.grey700),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            context: context,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            headerStyle: _headerCell(),
            cellStyle: _cell(),
            headers: ['Nombre', 'Rol', 'Comprometido', 'Pagado', 'Pendiente', 'Mov. Neto'],
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            data: [
              ...tableRows,
              [
                'TOTAL',
                '${entidades.length}',
                Format.money(totalComprometido),
                Format.money(totalPagado),
                Format.money(totalPendiente),
                '',
              ],
            ],
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Comparte el reporte plantel como PDF.
  Future<void> shareReportePlantel({
    required List<Map<String, dynamic>> entidades,
    required Map<String, dynamic> resumen,
    required int mes,
    required int anio,
    String? unidadGestion,
  }) async {
    final mesStr = DateFormat('yyyy_MM').format(DateTime(anio, mes));
    final bytes = await buildReportePlantelPdf(
      entidades: entidades,
      resumen: resumen,
      mes: mes,
      anio: anio,
      unidadGestion: unidadGestion,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'reporte_plantel_$mesStr.pdf',
    );
  }

  // ───────────── Widget helpers ─────────────

  pw.Widget _buildKpiBox(String label, String value, PdfColor color) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(label,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
