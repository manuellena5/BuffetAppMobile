import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../shared/widgets/responsive_container.dart';
import 'package:intl/intl.dart';
import '../../shared/services/plantel_import_export_service.dart';
import '../../../data/dao/db.dart';

/// Posiciones válidas para jugadores (mantener sincronizado con DB y servicio)
const _posicionesValidas = ['ARQUERO', 'DEFENSOR', 'MEDIOCAMPISTA', 'DELANTERO', 'STAFF_CT'];

/// Roles válidos (mantener sincronizado con DB y servicio)
const _rolesValidos = ['JUGADOR', 'DT', 'AYUDANTE', 'PF', 'OTRO'];

/// Tipos de contratación válidos (mantener sincronizado con DB y servicio)
const _tiposContratacionValidos = ['LOCAL', 'REFUERZO', 'OTRO'];

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
  
  // Jugadores con datos inválidos pendientes de corrección
  List<Map<String, dynamic>> _jugadoresConErrorPosicion = [];
  List<Map<String, dynamic>> _jugadoresConErrorRol = [];
  List<Map<String, dynamic>> _jugadoresConErrorTipoContratacion = [];

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
                    if (_jugadoresConErrorRol.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildAlertaRolesInvalidos(),
                    ],
                    if (_jugadoresConErrorTipoContratacion.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildAlertaTiposContratacionInvalidos(),
                    ],
                    if (_jugadoresConErrorPosicion.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildAlertaPosicionesInvalidas(),
                    ],
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
            _buildInstruccionItem('5', 'Tipo Contratación: LOCAL, REFUERZO, OTRO (solo para jugadores)'),
            _buildInstruccionItem('6', 'Posiciones: ARQUERO, DEFENSOR, MEDIOCAMPISTA, DELANTERO, STAFF_CT (solo jugadores)'),
            _buildInstruccionItem('7', 'Fecha Nacimiento formato: DD/MM/YYYY (ej: 15/03/1995)'),
            _buildInstruccionItem('8', 'Nombres duplicados serán ignorados'),
            _buildInstruccionItem('9', 'Consulte la hoja "_Valores" del template para ver todos los valores permitidos'),
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
            // Tabla con scroll horizontal explícito
            Container(
              constraints: BoxConstraints(
                maxHeight: 400,
                maxWidth: MediaQuery.of(context).size.width - 32,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
                    columns: const [
                      DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Rol', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Tipo Contrat.', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Posición', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Contacto', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('DNI', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('F. Nac.', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                rows: _jugadoresPreview.map((jugador) {
                  final rolInvalido = jugador['rol_invalido'] == true;
                  final tipoContratacionInvalido = jugador['tipo_contratacion_invalido'] == true;
                  final posicionInvalida = jugador['posicion_invalida'] == true;
                  final tieneErrores = rolInvalido || tipoContratacionInvalido || posicionInvalida;
                  
                  return DataRow(
                    color: tieneErrores 
                        ? WidgetStateProperty.all(Colors.orange[50])
                        : null,
                    cells: [
                      DataCell(Text(jugador['nombre']?.toString() ?? '')),
                      DataCell(
                        rolInvalido
                            ? Row(
                                children: [
                                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[800]),
                                  const SizedBox(width: 4),
                                  Text(
                                    jugador['rol']?.toString() ?? '-',
                                    style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
                                  ),
                                ],
                              )
                            : Chip(
                                label: Text(
                                  jugador['rol']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                backgroundColor: _getColorRol(jugador['rol']?.toString()),
                              ),
                      ),
                      DataCell(
                        tipoContratacionInvalido
                            ? Row(
                                children: [
                                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[800]),
                                  const SizedBox(width: 4),
                                  Text(
                                    jugador['tipo_contratacion']?.toString() ?? '-',
                                    style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
                                  ),
                                ],
                              )
                            : Text(jugador['tipo_contratacion']?.toString() ?? '-'),
                      ),
                      DataCell(
                        posicionInvalida
                            ? Row(
                                children: [
                                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[800]),
                                  const SizedBox(width: 4),
                                  Text(
                                    jugador['posicion']?.toString() ?? '-',
                                    style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
                                  ),
                                ],
                              )
                            : Text(jugador['posicion']?.toString() ?? '-'),
                      ),
                      DataCell(Text(jugador['contacto']?.toString() ?? '-')),
                      DataCell(Text(jugador['dni']?.toString() ?? '-')),
                      DataCell(Text(_formatFecha(jugador['fecha_nacimiento']?.toString()))),
                    ],
                  );
                }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertaPosicionesInvalidas() {
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Posiciones inválidas detectadas (${_jugadoresConErrorPosicion.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              'Los siguientes jugadores tienen posiciones que no coinciden con los valores permitidos:',
              style: TextStyle(color: Colors.orange[900]),
            ),
            const SizedBox(height: 12),
            ..._jugadoresConErrorPosicion.map((jugador) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '• ${jugador['nombre']} - Posición: "${jugador['posicion']}"',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _corregirPosicion(jugador),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Corregir'),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Posiciones válidas:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _posicionesValidas.join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertaRolesInvalidos() {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Roles inválidos detectados (${_jugadoresConErrorRol.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              'Los siguientes registros tienen roles que no coinciden con los valores permitidos:',
              style: TextStyle(color: Colors.red[900]),
            ),
            const SizedBox(height: 12),
            ..._jugadoresConErrorRol.map((jugador) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '• ${jugador['nombre']} - Rol: "${jugador['rol']}"',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _corregirRol(jugador),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Corregir'),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Roles válidos:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rolesValidos.join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertaTiposContratacionInvalidos() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tipos de contratación inválidos (${_jugadoresConErrorTipoContratacion.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[900],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              'Los siguientes jugadores tienen tipos de contratación que no coinciden con los valores permitidos:',
              style: TextStyle(color: Colors.amber[900]),
            ),
            const SizedBox(height: 12),
            ..._jugadoresConErrorTipoContratacion.map((jugador) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '• ${jugador['nombre']} - Tipo: "${jugador['tipo_contratacion']}"',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _corregirTipoContratacion(jugador),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Corregir'),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tipos de contratación válidos:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tiposContratacionValidos.join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonesConfirmacion() {
    final tienePendientes = _jugadoresConErrorPosicion.isNotEmpty ||
                            _jugadoresConErrorRol.isNotEmpty ||
                            _jugadoresConErrorTipoContratacion.isNotEmpty;
    
    final totalErrores = _jugadoresConErrorPosicion.length +
                         _jugadoresConErrorRol.length +
                         _jugadoresConErrorTipoContratacion.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tienePendientes)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              border: Border.all(color: Colors.orange),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange[800]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Debe corregir los $totalErrores registros con datos inválidos antes de importar',
                    style: TextStyle(
                      color: Colors.orange[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
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
                onPressed: (_jugadoresPreview.isEmpty || tienePendientes) ? null : _confirmarImportacion,
                icon: const Icon(Icons.check_circle),
                label: Text('Importar ${_jugadoresPreview.length} jugadores'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[600],
                ),
              ),
            ),
          ],
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

      // Separar jugadores válidos de los que tienen errores
      final jugadores = datos['jugadores'] as List<Map<String, dynamic>>;
      final jugadoresValidos = <Map<String, dynamic>>[];
      final jugadoresConErrorPosicion = <Map<String, dynamic>>[];
      final jugadoresConErrorRol = <Map<String, dynamic>>[];
      final jugadoresConErrorTipoContratacion = <Map<String, dynamic>>[];
      
      for (final jugador in jugadores) {
        final tieneErrorRol = jugador['rol_invalido'] == true;
        final tieneErrorTipoContratacion = jugador['tipo_contratacion_invalido'] == true;
        final tieneErrorPosicion = jugador['posicion_invalida'] == true;
        
        if (tieneErrorRol) {
          jugadoresConErrorRol.add(jugador);
        } else if (tieneErrorTipoContratacion) {
          jugadoresConErrorTipoContratacion.add(jugador);
        } else if (tieneErrorPosicion) {
          jugadoresConErrorPosicion.add(jugador);
        } else {
          jugadoresValidos.add(jugador);
        }
      }

      setState(() {
        _jugadoresPreview = jugadoresValidos;
        _jugadoresConErrorPosicion = jugadoresConErrorPosicion;
        _jugadoresConErrorRol = jugadoresConErrorRol;
        _jugadoresConErrorTipoContratacion = jugadoresConErrorTipoContratacion;
        _erroresLectura = datos['errores'] as List<String>;
        _cargando = false;
      });

      if (_jugadoresPreview.isEmpty && 
          _jugadoresConErrorPosicion.isEmpty && 
          _jugadoresConErrorRol.isEmpty &&
          _jugadoresConErrorTipoContratacion.isEmpty &&
          _erroresLectura.isEmpty) {
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

  Future<void> _corregirPosicion(Map<String, dynamic> jugador) async {
    String? posicionSeleccionada;
    
    final resultado = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corregir Posición'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jugador: ${jugador['nombre']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Posición inválida: "${jugador['posicion']}"',
                      style: TextStyle(color: Colors.orange[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Seleccione la posición correcta:'),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setDialogState) {
                return DropdownButtonFormField<String>(
                  value: posicionSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Posición *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sports_soccer),
                  ),
                  items: _posicionesValidas.map((pos) {
                    return DropdownMenuItem(
                      value: pos,
                      child: Text(_nombrePosicion(pos)),
                    );
                  }).toList(),
                  onChanged: (valor) {
                    setDialogState(() {
                      posicionSeleccionada = valor;
                    });
                  },
                  validator: (v) => v == null ? 'Debe seleccionar una posición' : null,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (posicionSeleccionada != null) {
                Navigator.pop(context, posicionSeleccionada);
              }
            },
            child: const Text('Corregir'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      setState(() {
        // Actualizar posición del jugador
        jugador['posicion'] = resultado;
        jugador['posicion_invalida'] = false;
        
        // Mover de la lista de errores a la lista de válidos
        _jugadoresConErrorPosicion.remove(jugador);
        _jugadoresPreview.add(jugador);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Posición corregida para ${jugador['nombre']}: $resultado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _nombrePosicion(String posicion) {
    switch (posicion) {
      case 'ARQUERO':
        return 'Arquero';
      case 'DEFENSOR':
        return 'Defensor';
      case 'MEDIOCAMPISTA':
        return 'Mediocampista';
      case 'DELANTERO':
        return 'Delantero';
      case 'STAFF_CT':
        return 'Staff Cuerpo Técnico';
      default:
        return posicion;
    }
  }

  Future<void> _corregirRol(Map<String, dynamic> jugador) async {
    String? rolSeleccionado;
    
    final resultado = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corregir Rol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Entidad: ${jugador['nombre']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: Colors.red[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rol inválido: "${jugador['rol']}"',
                      style: TextStyle(color: Colors.red[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Seleccione el rol correcto:'),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setDialogState) {
                return DropdownButtonFormField<String>(
                  value: rolSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Rol *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  items: _rolesValidos.map((rol) {
                    return DropdownMenuItem(
                      value: rol,
                      child: Text(_nombreRol(rol)),
                    );
                  }).toList(),
                  onChanged: (valor) {
                    setDialogState(() {
                      rolSeleccionado = valor;
                    });
                  },
                  validator: (v) => v == null ? 'Debe seleccionar un rol' : null,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (rolSeleccionado != null) {
                Navigator.pop(context, rolSeleccionado);
              }
            },
            child: const Text('Corregir'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      setState(() {
        jugador['rol'] = resultado;
        jugador['rol_invalido'] = false;
        
        _jugadoresConErrorRol.remove(jugador);
        _jugadoresPreview.add(jugador);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rol corregido para ${jugador['nombre']}: $resultado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _corregirTipoContratacion(Map<String, dynamic> jugador) async {
    String? tipoSeleccionado;
    
    final resultado = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corregir Tipo de Contratación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jugador: ${jugador['nombre']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, size: 16, color: Colors.amber[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tipo de contratación inválido: "${jugador['tipo_contratacion']}"',
                      style: TextStyle(color: Colors.amber[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Seleccione el tipo de contratación correcto:'),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setDialogState) {
                return DropdownButtonFormField<String>(
                  value: tipoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Contratación *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.assignment),
                  ),
                  items: _tiposContratacionValidos.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(_nombreTipoContratacion(tipo)),
                    );
                  }).toList(),
                  onChanged: (valor) {
                    setDialogState(() {
                      tipoSeleccionado = valor;
                    });
                  },
                  validator: (v) => v == null ? 'Debe seleccionar un tipo' : null,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (tipoSeleccionado != null) {
                Navigator.pop(context, tipoSeleccionado);
              }
            },
            child: const Text('Corregir'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      setState(() {
        jugador['tipo_contratacion'] = resultado;
        jugador['tipo_contratacion_invalido'] = false;
        
        _jugadoresConErrorTipoContratacion.remove(jugador);
        _jugadoresPreview.add(jugador);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tipo de contratación corregido para ${jugador['nombre']}: $resultado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _nombreRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return 'Jugador';
      case 'DT':
        return 'Director Técnico';
      case 'AYUDANTE':
        return 'Ayudante de Campo';
      case 'PF':
        return 'Preparador Físico';
      case 'OTRO':
        return 'Otro';
      default:
        return rol;
    }
  }

  String _nombreTipoContratacion(String tipo) {
    switch (tipo) {
      case 'LOCAL':
        return 'Local';
      case 'REFUERZO':
        return 'Refuerzo';
      case 'OTRO':
        return 'Otro';
      default:
        return tipo;
    }
  }

  void _limpiarSeleccion() {
    setState(() {
      _archivoSeleccionado = null;
      _jugadoresPreview = [];
      _jugadoresConErrorPosicion = [];
      _jugadoresConErrorRol = [];
      _jugadoresConErrorTipoContratacion = [];
      _erroresLectura = [];
      _importacionCompletada = false;
      _resultadoImport = null;
    });
  }

  Future<void> _confirmarImportacion() async {
    // Detectar duplicados antes de confirmar
    final db = await AppDatabase.instance();
    final jugadoresExistentes = await db.query('entidades_plantel');
    final nombresExistentes = jugadoresExistentes
        .map((e) => (e['nombre'] as String?)?.toLowerCase().trim())
        .where((n) => n != null)
        .toSet();
    
    final duplicados = <String>[];
    for (final jugador in _jugadoresPreview) {
      final nombre = (jugador['nombre'] as String?)?.toLowerCase().trim();
      if (nombre != null && nombresExistentes.contains(nombre)) {
        duplicados.add(jugador['nombre'] as String);
      }
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Importación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Desea importar ${_jugadoresPreview.length} jugadores?'),
            const SizedBox(height: 12),
            if (duplicados.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange[800], size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Jugadores duplicados (serán ignorados):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: duplicados.map((nombre) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 16),
                          const SizedBox(width: 4),
                          Expanded(child: Text(nombre)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ] else
              const Text('No se detectaron duplicados.'),
          ],
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
