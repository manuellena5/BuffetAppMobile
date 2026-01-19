import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/state/app_settings.dart';
import '../../../data/dao/db.dart';

/// Página para editar un compromiso financiero existente.
/// FASE 13.5: Implementación con modalidades y cuotas.
class EditarCompromisoPage extends StatefulWidget {
  final int compromisoId;
  
  const EditarCompromisoPage({
    super.key,
    required this.compromisoId,
  });

  @override
  State<EditarCompromisoPage> createState() => _EditarCompromisoPageState();
}

class _EditarCompromisoPageState extends State<EditarCompromisoPage> {
  final _formKey = GlobalKey<FormState>();
  final _compromisosService = CompromisosService.instance;
  
  // Controllers
  final _nombreController = TextEditingController();
  final _montoController = TextEditingController();
  final _cuotasController = TextEditingController();
  final _frecuenciaDiasController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  // Form values
  String _tipo = 'INGRESO';
  String _modalidad = 'PAGO_UNICO'; // PAGO_UNICO | MONTO_TOTAL_CUOTAS | RECURRENTE
  String _frecuencia = 'MENSUAL';
  DateTime _fechaInicio = DateTime.now();
  DateTime? _fechaFin;
  int _unidadGestionId = 1;
  
  // Vista previa de cuotas
  List<Map<String, dynamic>> _cuotasGeneradas = [];
  List<Map<String, dynamic>> _cuotasExistentes = []; // Cuotas ya guardadas en DB
  bool _distribucionManual = false;
  final List<TextEditingController> _montoCuotaControllers = [];
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  List<Map<String, dynamic>> _frecuencias = [];
  Map<String, dynamic>? _compromisoOriginal;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    _cuotasController.dispose();
    _frecuenciaDiasController.dispose();
    _categoriaController.dispose();
    _observacionesController.dispose();
    for (var controller in _montoCuotaControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final db = await AppDatabase.instance();
      final settings = Provider.of<AppSettings>(context, listen: false);
      
      // Cargar compromiso
      final compromiso = await _compromisosService.obtenerCompromiso(widget.compromisoId);
      
      if (compromiso == null) {
        setState(() {
          _error = 'Compromiso no encontrado';
          _isLoading = false;
        });
        return;
      }
      
      // Cargar cuotas existentes
      final cuotasExistentes = await _compromisosService.obtenerCuotas(widget.compromisoId);
      
      // Cargar frecuencias
      final frecuencias = await db.query('frecuencias', orderBy: 'descripcion');
      
      // Llenar campos con datos existentes
      _nombreController.text = compromiso['nombre'] as String? ?? '';
      _montoController.text = (compromiso['monto'] as double?)?.toString() ?? '';
      _cuotasController.text = (compromiso['cuotas'] as int?)?.toString() ?? '';
      _frecuenciaDiasController.text = (compromiso['frecuencia_dias'] as int?)?.toString() ?? '';
      _categoriaController.text = compromiso['categoria'] as String? ?? '';
      _observacionesController.text = compromiso['observaciones'] as String? ?? '';
      
      _tipo = compromiso['tipo'] as String? ?? 'INGRESO';
      _modalidad = compromiso['modalidad'] as String? ?? 'PAGO_UNICO';
      _frecuencia = compromiso['frecuencia'] as String? ?? 'MENSUAL';
      
      // Heredar unidad de gestión del contexto si está disponible
      final unidadActivaId = settings.unidadGestionActivaId;
      _unidadGestionId = unidadActivaId ?? compromiso['unidad_gestion_id'] as int? ?? 1;
      
      if (compromiso['fecha_inicio'] != null) {
        _fechaInicio = DateTime.parse(compromiso['fecha_inicio'] as String);
      }
      
      if (compromiso['fecha_fin'] != null) {
        _fechaFin = DateTime.parse(compromiso['fecha_fin'] as String);
      }
      
      setState(() {
        _frecuencias = frecuencias;
        _compromisoOriginal = compromiso;
        _cuotasExistentes = cuotasExistentes;
        _isLoading = false;
      });
      
      // Generar vista previa inicial
      if (_cuotasExistentes.isNotEmpty) {
        _cargarCuotasExistentes();
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'editar_compromiso.cargar',
        error: e,
        stackTrace: st,
        payload: {'compromisoId': widget.compromisoId},
      );
      
      setState(() {
        _error = 'Error al cargar datos: $e';
        _isLoading = false;
      });
    }
  }

  /// Carga cuotas existentes en la vista previa
  void _cargarCuotasExistentes() {
    setState(() {
      _cuotasGeneradas = List.from(_cuotasExistentes);
      _montoCuotaControllers.clear();
      for (var cuota in _cuotasGeneradas) {
        final controller = TextEditingController(
          text: (cuota['monto_esperado'] as double?)?.toString() ?? '',
        );
        _montoCuotaControllers.add(controller);
      }
    });
  }

  /// Genera vista previa de cuotas según modalidad y parámetros actuales
  Future<void> _generarVistaPrevia() async {
    // Limpiar controladores previos
    for (var controller in _montoCuotaControllers) {
      controller.dispose();
    }
    _montoCuotaControllers.clear();

    // Validar que haya monto
    if (_montoController.text.isEmpty) {
      setState(() => _cuotasGeneradas = []);
      return;
    }

    final monto = double.tryParse(_montoController.text);
    if (monto == null || monto <= 0) {
      setState(() => _cuotasGeneradas = []);
      return;
    }

    // Para MONTO_TOTAL_CUOTAS, validar cantidad de cuotas
    if (_modalidad == 'MONTO_TOTAL_CUOTAS') {
      if (_cuotasController.text.isEmpty) {
        setState(() => _cuotasGeneradas = []);
        return;
      }
      final cuotas = int.tryParse(_cuotasController.text);
      if (cuotas == null || cuotas <= 0) {
        setState(() => _cuotasGeneradas = []);
        return;
      }
    }

    try {
      // Crear compromiso temporal para generar cuotas
      final tempId = await _compromisosService.crearCompromiso(
        unidadGestionId: _unidadGestionId,
        nombre: 'TEMP',
        tipo: _tipo,
        modalidad: _modalidad,
        monto: monto,
        frecuencia: _frecuencia,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        cuotas: _modalidad == 'MONTO_TOTAL_CUOTAS' ? int.parse(_cuotasController.text) : null,
        frecuenciaDias: _frecuencia == 'PERSONALIZADA' && _frecuenciaDiasController.text.isNotEmpty
            ? int.parse(_frecuenciaDiasController.text)
            : null,
        fechaFin: _fechaFin != null ? DateFormat('yyyy-MM-dd').format(_fechaFin!) : null,
        categoria: '',
      );

      // Generar cuotas
      final cuotasGeneradas = await _compromisosService.generarCuotas(tempId);
      
      // Eliminar compromiso temporal
      final db = await AppDatabase.instance();
      await db.delete('compromisos', where: 'id = ?', whereArgs: [tempId]);

      // Actualizar estado
      setState(() {
        _cuotasGeneradas = cuotasGeneradas;
        
        // Crear controladores para edición manual
        _montoCuotaControllers.clear();
        for (var cuota in _cuotasGeneradas) {
          final controller = TextEditingController(
            text: (cuota['monto_esperado'] as double?)?.toString() ?? '',
          );
          _montoCuotaControllers.add(controller);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar vista previa: $e')),
        );
      }
    }
  }

  /// Valida que la suma de montos manuales sea igual al total
  String? _validarSumaMontosManuales() {
    if (!_distribucionManual || _modalidad != 'MONTO_TOTAL_CUOTAS') {
      return null;
    }

    final total = double.tryParse(_montoController.text);
    if (total == null) return null;

    double suma = 0;
    for (var controller in _montoCuotaControllers) {
      final monto = double.tryParse(controller.text);
      if (monto == null || monto <= 0) {
        return 'Todos los montos deben ser válidos y mayores a cero';
      }
      suma += monto;
    }

    if ((suma - total).abs() > 0.01) {
      return 'La suma (\$${suma.toStringAsFixed(2)}) no coincide con el total (\$${total.toStringAsFixed(2)})';
    }

    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validar suma de montos manuales
    final errorSuma = _validarSumaMontosManuales();
    if (errorSuma != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorSuma), backgroundColor: Colors.red),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    try {
      final monto = double.parse(_montoController.text);
      final cuotas = _cuotasController.text.isNotEmpty 
          ? int.parse(_cuotasController.text) 
          : null;
      final frecuenciaDias = _frecuencia == 'PERSONALIZADA' && _frecuenciaDiasController.text.isNotEmpty
          ? int.parse(_frecuenciaDiasController.text)
          : null;
      
      // Actualizar compromiso
      await _compromisosService.actualizarCompromiso(
        widget.compromisoId,
        nombre: _nombreController.text.trim(),
        tipo: _tipo,
        modalidad: _modalidad,
        monto: monto,
        frecuencia: _frecuencia,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        frecuenciaDias: frecuenciaDias,
        cuotas: cuotas,
        fechaFin: _fechaFin != null ? DateFormat('yyyy-MM-dd').format(_fechaFin!) : null,
        categoria: _categoriaController.text.trim().isEmpty 
            ? '' 
            : _categoriaController.text.trim(),
        observaciones: _observacionesController.text.trim().isNotEmpty 
            ? _observacionesController.text.trim() 
            : null,
      );

      // Regenerar y guardar cuotas si se modificaron parámetros relevantes
      if (_cuotasGeneradas.isNotEmpty) {
        // Primero eliminar cuotas existentes
        final db = await AppDatabase.instance();
        await db.delete('compromiso_cuotas', where: 'compromiso_id = ?', whereArgs: [widget.compromisoId]);
        
        // Aplicar montos manuales si corresponde
        if (_distribucionManual && _modalidad == 'MONTO_TOTAL_CUOTAS') {
          for (int i = 0; i < _cuotasGeneradas.length; i++) {
            final montoManual = double.parse(_montoCuotaControllers[i].text);
            _cuotasGeneradas[i]['monto_esperado'] = montoManual;
          }
        }
        
        // Guardar nuevas cuotas
        await _compromisosService.guardarCuotas(widget.compromisoId, _cuotasGeneradas);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compromiso actualizado exitosamente')),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'editar_compromiso.guardar',
        error: e,
        stackTrace: st,
        payload: {'compromisoId': widget.compromisoId},
      );
      
      setState(() => _isSubmitting = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Compromiso'),
        actions: [
          if (!_isLoading && !_isSubmitting)
            TextButton(
              onPressed: _guardar,
              child: const Text(
                'GUARDAR',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _cargarDatos,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Información de solo lectura
            if (_compromisoOriginal != null)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información del compromiso',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('ID: ${widget.compromisoId}'),
                      Text('Cuotas confirmadas: ${_compromisoOriginal!['cuotas_confirmadas'] ?? 0}'),
                      Text('Estado: ${_compromisoOriginal!['activo'] == 1 ? 'Activo' : 'Pausado'}'),
                      if (_cuotasExistentes.isNotEmpty)
                        Text('Cuotas en DB: ${_cuotasExistentes.length}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            
            // Nombre
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'ej: Sueldo Entrenador',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 16),
            
            // Tipo
            DropdownButtonFormField<String>(
              value: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.swap_vert),
              ),
              items: const [
                DropdownMenuItem(value: 'INGRESO', child: Text('Ingreso')),
                DropdownMenuItem(value: 'EGRESO', child: Text('Egreso')),
              ],
              onChanged: _isSubmitting ? null : (v) {
                if (v != null) setState(() => _tipo = v);
              },
            ),
            const SizedBox(height: 16),
            
            // MODALIDAD (selector principal)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Modalidad del compromiso *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<String>(
                      title: const Text('Pago Único'),
                      subtitle: const Text('Un solo pago en fecha específica'),
                      value: 'PAGO_UNICO',
                      groupValue: _modalidad,
                      onChanged: _isSubmitting ? null : (v) {
                        setState(() {
                          _modalidad = v!;
                          _generarVistaPrevia();
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Monto Total en Cuotas'),
                      subtitle: const Text('Dividir un monto total en X cuotas'),
                      value: 'MONTO_TOTAL_CUOTAS',
                      groupValue: _modalidad,
                      onChanged: _isSubmitting ? null : (v) {
                        setState(() {
                          _modalidad = v!;
                          _generarVistaPrevia();
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Recurrente'),
                      subtitle: const Text('Monto fijo que se repite periódicamente'),
                      value: 'RECURRENTE',
                      groupValue: _modalidad,
                      onChanged: _isSubmitting ? null : (v) {
                        setState(() {
                          _modalidad = v!;
                          _generarVistaPrevia();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Monto
            TextFormField(
              controller: _montoController,
              decoration: InputDecoration(
                labelText: _modalidad == 'MONTO_TOTAL_CUOTAS' 
                    ? 'Monto total * (a dividir)'
                    : 'Monto * (por cuota)',
                hintText: 'ej: 50000',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.attach_money),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requerido';
                final monto = double.tryParse(v);
                if (monto == null || monto <= 0) return 'Debe ser mayor a cero';
                return null;
              },
              onChanged: (_) => _generarVistaPrevia(),
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 16),
            
            // Frecuencia
            DropdownButtonFormField<String>(
              value: _frecuencia,
              decoration: const InputDecoration(
                labelText: 'Frecuencia *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              items: _frecuencias.map((f) {
                return DropdownMenuItem(
                  value: f['codigo'] as String,
                  child: Text(f['descripcion'] as String),
                );
              }).toList(),
              onChanged: _isSubmitting ? null : (v) {
                if (v != null) {
                  setState(() => _frecuencia = v);
                  _generarVistaPrevia();
                }
              },
            ),
            const SizedBox(height: 16),
            
            // Frecuencia días (solo PERSONALIZADA)
            if (_frecuencia == 'PERSONALIZADA')
              TextFormField(
                controller: _frecuenciaDiasController,
                decoration: const InputDecoration(
                  labelText: 'Días de frecuencia *',
                  hintText: 'ej: 15',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.event_repeat),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_frecuencia == 'PERSONALIZADA') {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final dias = int.tryParse(v);
                    if (dias == null || dias <= 0) return 'Debe ser mayor a cero';
                  }
                  return null;
                },
                onChanged: (_) => _generarVistaPrevia(),
                enabled: !_isSubmitting,
              ),
            if (_frecuencia == 'PERSONALIZADA') const SizedBox(height: 16),
            
            // Cantidad de cuotas (solo MONTO_TOTAL_CUOTAS)
            if (_modalidad == 'MONTO_TOTAL_CUOTAS')
              TextFormField(
                controller: _cuotasController,
                decoration: const InputDecoration(
                  labelText: 'Cantidad de cuotas *',
                  hintText: 'ej: 12',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.repeat),
                  helperText: 'En cuántas cuotas dividir el monto total',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_modalidad == 'MONTO_TOTAL_CUOTAS') {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final cuotas = int.tryParse(v);
                    if (cuotas == null || cuotas <= 0) return 'Debe ser mayor a cero';
                  }
                  return null;
                },
                onChanged: (_) => _generarVistaPrevia(),
                enabled: !_isSubmitting,
              ),
            if (_modalidad == 'MONTO_TOTAL_CUOTAS') const SizedBox(height: 16),
            
            // Fecha inicio
            ListTile(
              title: const Text('Fecha de inicio *'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
              leading: const Icon(Icons.calendar_month),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: Colors.grey),
              ),
              onTap: _isSubmitting ? null : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _fechaInicio,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _fechaInicio = picked);
                  _generarVistaPrevia();
                }
              },
            ),
            const SizedBox(height: 16),
            
            // Fecha fin (solo para RECURRENTE)
            if (_modalidad == 'RECURRENTE')
              ListTile(
                title: const Text('Fecha de fin (opcional)'),
                subtitle: Text(
                  _fechaFin != null 
                      ? DateFormat('dd/MM/yyyy').format(_fechaFin!)
                      : 'Hasta fin de año ${DateTime.now().year}',
                ),
                leading: const Icon(Icons.event_busy),
                trailing: _fechaFin != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _isSubmitting ? null : () {
                          setState(() => _fechaFin = null);
                          _generarVistaPrevia();
                        },
                      )
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: const BorderSide(color: Colors.grey),
                ),
                onTap: _isSubmitting ? null : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _fechaFin ?? _fechaInicio.add(const Duration(days: 365)),
                    firstDate: _fechaInicio,
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _fechaFin = picked);
                    _generarVistaPrevia();
                  }
                },
              ),
            if (_modalidad == 'RECURRENTE') const SizedBox(height: 16),
            
            // Categoría
            TextFormField(
              controller: _categoriaController,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                hintText: 'ej: Personal, Infraestructura',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 16),
            
            // Observaciones
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                hintText: 'Notas adicionales...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 3,
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 24),
            
            // Vista previa de cuotas
            if (_cuotasGeneradas.isNotEmpty) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Vista previa de cuotas',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '${_cuotasGeneradas.length} cuotas',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Opción de distribución manual (solo MONTO_TOTAL_CUOTAS)
                      if (_modalidad == 'MONTO_TOTAL_CUOTAS')
                        SwitchListTile(
                          title: const Text('Distribución manual'),
                          subtitle: const Text('Editar monto de cada cuota individualmente'),
                          value: _distribucionManual,
                          onChanged: (v) => setState(() => _distribucionManual = v),
                        ),
                      
                      const Divider(),
                      
                      // Lista de cuotas
                      ...List.generate(_cuotasGeneradas.length, (index) {
                        final cuota = _cuotasGeneradas[index];
                        final fecha = cuota['fecha_programada'] as String;
                        final monto = cuota['monto_esperado'] as double;
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('Cuota ${cuota['numero_cuota']}:'),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(fecha))),
                              ),
                              Expanded(
                                flex: 3,
                                child: _distribucionManual && _modalidad == 'MONTO_TOTAL_CUOTAS'
                                    ? TextFormField(
                                        controller: _montoCuotaControllers[index],
                                        decoration: const InputDecoration(
                                          prefix: Text('\$'),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                        ],
                                      )
                                    : Text('\$${monto.toStringAsFixed(2)}'),
                              ),
                            ],
                          ),
                        );
                      }),
                      
                      // Validación de suma
                      if (_distribucionManual && _modalidad == 'MONTO_TOTAL_CUOTAS') ...[
                        const Divider(),
                        Builder(
                          builder: (context) {
                            final error = _validarSumaMontosManuales();
                            if (error != null) {
                              return Text(
                                error,
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                              );
                            }
                            return const Text(
                              '✓ Suma válida',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // Botón guardar
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _guardar,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSubmitting ? 'Guardando...' : 'Guardar Cambios'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
