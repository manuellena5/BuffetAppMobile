import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:excel/excel.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../services/reporte_resumen_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla de Reporte Resumen Mensual (mes a mes del año)
class ReporteResumenMensualPage extends StatefulWidget {
  const ReporteResumenMensualPage({super.key});

  @override
  State<ReporteResumenMensualPage> createState() => _ReporteResumenMensualPageState();
}

class _ReporteResumenMensualPageState extends State<ReporteResumenMensualPage> {
  final int _yearActual = DateTime.now().year;
  String? _unidadGestionNombre;
  
  List<Map<String, dynamic>> _datos = [];
  
  bool _loading = false;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _loading = true);
    
    try {
      final settings = context.read<AppSettings>();
      final unidadGestionId = settings.unidadGestionActivaId;
      
      if (unidadGestionId != null) {
        // Obtener nombre de unidad
        final db = await AppDatabase.instance();
        final rows = await db.query('unidades_gestion',
            columns: ['nombre'],
            where: 'id=?',
            whereArgs: [unidadGestionId],
            limit: 1);
        if (rows.isNotEmpty) {
          _unidadGestionNombre = (rows.first['nombre'] ?? '').toString();
        }
        
        // Obtener datos del resumen mensual
        final datos = await ReporteResumenService.obtenerResumenMensual(
          year: _yearActual,
          unidadGestionId: unidadGestionId,
        );
        
        setState(() {
          _datos = datos;
          _loading = false;
        });
      } else {
        setState(() {
          _datos = [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  Future<void> _exportarExcel() async {
    setState(() => _exportando = true);
    
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      
      final sheet = excel['Resumen Mensual'];
      
      // Estilos
      final headerStyle = CellStyle(
        bold: true,
        fontSize: 12,
        backgroundColorHex: '#2E7D32',
        fontColorHex: '#FFFFFF',
      );
      
      final titleStyle = CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: '#2E7D32',
      );
      
      // Título
      var row = 0;
      final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      titleCell.value = 'Reporte Resumen Mensual - Año $_yearActual';
      titleCell.cellStyle = titleStyle;
      
      row++;
      if (_unidadGestionNombre != null) {
        final unidadCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        unidadCell.value = 'Unidad de Gestión: $_unidadGestionNombre';
        unidadCell.cellStyle = CellStyle(italic: true);
        row++;
      }
      
      final fechaCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      fechaCell.value = 'Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}';
      fechaCell.cellStyle = CellStyle(fontSize: 10, fontColorHex: '#666666');
      
      row += 2;
      
      // Headers
      final headers = ['Mes', 'Ingresos', 'Egresos', 'Saldo'];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = headers[i];
        cell.cellStyle = headerStyle;
      }
      
      row++;
      
      // Datos
      for (final dato in _datos) {
        final mes = dato['mes'] as int;
        final mesNombre = DateFormat('MMMM', 'es_AR').format(DateTime(_yearActual, mes));
        final ingresos = (dato['ingresos'] as num?)?.toDouble() ?? 0.0;
        final egresos = (dato['egresos'] as num?)?.toDouble() ?? 0.0;
        final saldo = (dato['saldo'] as num?)?.toDouble() ?? 0.0;
        
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = 
            '${mesNombre.substring(0, 1).toUpperCase()}${mesNombre.substring(1)}';
        
        final ingresosCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        ingresosCell.value = ingresos;
        ingresosCell.cellStyle = CellStyle(fontColorHex: '#2E7D32');
        
        final egresosCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
        egresosCell.value = egresos;
        egresosCell.cellStyle = CellStyle(fontColorHex: '#C62828');
        
        final saldoCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        saldoCell.value = saldo;
        saldoCell.cellStyle = CellStyle(
          bold: true,
          fontColorHex: saldo >= 0 ? '#1976D2' : '#F57C00',
        );
        
        row++;
      }
      
      // Ajustar anchos
      sheet.setColWidth(0, 20.0);
      sheet.setColWidth(1, 20.0);
      sheet.setColWidth(2, 20.0);
      sheet.setColWidth(3, 20.0);
      
      // Guardar
      final excelBytes = excel.encode();
      if (excelBytes == null) {
        throw Exception('Error al generar archivo Excel');
      }
      
      final filename = 'resumen_mensual_${_unidadGestionNombre ?? 'tesoreria'}_$_yearActual';
      
      final savedPath = await FileSaver.instance.saveFile(
        name: filename,
        bytes: Uint8List.fromList(excelBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      
      if (mounted) {
        setState(() => _exportando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte exportado: $savedPath'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'reporte_mensual.exportar',
        error: e,
        stackTrace: st,
      );
      
      if (mounted) {
        setState(() => _exportando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Resumen Mensual $_yearActual'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _exportando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download),
            onPressed: _exportando ? null : _exportarExcel,
            tooltip: 'Exportar a Excel',
          ),
        ],
      ),
      body: Column(
        children: [
          // Unidad de Gestión
          if (_unidadGestionNombre != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                // border: Border(
                //   top: BorderSide.none,
                //   bottom: BorderSide(color: Colors.grey.shade300),
                //   left: BorderSide.none,
                //   right: BorderSide.none,
                // ),
              ),
              child: Text(
                _unidadGestionNombre!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.purple,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Tabla
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _datos.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No hay datos disponibles',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: Card(
                              elevation: 4,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(Colors.purple.shade50),
                                  border: TableBorder.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  columns: const [
                                    DataColumn(
                                      label: Text(
                                        'Mes',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        'Ingresos',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      numeric: true,
                                    ),
                                    DataColumn(
                                      label: Text(
                                        'Egresos',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      numeric: true,
                                    ),
                                    DataColumn(
                                      label: Text(
                                        'Saldo',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      numeric: true,
                                    ),
                                  ],
                                  rows: _datos.map((dato) {
                                    final mes = dato['mes'] as int;
                                    final mesNombre = DateFormat('MMMM', 'es_AR').format(DateTime(_yearActual, mes));
                                    final ingresos = (dato['ingresos'] as num?)?.toDouble() ?? 0.0;
                                    final egresos = (dato['egresos'] as num?)?.toDouble() ?? 0.0;
                                    final saldo = (dato['saldo'] as num?)?.toDouble() ?? 0.0;
                                    
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                            '${mesNombre.substring(0, 1).toUpperCase()}${mesNombre.substring(1)}',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            Format.money(ingresos),
                                            style: const TextStyle(color: Colors.green),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            Format.money(egresos),
                                            style: const TextStyle(color: Colors.red),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            Format.money(saldo),
                                            style: TextStyle(
                                              color: saldo >= 0 ? Colors.blue : Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
