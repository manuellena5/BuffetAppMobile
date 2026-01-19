import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../../features/shared/services/plantel_service.dart';

/// FASE 17.8: Pantalla para editar un jugador/staff existente.
/// Similar a crear_jugador_page.dart pero con datos pre-cargados.
class EditarJugadorPage extends StatefulWidget {
  final int entidadId;

  const EditarJugadorPage({
    Key? key,
    required this.entidadId,
  }) : super(key: key);

  @override
  State<EditarJugadorPage> createState() => _EditarJugadorPageState();
}

class _EditarJugadorPageState extends State<EditarJugadorPage> {
  final _formKey = GlobalKey<FormState>();
  final _plantelSvc = PlantelService.instance;

  bool _cargando = true;
  bool _guardando = false;

  // Datos originales
  Map<String, dynamic>? _entidadOriginal;
  int _cantidadCompromisos = 0;

  // Controladores
  final _nombreCtrl = TextEditingController();
  final _contactoCtrl = TextEditingController();
  final _dniCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  String? _rolSeleccionado;
  DateTime? _fechaNacimiento;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _contactoCtrl.dispose();
    _dniCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final entidad = await _plantelSvc.obtenerEntidad(widget.entidadId);
      if (entidad == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entidad no encontrada')),
          );
          Navigator.pop(context);
        }
        return;
      }

      final compromisos = await _plantelSvc.listarCompromisosDeEntidad(widget.entidadId);

      setState(() {
        _entidadOriginal = entidad;
        _cantidadCompromisos = compromisos.length;

        // Pre-cargar campos con null-safety
        _nombreCtrl.text = entidad['nombre']?.toString() ?? '';
        _rolSeleccionado = entidad['rol']?.toString();
        _contactoCtrl.text = entidad['contacto']?.toString() ?? '';
        _dniCtrl.text = entidad['dni']?.toString() ?? '';
        _observacionesCtrl.text = entidad['observaciones']?.toString() ?? '';

        final fechaNacStr = entidad['fecha_nacimiento']?.toString();
        if (fechaNacStr != null && fechaNacStr.isNotEmpty) {
          try {
            _fechaNacimiento = DateTime.parse(fechaNacStr);
          } catch (_) {
            _fechaNacimiento = null;
          }
        }
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'editar_jugador.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
        payload: {'entidad_id': widget.entidadId},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar datos. Por favor, intente nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime.now().subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      locale: const Locale('es'),
      helpText: 'Seleccionar fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (fecha != null) {
      setState(() {
        _fechaNacimiento = fecha;
      });
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar que haya cambios
    final nombreNuevo = _nombreCtrl.text.trim();
    if (nombreNuevo.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El nombre no puede estar vacío'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _guardando = true);

    try {
      // Preparar map de cambios
      final cambios = <String, dynamic>{
        'nombre': nombreNuevo,
        'rol': _rolSeleccionado!,
        'contacto': _contactoCtrl.text.trim().isEmpty ? null : _contactoCtrl.text.trim(),
        'dni': _dniCtrl.text.trim().isEmpty ? null : _dniCtrl.text.trim(),
        'fecha_nacimiento': _fechaNacimiento?.toIso8601String().split('T')[0],
        'observaciones': _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
      };

      await _plantelSvc.actualizarEntidad(widget.entidadId, cambios);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jugador actualizado correctamente')),
        );
        Navigator.pop(context, true); // true = se modificó
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'editar_jugador.guardar',
        error: e.toString(),
        stackTrace: stack,
        payload: {'entidad_id': widget.entidadId, 'nombre': nombreNuevo},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al actualizar. Por favor, intente nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activo = _entidadOriginal != null && (_entidadOriginal!['estado_activo'] as int) == 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Jugador/Staff'),
        actions: [
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Guardar',
              onPressed: _cargando ? null : _guardar,
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Información de solo lectura
                    Card(
                      color: activo ? Colors.blue.shade50 : Colors.grey.shade200,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Información de solo lectura',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text('ID: ${widget.entidadId}', style: const TextStyle(fontSize: 12)),
                            Text('Compromisos asociados: $_cantidadCompromisos', style: const TextStyle(fontSize: 12)),
                            Text(
                              'Estado: ${activo ? 'ACTIVO' : 'DADO DE BAJA'}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: activo ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Campo: Nombre
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo *',
                        hintText: 'Ej: Juan Pérez',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'El nombre es obligatorio';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Campo: Rol
                    DropdownButtonFormField<String>(
                      value: _rolSeleccionado,
                      decoration: const InputDecoration(
                        labelText: 'Rol *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sports_soccer),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'JUGADOR', child: Text('Jugador')),
                        DropdownMenuItem(value: 'DT', child: Text('Director Técnico')),
                        DropdownMenuItem(value: 'AYUDANTE', child: Text('Ayudante de Campo')),
                        DropdownMenuItem(value: 'PF', child: Text('Preparador Físico')),
                        DropdownMenuItem(value: 'OTRO', child: Text('Otro')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _rolSeleccionado = value;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'El rol es obligatorio';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Campo: Contacto
                    TextFormField(
                      controller: _contactoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contacto (teléfono o email)',
                        hintText: '+54 9 11 1234-5678 o email@ejemplo.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    // Campo: DNI
                    TextFormField(
                      controller: _dniCtrl,
                      decoration: const InputDecoration(
                        labelText: 'DNI',
                        hintText: '12345678',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Campo: Fecha de Nacimiento
                    InkWell(
                      onTap: _seleccionarFecha,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de nacimiento',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.cake),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _fechaNacimiento == null
                              ? 'Seleccionar fecha'
                              : DateFormat('dd/MM/yyyy').format(_fechaNacimiento!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Campo: Observaciones
                    TextFormField(
                      controller: _observacionesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones',
                        hintText: 'Notas adicionales',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 24),

                    // Botón: Guardar
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(_guardando ? 'Guardando...' : 'Guardar Cambios'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
