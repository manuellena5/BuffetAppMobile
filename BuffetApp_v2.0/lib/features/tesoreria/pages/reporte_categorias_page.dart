import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/reporte_categorias_service.dart';
import '../../shared/format.dart';

/// Pantalla de Reportes de Movimientos por Categorías
class ReporteCategoriasPage extends StatefulWidget {
  const ReporteCategoriasPage({super.key});

  @override
  State<ReporteCategoriasPage> createState() => _ReporteCategoriasPageState();
}

class _ReporteCategoriasPageState extends State<ReporteCategoriasPage> {
  DateTime _mesSeleccionado = DateTime.now();
  bool _usandoFiltroPersonalizado = false;
  DateTime? _fechaDesdePersonalizada;
  DateTime? _fechaHastaPersonalizada;
  
  List<Map<String, dynamic>> _datos = [];
  Map<String, double> _totales = {
    'ingresos': 0.0,
    'egresos': 0.0,
    'saldo': 0.0,
  };
  
  bool _loading = false;
  bool _exportando = false;
  
  DateTime get _fechaDesde => _usandoFiltroPersonalizado && _fechaDesdePersonalizada != null
      ? _fechaDesdePersonalizada!
      : DateTime(_mesSeleccionado.year, _mesSeleccionado.month, 1);
      
  DateTime get _fechaHasta => _usandoFiltroPersonalizado && _fechaHastaPersonalizada != null
      ? _fechaHastaPersonalizada!
      : DateTime(_mesSeleccionado.year, _mesSeleccionado.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _loading = true);
    try {
      final datos = await ReporteCategoriasService.obtenerResumenPorCategoria(
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      
      final totales = await ReporteCategoriasService.obtenerTotalesGenerales(
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      
      setState(() {
        _datos = datos;
        _totales = totales;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  Future<void> _seleccionarFechaDesde() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaDesde,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (fecha != null) {
      setState(() {
        _usandoFiltroPersonalizado = true;
        _fechaDesdePersonalizada = fecha;
      });
      _cargarDatos();
    }
  }

  Future<void> _seleccionarFechaHasta() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaHasta,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (fecha != null) {
      setState(() {
        _usandoFiltroPersonalizado = true;
        _fechaHastaPersonalizada = fecha;
      });
      _cargarDatos();
    }
  }

  void _aplicarFiltroRapido(String periodo) {
    final ahora = DateTime.now();
    
    switch (periodo) {
      case 'anio_actual':
        setState(() {
          _usandoFiltroPersonalizado = true;
          _fechaDesdePersonalizada = DateTime(ahora.year, 1, 1);
          _fechaHastaPersonalizada = ahora;
        });
        break;
    }
    
    _cargarDatos();
  }
  
  void _cambiarMes(int delta) {
    setState(() {
      _usandoFiltroPersonalizado = false;
      _mesSeleccionado = DateTime(
        _mesSeleccionado.year,
        _mesSeleccionado.month + delta,
      );
    });
    _cargarDatos();
  }
  
  void _irMesActual() {
    setState(() {
      _usandoFiltroPersonalizado = false;
      _mesSeleccionado = DateTime.now();
    });
    _cargarDatos();
  }

  Future<void> _exportarExcel() async {
    setState(() => _exportando = true);
    
    try {
      // Generar contenido CSV
      final buffer = StringBuffer();
      
      // Header del reporte
      buffer.writeln('Reporte de Movimientos por Categorías');
      buffer.writeln('Período: ${DateFormat('dd/MM/yyyy').format(_fechaDesde)} - ${DateFormat('dd/MM/yyyy').format(_fechaHasta)}');
      buffer.writeln('Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
      buffer.writeln('');
      
      // Totales generales
      buffer.writeln('TOTALES GENERALES');
      buffer.writeln('Ingresos,${formatCurrency(_totales['ingresos'] ?? 0)}');
      buffer.writeln('Egresos,${formatCurrency(_totales['egresos'] ?? 0)}');
      buffer.writeln('Saldo,${formatCurrency(_totales['saldo'] ?? 0)}');
      buffer.writeln('');
      
      // Tabla de categorías
      buffer.writeln('DETALLE POR CATEGORÍAS');
      buffer.writeln('Categoría,Ingresos,Egresos,Saldo,Cantidad Mov.');
      
      for (final row in _datos) {
        final categoria = row['categoria'] as String;
        final ingresos = (row['total_ingresos'] as num?)?.toDouble() ?? 0.0;
        final egresos = (row['total_egresos'] as num?)?.toDouble() ?? 0.0;
        final saldo = (row['saldo'] as num?)?.toDouble() ?? 0.0;
        final cantidad = row['cantidad_movimientos'] as int;
        
        buffer.writeln(
          '$categoria,'
          '${formatCurrency(ingresos)},'
          '${formatCurrency(egresos)},'
          '${formatCurrency(saldo)},'
          '$cantidad'
        );
      }
      
      // Guardar archivo
      final fileName = 'reporte_categorias_'
          '${DateFormat('yyyyMMdd').format(_fechaDesde)}_'
          '${DateFormat('yyyyMMdd').format(_fechaHasta)}.csv';
      
      final dir = await _getExportDir();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(buffer.toString());
      
      if (mounted) {
        setState(() => _exportando = false);
        
        // Compartir archivo
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Reporte de Categorías',
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte exportado: ${file.path}'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exportando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  Future<Directory> _getExportDir() async {
    if (Platform.isAndroid) {
      // Intentar carpeta pública de descargas
      try {
        final dl = Directory('/storage/emulated/0/Download');
        if (await dl.exists()) return dl;
      } catch (_) {}
    }
    
    // Fallback a carpeta de documentos de la app
    return await getApplicationDocumentsDirectory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte por Categorías'),
        backgroundColor: Colors.green,
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
            tooltip: 'Exportar a Excel (CSV)',
          ),
        ],
      ),
      body: Column(
        children: [
          // Selector de Mes (tipo carrusel)
          if (!_usandoFiltroPersonalizado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _cambiarMes(-1),
                    tooltip: 'Mes anterior',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        DateFormat('MMMM yyyy', 'es_AR').format(_mesSeleccionado),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _mesSeleccionado.month == DateTime.now().month &&
                            _mesSeleccionado.year == DateTime.now().year
                        ? null
                        : () => _cambiarMes(1),
                    tooltip: 'Mes siguiente',
                  ),
                  IconButton(
                    icon: const Icon(Icons.today),
                    onPressed: () => _irMesActual(),
                    tooltip: 'Mes actual',
                  ),
                ],
              ),
            ),
          
          // Filtros de fecha (solo cuando se usa filtro personalizado)
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filtros personalizados',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (_usandoFiltroPersonalizado)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _usandoFiltroPersonalizado = false;
                              _mesSeleccionado = DateTime.now();
                            });
                            _cargarDatos();
                          },
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _seleccionarFechaDesde,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Desde',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              DateFormat('dd/MM/yyyy').format(_fechaDesde),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: _seleccionarFechaHasta,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Hasta',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              DateFormat('dd/MM/yyyy').format(_fechaHasta),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Año actual'),
                        selected: _usandoFiltroPersonalizado &&
                            _fechaDesdePersonalizada?.year == DateTime.now().year &&
                            _fechaDesdePersonalizada?.month == 1 &&
                            _fechaDesdePersonalizada?.day == 1,
                        onSelected: (_) => _aplicarFiltroRapido('anio_actual'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // KPIs
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildKPI(
                      'Ingresos',
                      formatCurrency(_totales['ingresos'] ?? 0),
                      Colors.green,
                      Icons.arrow_downward,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildKPI(
                      'Egresos',
                      formatCurrency(_totales['egresos'] ?? 0),
                      Colors.red,
                      Icons.arrow_upward,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildKPI(
                      'Saldo',
                      formatCurrency(_totales['saldo'] ?? 0),
                      (_totales['saldo'] ?? 0) >= 0 ? Colors.blue : Colors.orange,
                      Icons.account_balance,
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Tabla de datos
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
                              'No hay movimientos en el período seleccionado',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Ingresos', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Egresos', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Saldo', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Cant.', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _datos.map((row) {
                              final categoria = row['categoria'] as String;
                              final ingresos = (row['total_ingresos'] as num?)?.toDouble() ?? 0.0;
                              final egresos = (row['total_egresos'] as num?)?.toDouble() ?? 0.0;
                              final saldo = (row['saldo'] as num?)?.toDouble() ?? 0.0;
                              final cantidad = row['cantidad_movimientos'] as int;
                              
                              return DataRow(cells: [
                                DataCell(Text(categoria)),
                                DataCell(Text(
                                  formatCurrency(ingresos),
                                  style: const TextStyle(color: Colors.green),
                                )),
                                DataCell(Text(
                                  formatCurrency(egresos),
                                  style: const TextStyle(color: Colors.red),
                                )),
                                DataCell(Text(
                                  formatCurrency(saldo),
                                  style: TextStyle(
                                    color: saldo >= 0 ? Colors.blue : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )),
                                DataCell(Text(cantidad.toString())),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPI(String label, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
