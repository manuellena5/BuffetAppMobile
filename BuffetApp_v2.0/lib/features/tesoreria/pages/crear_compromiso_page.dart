import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/services/error_handler.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../../features/shared/state/app_settings.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import '../../shared/widgets/responsive_container.dart';

/// Página para crear un nuevo compromiso financiero con modalidades.
/// FASE 13.5: Implementación con selector de modalidad y vista previa de cuotas.
class CrearCompromisoPage extends StatefulWidget {
  const CrearCompromisoPage({super.key});

  @override
  State<CrearCompromisoPage> createState() => _CrearCompromisoPageState();
}

class _CrearCompromisoPageState extends State<CrearCompromisoPage> {
  final _formKey = GlobalKey<FormState>();
  final _compromisosService = CompromisosService.instance;
  final _plantelService = PlantelService.instance;
  
  // Controllers
  final _nombreController = TextEditingController();
  final _montoController = TextEditingController();
  final _cuotasController = TextEditingController();
  final _frecuenciaDiasController = TextEditingController();
  final _observacionesController = TextEditingController();
  
  // Form values
  String _tipo = 'INGRESO';
  String? _codigoCategoria;
  String _modalidad = 'PAGO_UNICO'; // PAGO_UNICO | MONTO_TOTAL_CUOTAS | RECURRENTE
  String _frecuencia = 'MENSUAL';
  DateTime _fechaInicio = DateTime.now();
  DateTime? _fechaFin;
  int _unidadGestionId = 1;
  
  // Vista previa de cuotas
  List<Map<String, dynamic>> _cuotasGeneradas = [];
  bool _distribucionManual = false;
  final List<TextEditingController> _montoCuotaControllers = [];
  final List<TextEditingController> _fechaCuotaControllers = [];
  
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _frecuencias = [];
  List<Map<String, dynamic>> _unidades = [];
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _entidadesPlantel = [];
  int? _entidadPlantelId;

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
    _observacionesController.dispose();
    for (var controller in _montoCuotaControllers) {
      controller.dispose();
    }
    for (var controller in _fechaCuotaControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    
    final db = await AppDatabase.instance();
    final settings = Provider.of<AppSettings>(context, listen: false);
    
    final frecuencias = await db.query('frecuencias', orderBy: 'descripcion');
    final unidades = await db.query('unidades_gestion', where: 'activo = 1', orderBy: 'nombre');
    
    // Cargar categorías
    await _cargarCategorias();
    
    // Cargar entidades del plantel (solo activas)
    final entidades = await _plantelService.listarEntidades(soloActivos: true);
    
    // Heredar unidad de gestión del contexto de tesorería
    final unidadActivaId = settings.unidadGestionActivaId;
    
    if (mounted) {
      setState(() {
        _frecuencias = frecuencias;
        _unidades = unidades;
        _entidadesPlantel = entidades;
        if (unidadActivaId != null) {
          _unidadGestionId = unidadActivaId;
        } else if (_unidades.isNotEmpty) {
          _unidadGestionId = _unidades.first['id'] as int;
        }
      });
    }
  }

  Future<void> _cargarCategorias() async {
    try {
      final cats = await CategoriaMovimientoService.obtenerCategoriasPorTipo(tipo: _tipo);
      setState(() {
        _categorias = cats;
        // Verificar si la categoría actual sigue siendo válida
        if (_codigoCategoria != null) {
          final esValida = _categorias.any((cat) => cat['codigo'] == _codigoCategoria);
          if (!esValida) {
            _codigoCategoria = null; // Limpiar si no es válida
          }
        }
      });
    } catch (e) {
      // Error silencioso, categorías opcionales
    }
  }

  /// Genera vista previa de cuotas según modalidad y parámetros actuales
  Future<void> _generarVistaPrevia() async {
    try {
      // Limpiar controladores previos
      for (var controller in _montoCuotaControllers) {
        controller.dispose();
      }
      _montoCuotaControllers.clear();
      
      for (var controller in _fechaCuotaControllers) {
        controller.dispose();
      }
      _fechaCuotaControllers.clear();

      // Validar que haya monto
      if (_montoController.text.isEmpty) {
        if (mounted) {
          setState(() => _cuotasGeneradas = []);
        }
        return;
      }

      final monto = double.tryParse(_montoController.text);
      if (monto == null || monto <= 0) {
        if (mounted) {
          setState(() => _cuotasGeneradas = []);
        }
        return;
      }

      // Para MONTO_TOTAL_CUOTAS, validar cantidad de cuotas
      if (_modalidad == 'MONTO_TOTAL_CUOTAS') {
        if (_cuotasController.text.isEmpty) {
          if (mounted) {
            setState(() => _cuotasGeneradas = []);
          }
          return;
        }
        final cuotas = int.tryParse(_cuotasController.text);
        if (cuotas == null || cuotas <= 0) {
          if (mounted) {
            setState(() => _cuotasGeneradas = []);
          }
          return;
        }
      }

      // Crear compromiso temporal para generar cuotas
      final tempId = await _compromisosService.crearCompromiso(
        unidadGestionId: _unidadGestionId,
        nombre: 'TEMP',
        tipo: _tipo,
        modalidad: _modalidad,
        monto: monto,
        frecuencia: _frecuencia,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        frecuenciaDias: _frecuencia == 'PERSONALIZADA' ? int.tryParse(_frecuenciaDiasController.text) : null,
        cuotas: _modalidad == 'MONTO_TOTAL_CUOTAS' ? int.tryParse(_cuotasController.text) : null,
        fechaFin: _fechaFin != null ? DateFormat('yyyy-MM-dd').format(_fechaFin!) : null,
        categoria: '',
      );

      final cuotas = await _compromisosService.generarCuotas(tempId);

      // Eliminar compromiso temporal
      final db = await AppDatabase.instance();
      await db.delete('compromisos', where: 'id = ?', whereArgs: [tempId]);

      // Crear controladores para edición manual (solo en MONTO_TOTAL_CUOTAS)
      if (_modalidad == 'MONTO_TOTAL_CUOTAS' && _distribucionManual) {
        for (var cuota in cuotas) {
          // Controlador de monto
          final montoController = TextEditingController(
            text: (cuota['monto_esperado'] as double).toStringAsFixed(2),
          );
          _montoCuotaControllers.add(montoController);
          
          // Controlador de fecha
          final fechaController = TextEditingController(
            text: DateFormat('dd/MM/yyyy').format(DateTime.parse(cuota['fecha_programada'])),
          );
          _fechaCuotaControllers.add(fechaController);
        }
      }

      if (mounted) {
        setState(() => _cuotasGeneradas = cuotas);
      }
    } catch (e) {
      // Capturar errores al generar vista previa (ej. al cambiar de automático a manual)
      if (mounted) {
        setState(() => _cuotasGeneradas = []);
      }
    }
  }

  /// Valida que la suma de montos manuales coincida con el total
  String? _validarSumaMontosManuales() {
    if (!_distribucionManual || _modalidad != 'MONTO_TOTAL_CUOTAS') {
      return null;
    }

    final montoTotal = double.tryParse(_montoController.text);
    if (montoTotal == null) return null;

    final montos = _montoCuotaControllers
        .map((c) => double.tryParse(c.text) ?? 0.0)
        .toList();

    final suma = montos.fold(0.0, (a, b) => a + b);

    if ((suma - montoTotal).abs() > 0.01) {
      return 'La suma (\$${suma.toStringAsFixed(2)}) no coincide con el total (\$${montoTotal.toStringAsFixed(2)})';
    }

    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // Validar incompatibilidad modalidad/frecuencia
    if (_modalidad == 'MONTO_TOTAL_CUOTAS' && _frecuencia == 'UNICA_VEZ') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se puede dividir en cuotas con frecuencia "Única vez". Cambiá la frecuencia o usá "Pago único".'),
          backgroundColor: Colors.red,
        ),
      );
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
      final cuotas = _modalidad == 'MONTO_TOTAL_CUOTAS' && _cuotasController.text.isNotEmpty 
          ? int.parse(_cuotasController.text) 
          : null;
      final frecuenciaDias = null; // No se usa frecuencia_dias por ahora
      
      final compromisoId = await _compromisosService.crearCompromiso(
        unidadGestionId: _unidadGestionId,
        nombre: _nombreController.text.trim(),
        tipo: _tipo,
        modalidad: _modalidad,
        monto: monto,
        frecuencia: _frecuencia,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        frecuenciaDias: frecuenciaDias,
        cuotas: cuotas,
        fechaFin: _fechaFin != null ? DateFormat('yyyy-MM-dd').format(_fechaFin!) : null,
        categoria: _codigoCategoria ?? '',
        observaciones: _observacionesController.text.trim().isNotEmpty 
            ? _observacionesController.text.trim() 
            : null,
        entidadPlantelId: _entidadPlantelId,
      );

      // Generar y guardar cuotas
      List<double>? montosPersonalizados;
      List<String>? fechasPersonalizadas;
      
      if (_distribucionManual && _modalidad == 'MONTO_TOTAL_CUOTAS') {
        montosPersonalizados = _montoCuotaControllers
            .map((c) => double.parse(c.text))
            .toList();
            
        // Parsear fechas manuales si existen
        if (_fechaCuotaControllers.isNotEmpty) {
          fechasPersonalizadas = _fechaCuotaControllers
              .map((c) {
                final parts = c.text.split('/');
                if (parts.length == 3) {
                  return '${parts[2]}-${parts[1]}-${parts[0]}'; // Convertir DD/MM/YYYY a YYYY-MM-DD
                }
                return null;
              })
              .where((f) => f != null)
              .cast<String>()
              .toList();
              
          // Si no se parsearon todas, no enviar fechas personalizadas
          if (fechasPersonalizadas.length != _fechaCuotaControllers.length) {
            fechasPersonalizadas = null;
          }
        }
      }

      final cuotasGeneradas = await _compromisosService.generarCuotas(
        compromisoId,
        montosPersonalizados: montosPersonalizados,
        fechasPersonalizadas: fechasPersonalizadas,
      );

      await _compromisosService.guardarCuotas(compromisoId, cuotasGeneradas);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Compromiso creado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        scope: 'tesoreria.crear_compromiso',
        error: e,
        stackTrace: st,
        context: mounted ? context : null,
        userMessage: 'No se pudo crear el compromiso. Verificá los datos e intentá nuevamente.',
        payload: {
          'modalidad': _modalidad,
          'tipo': _tipo,
          'unidad_gestion_id': _unidadGestionId,
        },
        showDialog: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Compromiso'),
      ),
      body: ResponsiveContainer(
        maxWidth: 800,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== CAMPOS SIEMPRE VISIBLES =====
              
              // Nombre
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del compromiso *',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty 
                    ? 'Ingresá un nombre' 
                    : null,
              ),
              const SizedBox(height: 16),
              
              // Tipo
              const Text('Tipo *', style: TextStyle(fontWeight: FontWeight.w500)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Ingreso'),
                      value: 'INGRESO',
                      groupValue: _tipo,
                      onChanged: (val) {
                        setState(() => _tipo = val!);
                        _cargarCategorias();
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Egreso'),
                      value: 'EGRESO',
                      groupValue: _tipo,
                      onChanged: (val) {
                        setState(() => _tipo = val!);
                        _cargarCategorias();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Unidad de gestión
              if (_unidades.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: _unidadGestionId,
                  decoration: const InputDecoration(
                    labelText: 'Unidad de Gestión *',
                    border: OutlineInputBorder(),
                  ),
                  items: _unidades.map((u) {
                    return DropdownMenuItem<int>(
                      value: u['id'] as int,
                      child: Text(u['nombre'] as String),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _unidadGestionId = val!),
                ),
              const SizedBox(height: 16),
              
              // Categoría
              DropdownButtonFormField<String>(
                value: _codigoCategoria,
                decoration: const InputDecoration(
                  labelText: 'Categoría (opcional)',
                  border: OutlineInputBorder(),
                  hintText: 'Seleccionar categoría',
                ),
                items: _categorias.map((cat) {
                  final codigo = cat['codigo'] as String;
                  final nombre = cat['nombre'] as String;
                  return DropdownMenuItem<String>(
                    value: codigo,
                    child: Text('$nombre ($codigo)'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _codigoCategoria = v),
              ),
              const SizedBox(height: 16),
              
              // Jugador/Staff del plantel
              if (_entidadesPlantel.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: _entidadPlantelId,
                  decoration: const InputDecoration(
                    labelText: 'Jugador / Staff (opcional)',
                    border: OutlineInputBorder(),
                    hintText: 'Asociar a un jugador o miembro del cuerpo técnico',
                    helperText: 'Útil para sueldos, viandas, combustibles del plantel',
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('-- Sin asociar --'),
                    ),
                    ..._entidadesPlantel.map((entidad) {
                      final id = entidad['id'] as int;
                      final nombre = entidad['nombre'] as String;
                      final rol = entidad['rol'] as String;
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text('$nombre ($rol)'),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _entidadPlantelId = v),
                ),
              const SizedBox(height: 16),
              
              // Observaciones
              TextFormField(
                controller: _observacionesController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              
              // ===== MODALIDAD DEL COMPROMISO (CAMPO CLAVE) =====
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔑 Modalidad del compromiso *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      title: const Text('Pago único'),
                      subtitle: const Text('Un solo pago/cobro'),
                      value: 'PAGO_UNICO',
                      groupValue: _modalidad,
                      onChanged: (val) {
                        setState(() {
                          _modalidad = val!;
                          _distribucionManual = false;
                        });
                        _generarVistaPrevia();
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Monto total en cuotas'),
                      subtitle: const Text('Dividir un monto total en N pagos'),
                      value: 'MONTO_TOTAL_CUOTAS',
                      groupValue: _modalidad,
                      onChanged: (val) {
                        setState(() {
                          _modalidad = val!;
                          _distribucionManual = false;
                        });
                        _generarVistaPrevia();
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Recurrente (monto fijo por período)'),
                      subtitle: const Text('Ej: sueldo mensual, alquiler'),
                      value: 'RECURRENTE',
                      groupValue: _modalidad,
                      onChanged: (val) {
                        setState(() {
                          _modalidad = val!;
                          _distribucionManual = false;
                        });
                        _generarVistaPrevia();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // ===== CAMPOS DINÁMICOS SEGÚN MODALIDAD =====
              
              if (_modalidad == 'PAGO_UNICO') ...[
                // Monto
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto *',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  onChanged: (_) => _generarVistaPrevia(),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Ingresá un monto';
                    final monto = double.tryParse(val);
                    if (monto == null || monto <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Fecha de pago/cobro
                ListTile(
                  title: const Text('Fecha de pago/cobro *'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: _fechaInicio,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (fecha != null) {
                      setState(() => _fechaInicio = fecha);
                      _generarVistaPrevia();
                    }
                  },
                ),
              ],
              
              if (_modalidad == 'MONTO_TOTAL_CUOTAS') ...[
                // Monto total
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto total del compromiso *',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  onChanged: (_) => _generarVistaPrevia(),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Ingresá un monto';
                    final monto = double.tryParse(val);
                    if (monto == null || monto <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Cantidad de cuotas
                TextFormField(
                  controller: _cuotasController,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad de cuotas *',
                    border: OutlineInputBorder(),
                    hintText: 'Ej: 12',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => _generarVistaPrevia(),
                  validator: (val) {
                    if (_modalidad == 'MONTO_TOTAL_CUOTAS') {
                      if (val == null || val.isEmpty) return 'Ingresá la cantidad de cuotas';
                      final cuotas = int.tryParse(val);
                      if (cuotas == null || cuotas <= 0) return 'Cantidad inválida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Frecuencia
                if (_frecuencias.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _frecuencia,
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia *',
                      border: OutlineInputBorder(),
                      helperText: 'No compatible con "Única vez" en cuotas',
                    ),
                    items: _frecuencias.map((f) {
                      final codigo = f['codigo'] as String;
                      final esUnicaVez = codigo == 'UNICA_VEZ';
                      return DropdownMenuItem<String>(
                        value: codigo,
                        enabled: !esUnicaVez, // Deshabilitar UNICA_VEZ en cuotas
                        child: Text(
                          f['descripcion'] as String,
                          style: TextStyle(
                            color: esUnicaVez ? Colors.grey : null,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() => _frecuencia = val!);
                      _generarVistaPrevia();
                    },
                  ),
                const SizedBox(height: 16),
                
                // Fecha de inicio
                ListTile(
                  title: const Text('Fecha de inicio *'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: _fechaInicio,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (fecha != null) {
                      setState(() => _fechaInicio = fecha);
                      _generarVistaPrevia();
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                // Distribución de cuotas
                const Text('Distribución de cuotas', style: TextStyle(fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('Automática'),
                        subtitle: const Text('Monto total / cuotas'),
                        value: false,
                        groupValue: _distribucionManual,
                        onChanged: (val) {
                          setState(() => _distribucionManual = val!);
                          _generarVistaPrevia();
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text('Manual'),
                        value: true,
                        groupValue: _distribucionManual,
                        onChanged: (val) {
                          setState(() => _distribucionManual = val!);
                          _generarVistaPrevia();
                        },
                      ),
                    ),
                  ],
                ),
              ],
              
              if (_modalidad == 'RECURRENTE') ...[
                // Monto por período
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto por período *',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                    helperText: 'Ej: sueldo mensual de \$300.000',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  onChanged: (_) => _generarVistaPrevia(),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Ingresá un monto';
                    final monto = double.tryParse(val);
                    if (monto == null || monto <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Frecuencia
                if (_frecuencias.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _frecuencia,
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia *',
                      border: OutlineInputBorder(),
                    ),
                    items: _frecuencias.map((f) {
                      return DropdownMenuItem<String>(
                        value: f['codigo'] as String,
                        child: Text(f['descripcion'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() => _frecuencia = val!);
                      _generarVistaPrevia();
                    },
                  ),
                const SizedBox(height: 16),
                
                // Fecha de inicio
                ListTile(
                  title: const Text('Fecha de inicio *'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: _fechaInicio,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (fecha != null) {
                      setState(() => _fechaInicio = fecha);
                      _generarVistaPrevia();
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                // Fecha de fin (opcional)
                ListTile(
                  title: const Text('Fecha de fin (opcional)'),
                  subtitle: Text(_fechaFin != null 
                      ? DateFormat('dd/MM/yyyy').format(_fechaFin!) 
                      : 'Sin fecha de fin (se generan cuotas hasta fin de año)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_fechaFin != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () async {
                            setState(() {
                              _fechaFin = null;
                            });
                            await _generarVistaPrevia();
                          },
                        ),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
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
                      });
                      await _generarVistaPrevia();
                    }
                  },
                ),
              ],
              
              const SizedBox(height: 24),
              
              // ===== VISTA PREVIA DE CUOTAS =====
              if (_cuotasGeneradas.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📋 Vista previa de cuotas',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      if (!_distribucionManual || _modalidad != 'MONTO_TOTAL_CUOTAS')
                        ..._cuotasGeneradas.map((cuota) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Cuota ${cuota['numero_cuota']} – ${DateFormat('MMM yyyy', 'es').format(DateTime.parse(cuota['fecha_programada']))}'),
                                Text(
                                  '\$${(cuota['monto_esperado'] as double).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          );
                        }),
                      if (_distribucionManual && _modalidad == 'MONTO_TOTAL_CUOTAS')
                        ...List.generate(_cuotasGeneradas.length, (index) {
                          final cuota = _cuotasGeneradas[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cuota ${cuota['numero_cuota']}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _fechaCuotaControllers[index],
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Fecha',
                                          isDense: true,
                                          hintText: 'DD/MM/YYYY',
                                        ),
                                        keyboardType: TextInputType.datetime,
                                        onTap: () async {
                                          final fechaActual = _fechaCuotaControllers[index].text;
                                          DateTime? fechaInicial;
                                          try {
                                            final parts = fechaActual.split('/');
                                            if (parts.length == 3) {
                                              fechaInicial = DateTime(
                                                int.parse(parts[2]),
                                                int.parse(parts[1]),
                                                int.parse(parts[0]),
                                              );
                                            }
                                          } catch (_) {}
                                          
                                          final fecha = await showDatePicker(
                                            context: context,
                                            initialDate: fechaInicial ?? DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime(2030),
                                          );
                                          
                                          if (fecha != null) {
                                            _fechaCuotaControllers[index].text = DateFormat('dd/MM/yyyy').format(fecha);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        controller: _montoCuotaControllers[index],
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          prefixText: '\$ ',
                                          isDense: true,
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      if (_distribucionManual && _modalidad == 'MONTO_TOTAL_CUOTAS')
                        Builder(
                          builder: (context) {
                            final montoTotal = double.tryParse(_montoController.text) ?? 0.0;
                            final suma = _montoCuotaControllers
                                .map((c) => double.tryParse(c.text) ?? 0.0)
                                .fold(0.0, (a, b) => a + b);
                            final esValido = (suma - montoTotal).abs() <= 0.01;
                            
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total asignado:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(
                                  '\$${suma.toStringAsFixed(2)} ${esValido ? '✔' : '✘'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: esValido ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              
              // Botón guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator()
                      : const Text('Guardar Compromiso', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

