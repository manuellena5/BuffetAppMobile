import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../features/shared/services/acuerdos_service.dart';
import '../../../data/dao/db.dart';

/// FASE 18.8: Página para editar un acuerdo existente
/// 
/// Restricciones:
/// - Solo permite editar acuerdos sin compromisos confirmados
/// - Campos editables: nombre, fecha_fin, observaciones, adjuntos
/// - NO permite cambiar montos, modalidad, frecuencia (requeriría recalcular compromisos)
class EditarAcuerdoPage extends StatefulWidget {
  final int acuerdoId;

  const EditarAcuerdoPage({super.key, required this.acuerdoId});

  @override
  State<EditarAcuerdoPage> createState() => _EditarAcuerdoPageState();
}

class _EditarAcuerdoPageState extends State<EditarAcuerdoPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nombreController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  // Form values
  DateTime? _fechaFin;
  DateTime? _fechaInicio;
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  Map<String, dynamic>? _acuerdo;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    
    try {
      final acuerdo = await AcuerdosService.obtenerAcuerdo(widget.acuerdoId);
      
      if (acuerdo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Acuerdo no encontrado')),
          );
          Navigator.pop(context);
        }
        return;
      }
      
      // Verificar que no tenga compromisos confirmados
      final stats = await AcuerdosService.obtenerEstadisticasAcuerdo(widget.acuerdoId);
      final cuotasConfirmadas = stats['cuotas_confirmadas'] as int? ?? 0;
      
      if (cuotasConfirmadas > 0) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('No se puede editar'),
              content: const Text(
                'Este acuerdo ya tiene compromisos confirmados y no puede ser editado.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
          Navigator.pop(context);
        }
        return;
      }
      
      // Cargar datos al formulario
      _nombreController.text = acuerdo['nombre']?.toString() ?? '';
      _observacionesController.text = acuerdo['observaciones']?.toString() ?? '';
      
      final fechaInicioStr = acuerdo['fecha_inicio']?.toString();
      final fechaFinStr = acuerdo['fecha_fin']?.toString();
      
      setState(() {
        _acuerdo = acuerdo;
        _fechaInicio = fechaInicioStr != null ? DateTime.parse(fechaInicioStr) : null;
        _fechaFin = fechaFinStr != null ? DateTime.parse(fechaFinStr) : null;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'editar_acuerdo_page.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
        payload: {'acuerdo_id': widget.acuerdoId},
      );
      
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar acuerdo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);
    
    try {
      await AcuerdosService.actualizarAcuerdo(
        id: widget.acuerdoId,
        nombre: _nombreController.text.trim(),
        fechaFin: _fechaFin != null ? _formatDate(_fechaFin!) : null,
        observaciones: _observacionesController.text.trim().isEmpty
            ? null
            : _observacionesController.text.trim(),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acuerdo actualizado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'editar_acuerdo_page.guardar_cambios',
        error: e.toString(),
        stackTrace: stack,
        payload: {'acuerdo_id': widget.acuerdoId},
      );
      
      setState(() => _isSubmitting = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: ${e.toString()}'),
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
        title: const Text('Editar Acuerdo'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Solo se pueden editar ciertos campos. Para cambios mayores, finalice este acuerdo y cree uno nuevo.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Text(
                    'Información Editable',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del Acuerdo *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val?.trim().isEmpty ?? true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  ListTile(
                    title: const Text('Fecha de Fin (opcional)'),
                    subtitle: Text(_fechaFin != null 
                        ? DateFormat('dd/MM/yyyy').format(_fechaFin!) 
                        : 'Sin fecha de fin'),
                    leading: const Icon(Icons.event),
                    trailing: _fechaFin != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _fechaFin = null),
                          )
                        : null,
                    onTap: () async {
                      final fecha = await showDatePicker(
                        context: context,
                        initialDate: _fechaFin ?? _fechaInicio ?? DateTime.now(),
                        firstDate: _fechaInicio ?? DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (fecha != null) {
                        setState(() => _fechaFin = fecha);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _observacionesController,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones',
                      border: OutlineInputBorder(),
                      hintText: 'Detalles adicionales...',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  Text(
                    'Información No Editable',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Los siguientes campos no se pueden modificar porque afectarían los compromisos ya generados:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_acuerdo != null) ...[
                    _buildInfoReadOnly('Tipo', _acuerdo!['tipo']?.toString() ?? '-'),
                    _buildInfoReadOnly('Modalidad', _modalidadLabel(_acuerdo!['modalidad']?.toString() ?? '-')),
                    _buildInfoReadOnly(
                      'Monto',
                      _acuerdo!['modalidad'] == 'MONTO_TOTAL_CUOTAS'
                          ? '\$ ${_acuerdo!['monto_total']}'
                          : '\$ ${_acuerdo!['monto_periodico']}',
                    ),
                    _buildInfoReadOnly('Frecuencia', _acuerdo!['frecuencia']?.toString() ?? '-'),
                    _buildInfoReadOnly(
                      'Fecha Inicio',
                      _fechaInicio != null ? DateFormat('dd/MM/yyyy').format(_fechaInicio!) : '-',
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSubmitting ? null : _guardarCambios,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Guardar Cambios'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoReadOnly(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _modalidadLabel(String modalidad) {
    switch (modalidad) {
      case 'MONTO_TOTAL_CUOTAS':
        return 'Monto Total en Cuotas';
      case 'RECURRENTE':
        return 'Recurrente';
      default:
        return modalidad;
    }
  }
}
