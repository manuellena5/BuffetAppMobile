import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../features/shared/services/movimiento_service.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/state/app_settings.dart';
import '../../../data/dao/db.dart';
import 'dart:io';

/// Página para confirmar un movimiento esperado como real.
/// 
/// Convierte un movimiento proyectado en un registro real en la base de datos.
class ConfirmarMovimientoPage extends StatefulWidget {
  final int compromisoId;
  final DateTime fechaVencimiento;
  final double montoSugerido;
  final String tipo;
  final String categoria;
  final int? numeroCuota; // Número de cuota a confirmar
  
  const ConfirmarMovimientoPage({
    super.key,
    required this.compromisoId,
    required this.fechaVencimiento,
    required this.montoSugerido,
    required this.tipo,
    required this.categoria,
    this.numeroCuota,
  });

  @override
  State<ConfirmarMovimientoPage> createState() => _ConfirmarMovimientoPageState();
}

class _ConfirmarMovimientoPageState extends State<ConfirmarMovimientoPage> {
  final _formKey = GlobalKey<FormState>();
  final _svc = EventoMovimientoService();
  final _compromisosService = CompromisosService.instance;
  
  // Controllers
  final _montoController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  // Form values
  DateTime _fechaReal = DateTime.now();
  int? _medioPagoId;
  
  // Adjunto
  File? _archivoLocal;
  String? _archivoNombre;
  
  // Estado
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _mediosPago = [];
  Map<String, dynamic>? _compromiso;
  
  @override
  void initState() {
    super.initState();
    _fechaReal = widget.fechaVencimiento;
    _montoController.text = widget.montoSugerido.toString();
    _cargarDatos();
  }

  @override
  void dispose() {
    _montoController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    try {
      final db = await AppDatabase.instance();
      
      // Cargar medios de pago
      final medios = await db.query('metodos_pago', orderBy: 'descripcion');
      
      // Cargar compromiso
      final compromiso = await _compromisosService.obtenerCompromiso(widget.compromisoId);
      
      setState(() {
        _mediosPago = medios;
        _compromiso = compromiso;
        if (_mediosPago.isNotEmpty) {
          _medioPagoId = _mediosPago.first['id'] as int;
        }
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'confirmar_movimiento.cargar',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _seleccionarArchivo(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        final size = await file.length();
        
        // Validar tamaño (25MB)
        if (size > 25 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('El archivo supera el límite de 25MB'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        setState(() {
          _archivoLocal = file;
          _archivoNombre = pickedFile.name;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'confirmar_movimiento.seleccionar_archivo',
        error: e,
        stackTrace: st,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar archivo: $e')),
        );
      }
    }
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_medioPagoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un medio de pago')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final settings = context.read<AppSettings>();
      final unidadGestionId = settings.unidadGestionActivaId;
      
      if (unidadGestionId == null) {
        throw StateError('No hay unidad de gestión activa');
      }

      final monto = double.parse(_montoController.text);

      // Crear movimiento
      final movId = await _svc.crear(
        disciplinaId: unidadGestionId, // Temporal, migrar a unidadGestionId
        tipo: widget.tipo,
        categoria: widget.categoria,
        monto: monto,
        medioPagoId: _medioPagoId!,
        observacion: _observacionesController.text.trim().isNotEmpty
            ? _observacionesController.text.trim()
            : null,
        compromisoId: widget.compromisoId,
        estado: 'CONFIRMADO',
        archivoLocalPath: _archivoLocal?.path,
        archivoNombre: _archivoNombre,
      );

      // Actualizar estado de la cuota en compromiso_cuotas
      if (widget.numeroCuota != null) {
        // Buscar la cuota por número
        final cuotas = await _compromisosService.obtenerCuotas(widget.compromisoId);
        final cuota = cuotas.firstWhere(
          (c) => c['numero_cuota'] == widget.numeroCuota,
          orElse: () => <String, dynamic>{},
        );
        
        if (cuota.isNotEmpty && cuota['id'] != null) {
          await _compromisosService.actualizarEstadoCuota(
            cuota['id'] as int,
            'CONFIRMADO',
            montoReal: monto,
          );
        }
      } else {
        // Buscar la cuota por fecha
        final db = await AppDatabase.instance();
        final cuotas = await db.query(
          'compromiso_cuotas',
          where: 'compromiso_id = ? AND fecha_programada = ? AND estado = ?',
          whereArgs: [
            widget.compromisoId,
            DateFormat('yyyy-MM-dd').format(widget.fechaVencimiento),
            'ESPERADO',
          ],
          limit: 1,
        );
        
        if (cuotas.isNotEmpty) {
          final cuotaId = cuotas.first['id'] as int;
          await _compromisosService.actualizarEstadoCuota(
            cuotaId,
            'CONFIRMADO',
            montoReal: monto,
          );
        }
      }

      // Incrementar cuotas confirmadas del compromiso
      await _compromisosService.incrementarCuotasConfirmadas(widget.compromisoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Movimiento confirmado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'confirmar_movimiento.confirmar',
        error: e,
        stackTrace: st,
      );

      setState(() => _isSubmitting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al confirmar: $e'),
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
        title: const Text('Confirmar Movimiento'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (!_isSubmitting)
            TextButton(
              onPressed: _confirmar,
              child: const Text(
                'CONFIRMAR',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info del compromiso
              if (_compromiso != null)
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Compromiso',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(_compromiso!['nombre'] as String? ?? ''),
                        Text('Tipo: ${widget.tipo}'),
                        Text('Categoría: ${widget.categoria}'),
                        Text(
                          'Vencimiento esperado: ${DateFormat('dd/MM/yyyy').format(widget.fechaVencimiento)}',
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              
              // Fecha real
              ListTile(
                title: const Text('Fecha real del movimiento *'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(_fechaReal)),
                leading: const Icon(Icons.calendar_today),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: const BorderSide(color: Colors.grey),
                ),
                onTap: _isSubmitting ? null : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _fechaReal,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _fechaReal = picked);
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // Monto real
              TextFormField(
                controller: _montoController,
                decoration: const InputDecoration(
                  labelText: 'Monto real *',
                  hintText: 'Ingresá el monto efectivo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Requerido';
                  }
                  final monto = double.tryParse(v);
                  if (monto == null || monto <= 0) {
                    return 'Debe ser mayor a cero';
                  }
                  return null;
                },
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),
              
              // Medio de pago
              DropdownButtonFormField<int>(
                value: _medioPagoId,
                decoration: const InputDecoration(
                  labelText: 'Medio de pago *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payment),
                ),
                items: _mediosPago.map((m) {
                  return DropdownMenuItem(
                    value: m['id'] as int,
                    child: Text(m['descripcion'] as String),
                  );
                }).toList(),
                onChanged: _isSubmitting ? null : (v) {
                  setState(() => _medioPagoId = v);
                },
                validator: (v) {
                  if (v == null) {
                    return 'Seleccioná un medio de pago';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Observaciones
              TextFormField(
                controller: _observacionesController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  hintText: 'Notas adicionales...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 3,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),
              
              // Adjuntar comprobante
              const Text(
                'Adjuntar comprobante (opcional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _seleccionarArchivo(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Tomar foto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _seleccionarArchivo(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galería'),
                    ),
                  ),
                ],
              ),
              if (_archivoLocal != null) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                    title: Text(_archivoNombre ?? 'Archivo adjunto'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _archivoLocal = null;
                                _archivoNombre = null;
                              });
                            },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              
              // Botón confirmar
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _confirmar,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(_isSubmitting ? 'Confirmando...' : 'Confirmar Movimiento'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
