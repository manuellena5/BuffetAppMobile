import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../shared/widgets/responsive_container.dart';
import 'package:intl/intl.dart';
import '../../shared/services/plantel_import_export_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla para importar jugadores desde un archivo Excel.
/// Muestra instrucciones, permite seleccionar archivo, previsualizar datos
/// y confirmar importación con validaciones.
class ImportarJugadoresPage extends StatefulWidget {
  const ImportarJugadoresPage({super.key});

  @override
  State<ImportarJugadoresPage> createState() => _ImportarJugadoresPageState();
}

class _ImportarJugadoresPageState extends State<ImportarJugadoresPage> {
  final _importSvc = PlantelImportExportService.instance;

  bool _cargando = false;
  String? _archivoSeleccionado;
  List<Map<String, dynamic>> _jugadoresPreview = [];
  List<String> _erroresLectura = [];
  bool _importacionCompletada = false;
  Map<String, dynamic>? _resultadoImport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar Jugadores'),
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
                    if (_jugadoresPreview.isNotEmpty) ...[
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
            _buildInstruccionItem('2', 'Complete los datos en la hoja "Jugadores"'),
            _buildInstruccionItem('3', 'Columnas REQUERIDAS: Nombre, Rol'),
            _buildInstruccionItem('4', 'Roles válidos: JUGADOR, DT, AYUDANTE, PF, OTRO'),
            _buildInstruccionItem('5', 'Fecha Nacimiento formato: DD/MM/YYYY (ej: 15/03/1995)'),
            _buildInstruccionItem('6', 'Nombres duplicados serán ignorados'),
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
                            _archivoSeleccionado!.split('/').last,
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
                  label: Text('${_jugadoresPreview.length} jugadores'),
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
                  DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Rol', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Contacto', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('DNI', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('F. Nac.', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _jugadoresPreview.map((jugador) {
                  return DataRow(
                    cells: [
                      DataCell(Text(jugador['nombre']?.toString() ?? '')),
                      DataCell(
                        Chip(
                          label: Text(
                            jugador['rol']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: _getColorRol(jugador['rol']?.toString()),
                        ),
                      ),
                      DataCell(Text(jugador['contacto']?.toString() ?? '-')),
                      DataCell(Text(jugador['dni']?.toString() ?? '-')),
                      DataCell(Text(_formatFecha(jugador['fecha_nacimiento']?.toString()))),
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
            onPressed: _jugadoresPreview.isEmpty ? null : _confirmarImportacion,
            icon: const Icon(Icons.check_circle),
            label: Text('Importar ${_jugadoresPreview.length} jugadores'),
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
    final creados = _resultadoImport!['creados'] as int;
    final duplicados = _resultadoImport!['duplicados'] as List<String>;
    final errores = _resultadoImport!['errores'] as List<String>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              creados > 0 ? Icons.check_circle : Icons.info_outline,
              size: 64,
              color: creados > 0 ? Colors.green : Colors.orange,
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
              Icons.person_add,
              'Creados',
              creados.toString(),
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
              onPressed: () => Navigator.pop(context, creados > 0),
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

  Color _getColorRol(String? rol) {
    switch (rol) {
      case 'DT':
        return Colors.purple[100]!;
      case 'JUGADOR':
        return Colors.blue[100]!;
      case 'AYUDANTE':
        return Colors.green[100]!;
      case 'PF':
        return Colors.orange[100]!;
      default:
        return Colors.grey[200]!;
    }
  }

  String _formatFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '-';
    try {
      final dt = DateTime.parse(fecha);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return fecha;
    }
  }

  Future<void> _descargarTemplate() async {
    try {
      // Pedir al usuario dónde guardar el archivo
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final suggestedName = 'plantel_template_$timestamp.xlsx';
      
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar template de importación',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath == null) {
        // Usuario canceló
        return;
      }

      // Mostrar diálogo de progreso
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

      // Generar el archivo en temp
      final tempPath = await _importSvc.generarTemplate();
      
      // Copiar a la ubicación elegida
      final tempFile = File(tempPath);
      await tempFile.copy(outputPath);
      
      // Eliminar temporal
      await tempFile.delete();

      // Cerrar diálogo de progreso
      if (mounted) Navigator.pop(context);

      // Mostrar resultado exitoso
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
                  'Complete la hoja "Jugadores" con los datos y luego selecciónelo para importar.',
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
                  // Abrir explorador en la carpeta
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
        scope: 'importar_jugadores.descargar_template',
        error: e.toString(),
        stackTrace: stack,
      );

      // Cerrar diálogo de progreso si está abierto
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
        _jugadoresPreview = datos['jugadores'] as List<Map<String, dynamic>>;
        _erroresLectura = datos['errores'] as List<String>;
        _cargando = false;
      });

      if (_jugadoresPreview.isEmpty && _erroresLectura.isEmpty) {
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
        scope: 'importar_jugadores.seleccionar_archivo',
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
      _jugadoresPreview = [];
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
          '¿Desea importar ${_jugadoresPreview.length} jugadores?\n\n'
          'Los nombres duplicados serán ignorados.',
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
      final resultado = await _importSvc.importarJugadores(_jugadoresPreview);

      setState(() {
        _importacionCompletada = true;
        _resultadoImport = resultado;
        _cargando = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'importar_jugadores.confirmar',
        error: e.toString(),
        stackTrace: stack,
      );

      setState(() => _cargando = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al importar jugadores. Revise los logs.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
