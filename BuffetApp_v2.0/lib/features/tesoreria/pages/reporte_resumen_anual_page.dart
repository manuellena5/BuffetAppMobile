import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:excel/excel.dart' as excel;
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../services/reporte_resumen_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla de Reporte Resumen Anual
class ReporteResumenAnualPage extends StatefulWidget {
  const ReporteResumenAnualPage({super.key});

  @override
  State<ReporteResumenAnualPage> createState() => _ReporteResumenAnualPageState();
}

class _ReporteResumenAnualPageState extends State<ReporteResumenAnualPage> {
  int _yearSeleccionado = DateTime.now().year;
  String? _unidadGestionNombre;
  
  Map<String, double> _datos = {
    'saldo_inicial': 0.0,
    'ingresos_acumulados': 0.0,
    'egresos_acumulados': 0.0,
    'saldo_actual': 0.0,
  };
  
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
        
        // Obtener datos del resumen
        final datos = await ReporteResumenService.obtenerResumenAnual(
          year: _yearSeleccionado,
          unidadGestionId: unidadGestionId,
        );
        
        setState(() {
          _datos = datos;
          _loading = false;
        });
      } else {
        setState(() {
          _datos = {
            'saldo_inicial': 0.0,
            'ingresos_acumulados': 0.0,
            'egresos_acumulados': 0.0,
            'saldo_actual': 0.0,
          };
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
      final excelFile = excel.Excel.createExcel();
      excelFile.delete('Sheet1');
      
      final sheet = excelFile['Resumen Anual'];
      
      // Estilos
      final headerStyle = excel.CellStyle(
        bold: true,
        fontSize: 14,
        backgroundColorHex: '#2E7D32',
        fontColorHex: '#FFFFFF',
      );
      
      final titleStyle = excel.CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: '#2E7D32',
      );
      
      // Título
      var row = 0;
      final titleCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      titleCell.value = 'Reporte Resumen Anual - Año $_yearSeleccionado';
      titleCell.cellStyle = titleStyle;
      
      row++;
      if (_unidadGestionNombre != null) {
        final unidadCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        unidadCell.value = 'Unidad de Gestión: $_unidadGestionNombre';
        unidadCell.cellStyle = excel.CellStyle(italic: true);
        row++;
      }
      
      final fechaCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      fechaCell.value = 'Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}';
      fechaCell.cellStyle = excel.CellStyle(fontSize: 10, fontColorHex: '#666666');
      
      row += 2;
      
      // Headers
      final headerConcepto = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      headerConcepto.value = 'Concepto';
      headerConcepto.cellStyle = headerStyle;
      
      final headerMonto = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
      headerMonto.value = 'Monto';
      headerMonto.cellStyle = headerStyle;
      
      row++;
      
      // Datos
      final conceptos = [
        {'label': 'Saldo Inicial del Año', 'key': 'saldo_inicial', 'color': '#424242'},
        {'label': 'Ingresos Acumulados', 'key': 'ingresos_acumulados', 'color': '#2E7D32'},
        {'label': 'Egresos Acumulados', 'key': 'egresos_acumulados', 'color': '#C62828'},
        {'label': 'Saldo Actual', 'key': 'saldo_actual', 'color': '#1976D2'},
      ];
      
      for (final concepto in conceptos) {
        final labelCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        labelCell.value = concepto['label'] as String;
        labelCell.cellStyle = excel.CellStyle(bold: true);
        
        final montoCell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        final valor = _datos[concepto['key']] ?? 0.0;
        montoCell.value = valor;
        montoCell.cellStyle = excel.CellStyle(
          bold: true,
          fontColorHex: concepto['color'] as String,
        );
        
        row++;
      }
      
      // Ajustar anchos
      sheet.setColWidth(0, 30.0);
      sheet.setColWidth(1, 25.0);
      
      // Guardar
      final excelBytes = excelFile.encode();
      if (excelBytes == null) {
        throw Exception('Error al generar archivo Excel');
      }
      
      final filename = 'resumen_anual_${_unidadGestionNombre ?? 'tesoreria'}_$_yearSeleccionado';
      
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
        scope: 'reporte_anual.exportar',
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
        title: const Text('Resumen Anual'),
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
          // Selector de Año
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _yearSeleccionado--);
                    _cargarDatos();
                  },
                  tooltip: 'Año anterior',
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Año $_yearSeleccionado',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _yearSeleccionado == DateTime.now().year
                      ? null
                      : () {
                          setState(() => _yearSeleccionado++);
                          _cargarDatos();
                        },
                  tooltip: 'Año siguiente',
                ),
                IconButton(
                  icon: const Icon(Icons.today),
                  onPressed: () {
                    setState(() => _yearSeleccionado = DateTime.now().year);
                    _cargarDatos();
                  },
                  tooltip: 'Año actual',
                ),
              ],
            ),
          ),
          
          // Unidad de Gestión
          if (_unidadGestionNombre != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              child: Text(
                _unidadGestionNombre!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Contenido
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Column(
                          children: [
                            // KPIs
                            _buildKPICard(
                              'Saldo Inicial del Año',
                              _datos['saldo_inicial'] ?? 0.0,
                              Icons.account_balance_wallet,
                              Colors.grey.shade700,
                            ),
                            const SizedBox(height: 16),
                            _buildKPICard(
                              'Ingresos Acumulados',
                              _datos['ingresos_acumulados'] ?? 0.0,
                              Icons.arrow_downward,
                              Colors.green,
                            ),
                            const SizedBox(height: 16),
                            _buildKPICard(
                              'Egresos Acumulados',
                              _datos['egresos_acumulados'] ?? 0.0,
                              Icons.arrow_upward,
                              Colors.red,
                            ),
                            const SizedBox(height: 24),
                            const Divider(thickness: 2),
                            const SizedBox(height: 16),
                            _buildKPICard(
                              'Saldo Actual',
                              _datos['saldo_actual'] ?? 0.0,
                              Icons.account_balance,
                              Colors.blue,
                              destacado: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(
    String label,
    double valor,
    IconData icono,
    Color color, {
    bool destacado = false,
  }) {
    return Card(
      elevation: destacado ? 8 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: destacado ? color.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: destacado ? 16 : 14,
                      color: Colors.grey.shade700,
                      fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Format.money(valor),
                    style: TextStyle(
                      fontSize: destacado ? 28 : 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
