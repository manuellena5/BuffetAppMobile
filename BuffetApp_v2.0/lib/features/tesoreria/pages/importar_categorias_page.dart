import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../shared/widgets/responsive_container.dart';
import 'package:intl/intl.dart';
import '../services/categoria_import_export_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla para importar categorías desde un archivo Excel.
class ImportarCategoriasPage extends StatefulWidget {
  const ImportarCategoriasPage({super.key});

  @override
  State<ImportarCategoriasPage> createState() => _ImportarCategoriasPageState();
}

class _ImportarCategoriasPageState extends State<ImportarCategoriasPage> {
  final _importSvc = CategoriaImportExportService.instance;

  bool _cargando = false;
  String? _archivoSeleccionado;
  List<Map<String, dynamic>> _categoriasPreview = [];
  List<String> _erroresLectura = [];
  bool _importacionCompletada = false;
  Map<String, dynamic>? _resultadoImport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar Categorías'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Descargar Template',
            onPressed: _descargarTemplate,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 800,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInstrucciones(),
                    const SizedBox(height: 24),
                    if (!_importacionCompletada) ...[
                      _buildSelectorArchivo(),
                      const SizedBox(height: 24),
                      if (_erroresLectura.isNotEmpty) _buildErrores(),
                      if (_categoriasPreview.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildPreview(),
                        const SizedBox(height: 24),
                        _buildBotonesConfirmacion(),
                      ],
                    ],
                    if (_importacionCompletada && _resultadoImport != null) ...[
                      const SizedBox(height: 24),
                      _buildResultado(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInstrucciones() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Instrucciones',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInstruccionItem('1', 'Descargue el template Excel usando el botón ↓ arriba'),
            _buildInstruccionItem('2', 'Complete los datos en la hoja "Categorias"'),
            _buildInstruccionItem('3', 'Columnas REQUERIDAS: Código, Nombre, Tipo'),
            _buildInstruccionItem('4', 'Tipos válidos: INGRESO, EGRESO, AMBOS'),
            _buildInstruccionItem('5', 'Código máximo 10 caracteres'),
            _buildInstruccionItem('6', 'Categorías duplicadas serán ignoradas'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber[900]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Los datos serán validados antes de importar. Revise la previsualización.',
                      style: TextStyle(fontWeight: FontWeight.w500),
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

  Widget _buildInstruccionItem(String numero, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue[700],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                numero,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(texto),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorArchivo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Seleccionar Archivo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (_archivoSeleccionado != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, color: Colors.green[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Archivo seleccionado:',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            _archivoSeleccionado!.split('\\').last,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _limpiarSeleccion,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _seleccionarArchivo,
              icon: const Icon(Icons.upload_file),
              label: Text(
                _archivoSeleccionado == null
                    ? 'Seleccionar archivo Excel'
                    : 'Cambiar archivo',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrores() {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  'Errores encontrados (${_erroresLectura.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[900],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            ..._erroresLectura.map(
              (error) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Previsualización',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Chip(
                  label: Text('${_categoriasPreview.length} categorías'),
                  backgroundColor: Colors.blue[100],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
                columns: const [
                  DataColumn(label: Text('Código', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Icono', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Observación', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _categoriasPreview.map((cat) {
                  return DataRow(
                    cells: [
                      DataCell(Text(cat['codigo']?.toString() ?? '')),
                      DataCell(Text(cat['nombre']?.toString() ?? '')),
                      DataCell(
                        Chip(
                          label: Text(
                            cat['tipo']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: _getColorTipo(cat['tipo']?.toString()),
                        ),
                      ),
                      DataCell(Text(cat['icono']?.toString() ?? '-')),
                      DataCell(
                        SizedBox(
                          width: 200,
                          child: Text(
                            cat['observacion']?.toString() ?? '-',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonesConfirmacion() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _limpiarSeleccion,
            icon: const Icon(Icons.cancel),
            label: const Text('Cancelar'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _categoriasPreview.isEmpty ? null : _confirmarImportacion,
            icon: const Icon(Icons.check_circle),
            label: Text('Importar ${_categoriasPreview.length} categorías'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultado() {
    final creadas = _resultadoImport!['creadas'] as int;
    final duplicados = _resultadoImport!['duplicados'] as List<String>;
    final errores = _resultadoImport!['errores'] as List<String>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              creadas > 0 ? Icons.check_circle : Icons.info_outline,
              size: 64,
              color: creadas > 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 16),
            Text(
              'Importación Completada',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const Divider(height: 32),
            _buildResultadoItem(
              Icons.add_circle,
              'Creadas',
              creadas.toString(),
              Colors.green,
            ),
            if (duplicados.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildResultadoItem(
                Icons.content_copy,
                'Duplicados (ignorados)',
                duplicados.length.toString(),
                Colors.orange,
              ),
              const SizedBox(height: 8),
              ...duplicados.map(
                (nombre) => Padding(
                  padding: const EdgeInsets.only(left: 48, top: 4),
                  child: Text('• $nombre', style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
            if (errores.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildResultadoItem(
                Icons.error,
                'Errores',
                errores.length.toString(),
                Colors.red,
              ),
              const SizedBox(height: 8),
              ...errores.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(left: 48, top: 4),
                  child: Text('• $error', style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, creadas > 0),
              icon: const Icon(Icons.done),
              label: const Text('Finalizar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultadoItem(IconData icon, String label, String valor, Color color) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Chip(
          label: Text(
            valor,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: color.withOpacity(0.2),
        ),
      ],
    );
  }

  Color _getColorTipo(String? tipo) {
    switch (tipo) {
      case 'INGRESO':
        return Colors.green[100]!;
      case 'EGRESO':
        return Colors.red[100]!;
      case 'AMBOS':
        return Colors.orange[100]!;
      default:
        return Colors.grey[200]!;
    }
  }

  Future<void> _descargarTemplate() async {
    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final suggestedName = 'categorias_template_$timestamp.xlsx';
      
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar template de importación',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath == null) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generando template...'),
              ],
            ),
          ),
        );
      }

      final tempPath = await _importSvc.generarTemplate();
      final tempFile = File(tempPath);
      await tempFile.copy(outputPath);
      await tempFile.delete();

      if (mounted) Navigator.pop(context);

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text('Template descargado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El archivo se guardó correctamente en:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    outputPath,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Complete la hoja "Categorias" con los datos y luego selecciónelo para importar.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final directory = File(outputPath).parent.path;
                  await Process.run('explorer', [directory]);
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir carpeta'),
              ),
            ],
          ),
        );
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'importar_categorias.descargar_template',
        error: e.toString(),
        stackTrace: stack,
      );

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red[700]),
                const SizedBox(width: 8),
                const Text('Error'),
              ],
            ),
            content: Text('Error al generar template:\n\n${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _seleccionarArchivo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) return;

      final filePath = result.files.single.path;
      if (filePath == null) {
        throw Exception('No se pudo leer el archivo');
      }

      setState(() {
        _cargando = true;
        _archivoSeleccionado = filePath;
      });

      final datos = await _importSvc.leerArchivoExcel(filePath);

      setState(() {
        _categoriasPreview = datos['categorias'] as List<Map<String, dynamic>>;
        _erroresLectura = datos['errores'] as List<String>;
        _cargando = false;
      });

      if (_categoriasPreview.isEmpty && _erroresLectura.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El archivo no contiene datos válidos.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'importar_categorias.seleccionar_archivo',
        error: e.toString(),
        stackTrace: stack,
      );

      setState(() => _cargando = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al leer archivo: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _limpiarSeleccion() {
    setState(() {
      _archivoSeleccionado = null;
      _categoriasPreview = [];
      _erroresLectura = [];
      _importacionCompletada = false;
      _resultadoImport = null;
    });
  }

  Future<void> _confirmarImportacion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Importación'),
        content: Text(
          '¿Desea importar ${_categoriasPreview.length} categorías?\n\n'
          'Las categorías duplicadas serán ignoradas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);

    try {
      final resultado = await _importSvc.importarCategorias(_categoriasPreview);

      setState(() {
        _importacionCompletada = true;
        _resultadoImport = resultado;
        _cargando = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'importar_categorias.confirmar',
        error: e.toString(),
        stackTrace: stack,
      );

      setState(() => _cargando = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al importar categorías. Revise los logs.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
