import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../features/shared/services/acuerdos_service.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../../features/shared/format.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import '../../shared/widgets/responsive_container.dart';

/// FASE 18.6: Página para crear un nuevo acuerdo financiero
/// 
/// Características:
/// - Formulario guiado con selección de modalidad
/// - Preview de compromisos a generar
/// - Validaciones en tiempo real
/// - Adjuntos (contratos)
class CrearAcuerdoPage extends StatefulWidget {
  const CrearAcuerdoPage({super.key});

  @override
  State<CrearAcuerdoPage> createState() => _CrearAcuerdoPageState();
}

class _CrearAcuerdoPageState extends State<CrearAcuerdoPage> {
  final _formKey = GlobalKey<FormState>();
  final _plantelService = PlantelService.instance;
  
  // Controllers
  final _nombreController = TextEditingController();
  final _montoTotalController = TextEditingController();
  final _montoPeriodicoController = TextEditingController();
  final _cuotasController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  // Form values
  String _tipo = 'EGRESO';
  String _modalidad = 'RECURRENTE'; // MONTO_TOTAL_CUOTAS | RECURRENTE
  String? _codigoCategoria;
  String _frecuencia = 'MENSUAL';
  DateTime _fechaInicio = DateTime.now();
  DateTime? _fechaFin;
  int _unidadGestionId = 1;
  int? _entidadPlantelId;
  
  // Preview
  bool _mostrarPreview = false;
  List<Map<String, dynamic>> _compromisosPreview = [];
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  
  // Catálogos
  List<Map<String, dynamic>> _frecuencias = [];
  List<Map<String, dynamic>> _unidades = [];
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _entidadesPlantel = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoTotalController.dispose();
    _montoPeriodicoController.dispose();
    _cuotasController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    
    try {
      final db = await AppDatabase.instance();
      
      final frecuencias = await db.query('frecuencias', orderBy: 'dias');
      final unidades = await db.query('unidades_gestion', where: 'activo = 1', orderBy: 'nombre');
      final categorias = await CategoriaMovimientoService.obtenerCategorias();
      final entidades = await _plantelService.listarEntidades();
      
      setState(() {
        _frecuencias = frecuencias;
        _unidades = unidades;
        _categorias = categorias;
        _entidadesPlantel = entidades;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'crear_acuerdo_page.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
      );
      
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar datos iniciales'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generarPreview() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _mostrarPreview = true);
    
    try {
      // Crear acuerdo temporal para generar preview
      final tempId = await AcuerdosService.crearAcuerdo(
        unidadGestionId: _unidadGestionId,
        entidadPlantelId: _entidadPlantelId,
        nombre: _nombreController.text.trim(),
        tipo: _tipo,
        modalidad: _modalidad,
        montoTotal: _modalidad == 'MONTO_TOTAL_CUOTAS' 
            ? double.tryParse(_montoTotalController.text)
            : null,
        montoPeriodico: _modalidad == 'RECURRENTE'
            ? double.tryParse(_montoPeriodicoController.text)
            : null,
        frecuencia: _frecuencia,
        cuotas: _modalidad == 'MONTO_TOTAL_CUOTAS'
            ? int.tryParse(_cuotasController.text)
            : null,
        fechaInicio: _formatDate(_fechaInicio),
        fechaFin: _fechaFin != null ? _formatDate(_fechaFin!) : null,
        categoria: _codigoCategoria ?? 'OTROS',
        observaciones: _observacionesController.text.trim().isEmpty
            ? null
            : _observacionesController.text.trim(),
      );
      
      final preview = await AcuerdosService.previewCompromisos(tempId);
      
      // Eliminar acuerdo temporal
      await AcuerdosService.desactivarAcuerdo(tempId);
      
      setState(() {
        _compromisosPreview = preview;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'crear_acuerdo_page.generar_preview',
        error: e.toString(),
        stackTrace: stack,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar preview: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _guardarAcuerdo() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Modal de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.orange[700]),
            const SizedBox(width: 12),
            const Text('Confirmar Creación'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Desea crear el siguiente acuerdo?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            _buildResumenAcuerdo(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    
    setState(() => _isSubmitting = true);
    
    try {
      final acuerdoId = await AcuerdosService.crearAcuerdo(
        unidadGestionId: _unidadGestionId,
        entidadPlantelId: _entidadPlantelId,
        nombre: _nombreController.text.trim(),
        tipo: _tipo,
        modalidad: _modalidad,
        montoTotal: _modalidad == 'MONTO_TOTAL_CUOTAS' 
            ? double.tryParse(_montoTotalController.text)
            : null,
        montoPeriodico: _modalidad == 'RECURRENTE'
            ? double.tryParse(_montoPeriodicoController.text)
            : null,
        frecuencia: _frecuencia,
        cuotas: _modalidad == 'MONTO_TOTAL_CUOTAS'
            ? int.tryParse(_cuotasController.text)
            : null,
        fechaInicio: _formatDate(_fechaInicio),
        fechaFin: _fechaFin != null ? _formatDate(_fechaFin!) : null,
        categoria: _codigoCategoria ?? 'OTROS',
        observaciones: _observacionesController.text.trim().isEmpty
            ? null
            : _observacionesController.text.trim(),
      );
      
      // Generar compromisos automáticamente
      final cuotasGeneradas = await AcuerdosService.generarCompromisos(acuerdoId);
      
      setState(() => _isSubmitting = false);
      
      // Modal de éxito
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 32),
                const SizedBox(width: 12),
                const Text('Acuerdo Creado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El acuerdo se creó exitosamente',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insert_drive_file, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'ID Acuerdo: $acuerdoId',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 16),
                          const SizedBox(width: 8),
                          Text('Compromisos generados: $cuotasGeneradas'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'crear_acuerdo_page.guardar_acuerdo',
        error: e.toString(),
        stackTrace: stack,
      );
      
      setState(() => _isSubmitting = false);
      
      // Modal de error
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red[700], size: 32),
                const SizedBox(width: 12),
                const Text('Error'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No se pudo crear el acuerdo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(
                    e.toString(),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Acuerdo'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 800,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                  _buildSeccionBasica(),
                  const Divider(height: 32),
                  _buildSeccionMontos(),
                  const Divider(height: 32),
                  _buildSeccionFechas(),
                  const Divider(height: 32),
                  _buildSeccionOpcional(),
                  const SizedBox(height: 24),
                  
                  if (_mostrarPreview) ...[
                    const Divider(height: 32),
                    _buildPreview(),
                    const SizedBox(height: 24),
                  ],
                  
                  _buildBotones(),
                  const SizedBox(height: 32),
                ],
              ),
              ),
            ),
    );
  }

  Widget _buildSeccionBasica() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Información Básica', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _nombreController,
          decoration: const InputDecoration(
            labelText: 'Nombre del Acuerdo *',
            hintText: 'Ej: Sueldo DT - Juan Pérez',
            border: OutlineInputBorder(),
          ),
          validator: (val) => val?.trim().isEmpty ?? true ? 'Requerido' : null,
        ),
        const SizedBox(height: 16),
        
        DropdownButtonFormField<int>(
          value: _unidadGestionId,
          decoration: const InputDecoration(
            labelText: 'Unidad de Gestión *',
            border: OutlineInputBorder(),
          ),
          items: _unidades.map((u) => DropdownMenuItem(
            value: u['id'] as int,
            child: Text(u['nombre'].toString()),
          )).toList(),
          onChanged: (val) => setState(() => _unidadGestionId = val!),
        ),
        const SizedBox(height: 16),
        
        DropdownButtonFormField<int?>(
          value: _entidadPlantelId,
          decoration: const InputDecoration(
            labelText: 'Jugador / Técnico (opcional)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Ninguno')),
            ..._entidadesPlantel.map((e) => DropdownMenuItem(
              value: e['id'] as int,
              child: Text('${e['nombre']} (${e['rol']})'),
            )),
          ],
          onChanged: (val) => setState(() => _entidadPlantelId = val),
        ),
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'INGRESO', label: Text('Ingreso'), icon: Icon(Icons.arrow_downward)),
                  ButtonSegment(value: 'EGRESO', label: Text('Egreso'), icon: Icon(Icons.arrow_upward)),
                ],
                selected: {_tipo},
                onSelectionChanged: (val) => setState(() => _tipo = val.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        DropdownButtonFormField<String?>(
          value: _codigoCategoria,
          decoration: const InputDecoration(
            labelText: 'Categoría *',
            border: OutlineInputBorder(),
          ),
          items: _categorias
              .where((c) {
                final tipo = c['tipo'] as String;
                return tipo == 'AMBOS' || tipo == _tipo;
              })
              .map((c) => DropdownMenuItem(
                value: c['codigo'] as String,
                child: Text(c['nombre'].toString()),
              ))
              .toList(),
          onChanged: (val) => setState(() => _codigoCategoria = val),
          validator: (val) => val == null ? 'Requerido' : null,
        ),
      ],
    );
  }

  Widget _buildSeccionMontos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Modalidad y Montos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'MONTO_TOTAL_CUOTAS',
              label: Text('Cuotas'),
              icon: Icon(Icons.payments),
            ),
            ButtonSegment(
              value: 'RECURRENTE',
              label: Text('Recurrente'),
              icon: Icon(Icons.repeat),
            ),
          ],
          selected: {_modalidad},
          onSelectionChanged: (val) {
            setState(() {
              _modalidad = val.first;
              _mostrarPreview = false;
            });
          },
        ),
        const SizedBox(height: 16),
        
        if (_modalidad == 'MONTO_TOTAL_CUOTAS') ...[
          TextFormField(
            controller: _montoTotalController,
            decoration: const InputDecoration(
              labelText: 'Monto Total *',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
              hintText: '100000',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            validator: (val) {
              if (val?.trim().isEmpty ?? true) return 'Requerido';
              final monto = double.tryParse(val!);
              if (monto == null || monto <= 0) return 'Debe ser mayor a 0';
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _cuotasController,
            decoration: const InputDecoration(
              labelText: 'Cantidad de Cuotas *',
              border: OutlineInputBorder(),
              hintText: '12',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (val) {
              if (val?.trim().isEmpty ?? true) return 'Requerido';
              final cuotas = int.tryParse(val!);
              if (cuotas == null || cuotas <= 0) return 'Debe ser mayor a 0';
              return null;
            },
          ),
        ],
        
        if (_modalidad == 'RECURRENTE') ...[
          TextFormField(
            controller: _montoPeriodicoController,
            decoration: const InputDecoration(
              labelText: 'Monto por Período *',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
              hintText: '50000',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            validator: (val) {
              if (val?.trim().isEmpty ?? true) return 'Requerido';
              final monto = double.tryParse(val!);
              if (monto == null || monto <= 0) return 'Debe ser mayor a 0';
              return null;
            },
          ),
        ],
        
        const SizedBox(height: 16),
        
        DropdownButtonFormField<String>(
          value: _frecuencia,
          decoration: const InputDecoration(
            labelText: 'Frecuencia *',
            border: OutlineInputBorder(),
          ),
          items: _frecuencias.map((f) => DropdownMenuItem(
            value: f['codigo'] as String,
            child: Text(f['descripcion'].toString()),
          )).toList(),
          onChanged: (val) {
            setState(() {
              _frecuencia = val!;
              _mostrarPreview = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSeccionFechas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fechas', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        ListTile(
          title: const Text('Fecha de Inicio *'),
          subtitle: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
          leading: const Icon(Icons.calendar_today),
          onTap: () async {
            final fecha = await showDatePicker(
              context: context,
              initialDate: _fechaInicio,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (fecha != null) {
              setState(() {
                _fechaInicio = fecha;
                _mostrarPreview = false;
              });
            }
          },
        ),
        
        ListTile(
          title: const Text('Fecha de Fin (opcional)'),
          subtitle: Text(_fechaFin != null 
              ? DateFormat('dd/MM/yyyy').format(_fechaFin!) 
              : 'Sin fecha de fin'),
          leading: const Icon(Icons.event),
          trailing: _fechaFin != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _fechaFin = null;
                      _mostrarPreview = false;
                    });
                  },
                )
              : null,
          onTap: () async {
            final fecha = await showDatePicker(
              context: context,
              initialDate: _fechaFin ?? _fechaInicio.add(const Duration(days: 365)),
              firstDate: _fechaInicio,
              lastDate: DateTime(2030),
            );
            if (fecha != null) {
              setState(() {
                _fechaFin = fecha;
                _mostrarPreview = false;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildSeccionOpcional() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Información Adicional', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _observacionesController,
          decoration: const InputDecoration(
            labelText: 'Observaciones (opcional)',
            border: OutlineInputBorder(),
            hintText: 'Detalles adicionales del acuerdo...',
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildPreview() {
    if (_compromisosPreview.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No hay compromisos para mostrar'),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview de Compromisos (${_compromisosPreview.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Se generarán ${_compromisosPreview.length} cuotas',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
        ),
        const SizedBox(height: 16),
        
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _compromisosPreview.take(5).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final comp = _compromisosPreview[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text('${comp['numero_cuota']}'),
                ),
                title: Text(comp['nombre'].toString()),
                subtitle: Text(comp['fecha_programada'].toString()),
                trailing: Text(
                  Format.money((comp['monto'] as num).toDouble()),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
        
        if (_compromisosPreview.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '... y ${_compromisosPreview.length - 5} más',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildBotones() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _mostrarPreview ? null : _generarPreview,
            icon: const Icon(Icons.preview),
            label: const Text('Ver Preview'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isSubmitting ? null : _guardarAcuerdo,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_isSubmitting ? 'Guardando...' : 'Crear Acuerdo'),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildResumenAcuerdo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _nombreController.text.trim(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Tipo', _tipo == 'INGRESO' ? 'Ingreso' : 'Egreso'),
          _buildInfoRow('Modalidad', _modalidad == 'MONTO_TOTAL_CUOTAS' ? 'Cuotas' : 'Recurrente'),
          if (_modalidad == 'MONTO_TOTAL_CUOTAS') ...[
            _buildInfoRow('Monto Total', '\$${_montoTotalController.text}'),
            _buildInfoRow('Cuotas', _cuotasController.text),
          ] else
            _buildInfoRow('Monto Periódico', '\$${_montoPeriodicoController.text}'),
          _buildInfoRow('Frecuencia', _frecuencias.firstWhere(
            (f) => f['codigo'] == _frecuencia,
            orElse: () => {'descripcion': _frecuencia},
          )['descripcion'] as String),
          _buildInfoRow('Fecha Inicio', DateFormat('dd/MM/yyyy').format(_fechaInicio)),
          if (_fechaFin != null)
            _buildInfoRow('Fecha Fin', DateFormat('dd/MM/yyyy').format(_fechaFin!)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
