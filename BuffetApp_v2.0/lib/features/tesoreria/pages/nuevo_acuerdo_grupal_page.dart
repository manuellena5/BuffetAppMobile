import 'package:buffet_app/features/shared/format.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import '../../shared/widgets/responsive_container.dart';
import '../services/acuerdos_grupales_service.dart';

/// Wizard de 6 pasos para crear acuerdos grupales
/// Paso 1: Selección de tipo (INGRESO/EGRESO)
/// Paso 2: Datos generales (nombre, unidad, categoría)
/// Paso 3: Cláusulas económicas (modalidad, monto, frecuencia, fechas, cuotas)
/// Paso 4: Selección de jugadores + ajustes de monto individuales
/// Paso 5: Preview detallado (tabla de acuerdos + compromisos)
/// Paso 6: Confirmación final con advertencias
class NuevoAcuerdoGrupalPage extends StatefulWidget {
  final int unidadGestionId;
  
  const NuevoAcuerdoGrupalPage({
    super.key,
    required this.unidadGestionId,
  });

  @override
  State<NuevoAcuerdoGrupalPage> createState() => _NuevoAcuerdoGrupalPageState();
}

class _NuevoAcuerdoGrupalPageState extends State<NuevoAcuerdoGrupalPage> {
  final _formKey = GlobalKey<FormState>();
  final _grupalSvc = AcuerdosGrupalesService.instance;
  
  // Estado del wizard
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Paso 1: Tipo
  String _tipo = 'EGRESO'; // EGRESO más común para sueldos

  // Paso 2: Datos generales
  final _nombreCtrl = TextEditingController();
  late int _unidadGestionId;
  String _categoria = 'PAGO JUGADORES'; // Categoría por defecto de categoria_movimiento
  final _observacionesCtrl = TextEditingController();

  // Paso 3: Cláusulas económicas
  String _modalidad = 'RECURRENTE';
  final _montoCtrl = TextEditingController();
  String _frecuencia = 'MENSUAL';
  DateTime _fechaInicio = DateTime.now();
  DateTime? _fechaFin;
  int _cuotas = 12;

  // Paso 4: Jugadores
  List<Map<String, dynamic>> _todosJugadores = [];
  List<Map<String, dynamic>> _jugadoresFiltrados = [];
  final Map<int, JugadorConMonto> _jugadoresSeleccionados = {};
  
  // Filtros de jugadores
  String _filtroRol = 'TODOS';
  String _filtroEstado = 'TODOS';
  String _filtroTipoContratacion = 'TODOS';
  final _filtroNombreCtrl = TextEditingController();

  // Paso 5: Preview
  PreviewAcuerdoGrupal? _preview;
  Map<int, List<String>> _validaciones = {};

  // Paso 6: Confirmación
  bool _generaCompromisos = true;

  @override
  void initState() {
    super.initState();
    _unidadGestionId = widget.unidadGestionId;
    _cargarJugadores();
    _filtroNombreCtrl.addListener(_aplicarFiltros);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _observacionesCtrl.dispose();
    _montoCtrl.dispose();
    _filtroNombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarJugadores() async {
    try {
      setState(() => _isLoading = true);
      
      final rawDb = await AppDatabase.instance();
      final result = await rawDb.query(
        'entidades_plantel',
        columns: ['id', 'nombre', 'rol', 'alias', 'tipo_contratacion', 'posicion', 'estado_activo'],
        where: 'estado_activo = ?',
        whereArgs: [1],
        orderBy: 'nombre ASC',
      );

      setState(() {
        _todosJugadores = result;
        _jugadoresFiltrados = result;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.cargar_jugadores',
        error: e.toString(),
        stackTrace: stack,
      );
      setState(() {
        _errorMessage = 'Error al cargar jugadores';
        _isLoading = false;
      });
    }
  }

  void _aplicarFiltros() {
    setState(() {
      _jugadoresFiltrados = _todosJugadores.where((j) {
        // Filtro por nombre
        final nombre = (j['nombre'] as String? ?? '').toLowerCase();
        final filtroNombre = _filtroNombreCtrl.text.toLowerCase();
        if (filtroNombre.isNotEmpty && !nombre.contains(filtroNombre)) {
          return false;
        }

        // Filtro por rol
        if (_filtroRol != 'TODOS') {
          if ((j['rol'] as String? ?? '') != _filtroRol) return false;
        }

        // Filtro por estado
        if (_filtroEstado == 'ACTIVO' && (j['estado_activo'] as int? ?? 0) != 1) {
          return false;
        }

        // Filtro por tipo de contratación
        if (_filtroTipoContratacion != 'TODOS') {
          if ((j['tipo_contratacion'] as String? ?? '') != _filtroTipoContratacion) {
            return false;
          }
        }

        return true;
      }).toList();
    });
  }

  void _toggleJugador(Map<String, dynamic> jugador, bool selected) {
    setState(() {
      final id = jugador['id'] as int;
      if (selected) {
        // Agregar con monto por defecto (del campo general)
        final montoBase = double.tryParse(_montoCtrl.text) ?? 0;
        _jugadoresSeleccionados[id] = JugadorConMonto(
          id: id,
          nombre: jugador['nombre'] as String? ?? '',
          numeroAsociado: null, // Columna no existe aún
          rol: jugador['rol'] as String?,
          alias: jugador['alias'] as String?,
          tipoContratacion: jugador['tipo_contratacion'] as String?,
          posicion: jugador['posicion'] as String?,
          monto: montoBase,
        );
      } else {
        _jugadoresSeleccionados.remove(id);
      }
    });
  }

  void _ajustarMontoIndividual(int jugadorId, double nuevoMonto) {
    setState(() {
      final jugador = _jugadoresSeleccionados[jugadorId];
      if (jugador != null) {
        _jugadoresSeleccionados[jugadorId] = JugadorConMonto(
          id: jugador.id,
          nombre: jugador.nombre,
          numeroAsociado: jugador.numeroAsociado,
          rol: jugador.rol,
          alias: jugador.alias,
          tipoContratacion: jugador.tipoContratacion,
          posicion: jugador.posicion,
          monto: nuevoMonto,
        );
      }
    });
  }

  Future<void> _generarPreview() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Validar jugadores
      final validacionRes = await _grupalSvc.validarJugadores(
        jugadores: _jugadoresSeleccionados.values.toList(),
        unidadGestionId: _unidadGestionId!,
        categoria: _categoria,
      );

      // Generar preview
      final preview = await _grupalSvc.generarPreview(
        nombre: _nombreCtrl.text.trim(),
        tipo: _tipo,
        modalidad: _modalidad,
        montoBase: _modalidad == 'RECURRENTE' 
          ? (double.tryParse(_montoCtrl.text) ?? 0) 
          : 0,
        montoTotal: _modalidad == 'MONTO_TOTAL_CUOTAS' 
          ? (double.tryParse(_montoCtrl.text) ?? 0) 
          : null,
        frecuencia: _frecuencia,
        cuotas: _cuotas,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        fechaFin: _fechaFin != null 
          ? DateFormat('yyyy-MM-dd').format(_fechaFin!) 
          : null,
        jugadores: _jugadoresSeleccionados.values.toList(),
        generaCompromisos: _generaCompromisos,
      );

      setState(() {
        _preview = preview;
        _validaciones = validacionRes;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.generar_preview',
        error: e.toString(),
        stackTrace: stack,
      );
      setState(() {
        _errorMessage = 'Error al generar preview: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmarCreacion() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final resultado = await _grupalSvc.crearAcuerdosGrupales(
        nombre: _nombreCtrl.text.trim(),
        unidadGestionId: _unidadGestionId!,
        tipo: _tipo,
        modalidad: _modalidad,
        montoBase: _modalidad == 'RECURRENTE' 
          ? (double.tryParse(_montoCtrl.text) ?? 0) 
          : 0,
        montoTotal: _modalidad == 'MONTO_TOTAL_CUOTAS' 
          ? (double.tryParse(_montoCtrl.text) ?? 0) 
          : null,
        frecuencia: _frecuencia,
        cuotas: _cuotas,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        fechaFin: _fechaFin != null 
          ? DateFormat('yyyy-MM-dd').format(_fechaFin!) 
          : null,
        categoria: _categoria,
        observacionesComunes: _observacionesCtrl.text.trim(),
        jugadores: _jugadoresSeleccionados.values.toList(),
        generaCompromisos: _generaCompromisos,
      );

      if (mounted) {
        Navigator.pop(context, resultado);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se crearon ${resultado.cantidadCreados} acuerdos${resultado.tieneErrores ? ' (con ${resultado.errores.length} errores)' : ''}',
            ),
            backgroundColor: resultado.todoExitoso ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.confirmar_creacion',
        error: e.toString(),
        stackTrace: stack,
      );
      setState(() {
        _errorMessage = 'Error al crear acuerdos: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Acuerdo Grupal'),
        actions: [
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text('Anterior', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 900,
        child: Form(
          key: _formKey,
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: _onStepContinue,
            onStepCancel: () => setState(() {
              if (_currentStep > 0) _currentStep--;
            }),
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    child: Text(_currentStep == 5 ? 'Crear Acuerdos' : 'Siguiente'),
                  ),
                  const SizedBox(width: 8),
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: _isLoading ? null : details.onStepCancel,
                      child: const Text('Anterior'),
                    ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Tipo'),
              content: _buildStepTipo(),
              isActive: _currentStep >= 0,
            ),
            Step(
              title: const Text('Datos Generales'),
              content: _buildStepDatosGenerales(),
              isActive: _currentStep >= 1,
            ),
            Step(
              title: const Text('Cláusulas Económicas'),
              content: _buildStepClausulas(),
              isActive: _currentStep >= 2,
            ),
            Step(
              title: const Text('Jugadores'),
              content: _buildStepJugadores(),
              isActive: _currentStep >= 3,
            ),
            Step(
              title: const Text('Preview'),
              content: _buildStepPreview(),
              isActive: _currentStep >= 4,
            ),
            Step(
              title: const Text('Confirmación'),
              content: _buildStepConfirmacion(),
              isActive: _currentStep >= 5,
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _onStepContinue() async {
    if (_isLoading) return;

    print('DEBUG: Intentando avanzar desde paso $_currentStep');

    // Validaciones por paso
    // Paso 0: Tipo - sin validación de formulario
    
    if (_currentStep == 1) {
      // Paso 1: Datos Generales - validar manualmente
      print('DEBUG: Validando Datos Generales');
      print('DEBUG: Nombre: ${_nombreCtrl.text}');
      print('DEBUG: Categoría: $_categoria');
      
      if (_nombreCtrl.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Debe ingresar un nombre para el acuerdo');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe ingresar un nombre para el acuerdo'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      if (_categoria.isEmpty) {
        setState(() => _errorMessage = 'Debe seleccionar una categoría');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe seleccionar una categoría'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      print('DEBUG: Datos Generales válidos ✓');
    }

    if (_currentStep == 2) {
      // Paso 2: Cláusulas Económicas - validar manualmente
      print('DEBUG: Validando Cláusulas Económicas');
      print('DEBUG: Modalidad: $_modalidad');
      print('DEBUG: Monto: ${_montoCtrl.text}');
      print('DEBUG: Frecuencia: $_frecuencia');
      
      if (_montoCtrl.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Debe ingresar un monto');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe ingresar un monto'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final monto = double.tryParse(_montoCtrl.text);
      if (monto == null || monto <= 0) {
        setState(() => _errorMessage = 'El monto debe ser un número válido mayor a 0');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El monto debe ser un número válido mayor a 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      if (_modalidad == 'MONTO_TOTAL_CUOTAS' && _cuotas <= 0) {
        setState(() => _errorMessage = 'La cantidad de cuotas debe ser mayor a 0');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La cantidad de cuotas debe ser mayor a 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      print('DEBUG: Cláusulas Económicas válidas ✓');
    }

    if (_currentStep == 3) {
      print('DEBUG: Validando jugadores seleccionados');
      print('DEBUG: Jugadores: ${_jugadoresSeleccionados.length}');
      
      if (_jugadoresSeleccionados.isEmpty) {
        setState(() => _errorMessage = 'Debe seleccionar al menos un jugador');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe seleccionar al menos un jugador'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (_currentStep == 4) {
      // Generar preview antes de pasar al paso 5
      print('DEBUG: Generando preview');
      await _generarPreview();
      if (_preview == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? 'Error al generar preview'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (_currentStep == 5) {
      // Confirmar creación
      print('DEBUG: Confirmando creación');
      await _confirmarCreacion();
      return;
    }

    print('DEBUG: Avanzando al paso ${_currentStep + 1}');
    setState(() {
      _errorMessage = null;
      _currentStep++;
    });
  }

  Widget _buildStepTipo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seleccione el tipo de acuerdo que desea crear',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Ingreso'),
          subtitle: const Text('Ejemplo: Becas, subsidios'),
          leading: Radio<String>(
            value: 'INGRESO',
            groupValue: _tipo,
            onChanged: (value) {
              setState(() {
                _tipo = value!;
                _categoria = 'ENTRADAS'; // Resetear categoría al cambiar tipo
              });
            },
          ),
        ),
        ListTile(
          title: const Text('Egreso'),
          subtitle: const Text('Ejemplo: Sueldos, viáticos'),
          leading: Radio<String>(
            value: 'EGRESO',
            groupValue: _tipo,
            onChanged: (value) {
              setState(() {
                _tipo = value!;
                _categoria = 'PAGO JUGADORES'; // Resetear categoría al cambiar tipo
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStepDatosGenerales() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nombreCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre del acuerdo grupal',
            hintText: 'Ej: Sueldos Plantel 2024',
          ),
          validator: (v) => v == null || v.trim().isEmpty 
            ? 'Requerido' 
            : null,
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<String>>(
          key: ValueKey('categorias_$_tipo'), // Forzar recarga cuando cambie el tipo
          future: _cargarCategorias(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            
            if (snapshot.hasError) {
              return Text(
                'Error al cargar categorías: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              );
            }
            
            final categorias = snapshot.data ?? [];
            
            if (categorias.isEmpty) {
              return const Text(
                'No hay categorías disponibles para este tipo',
                style: TextStyle(color: Colors.orange),
              );
            }
            
            // Asegurar que la categoría seleccionada esté en la lista
            if (!categorias.contains(_categoria)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() => _categoria = categorias.first);
              });
            }
            
            return DropdownButtonFormField<String>(
              value: categorias.contains(_categoria) ? _categoria : categorias.first,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                helperText: 'Seleccione la categoría del movimiento',
              ),
              items: categorias.map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _categoria = value);
                }
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Debe seleccionar una categoría';
                }
                return null;
              },
            );
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _observacionesCtrl,
          decoration: const InputDecoration(
            labelText: 'Observaciones comunes (opcional)',
            hintText: 'Aplica a todos los acuerdos',
          ),
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildStepClausulas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Modalidad', style: TextStyle(fontWeight: FontWeight.bold)),
        ListTile(
          title: const Text('Recurrente'),
          subtitle: const Text('Mismo monto cada período'),
          leading: Radio<String>(
            value: 'RECURRENTE',
            groupValue: _modalidad,
            onChanged: (value) => setState(() => _modalidad = value!),
          ),
        ),
        ListTile(
          title: const Text('Monto Total en Cuotas'),
          subtitle: const Text('Dividir monto total en X cuotas'),
          leading: Radio<String>(
            value: 'MONTO_TOTAL_CUOTAS',
            groupValue: _modalidad,
            onChanged: (value) => setState(() => _modalidad = value!),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _montoCtrl,
          decoration: InputDecoration(
            labelText: _modalidad == 'RECURRENTE' 
              ? 'Monto Periódico' 
              : 'Monto Total',
            prefixText: '\$',
          ),
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Requerido';
            if (double.tryParse(v) == null) return 'Monto inválido';
            return null;
          },
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _cargarFrecuencias(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            
            if (snapshot.hasError) {
              return Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Error al cargar frecuencias: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }
            
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Text(
                'No hay frecuencias disponibles',
                style: TextStyle(color: Colors.orange),
              );
            }
            
            final frecuencias = snapshot.data!;
            
            // Asegurar que la frecuencia seleccionada esté en la lista
            if (!frecuencias.any((f) => f['codigo'] == _frecuencia)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() => _frecuencia = frecuencias.first['codigo'] as String);
              });
            }
            
            return DropdownButtonFormField<String>(
              value: frecuencias.any((f) => f['codigo'] == _frecuencia) 
                  ? _frecuencia 
                  : frecuencias.first['codigo'] as String,
              decoration: const InputDecoration(labelText: 'Frecuencia'),
              items: frecuencias.map((f) {
                return DropdownMenuItem(
                  value: f['codigo'] as String,
                  child: Text(f['descripcion'] as String),
                );
              }).toList(),
              onChanged: (value) => setState(() => _frecuencia = value!),
            );
          },
        ),
        const SizedBox(height: 16),
        if (_modalidad == 'MONTO_TOTAL_CUOTAS')
          TextFormField(
            initialValue: _cuotas.toString(),
            decoration: const InputDecoration(labelText: 'Cantidad de Cuotas'),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requerido';
              final n = int.tryParse(v);
              if (n == null || n <= 0) return 'Debe ser mayor a 0';
              return null;
            },
            onChanged: (v) => _cuotas = int.tryParse(v) ?? 12,
          ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Fecha de Inicio'),
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
            }
          },
        ),
        if (_modalidad == 'RECURRENTE')
          ListTile(
            title: const Text('Fecha de Fin (opcional)'),
            subtitle: Text(_fechaFin != null 
              ? DateFormat('dd/MM/yyyy').format(_fechaFin!) 
              : 'Sin fecha de fin'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final fecha = await showDatePicker(
                context: context,
                initialDate: _fechaFin ?? DateTime.now().add(const Duration(days: 365)),
                firstDate: _fechaInicio,
                lastDate: DateTime(2030),
              );
              setState(() => _fechaFin = fecha);
            },
          ),
      ],
    );
  }

  Widget _buildStepJugadores() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Seleccionados: ${_jugadoresSeleccionados.length}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 16),
        // Filtros
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _filtroNombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buscar por nombre',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filtroRol,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: const [
                  DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                  DropdownMenuItem(value: 'JUGADOR', child: Text('Jugador')),
                  DropdownMenuItem(value: 'DT', child: Text('DT')),
                  DropdownMenuItem(value: 'CUERPO_TECNICO', child: Text('Cuerpo Técnico')),
                ],
                onChanged: (v) {
                  setState(() => _filtroRol = v!);
                  _aplicarFiltros();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filtroTipoContratacion,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                  DropdownMenuItem(value: 'LOCAL', child: Text('Local')),
                  DropdownMenuItem(value: 'REFUERZO', child: Text('Refuerzo')),
                  DropdownMenuItem(value: 'OTRO', child: Text('Otro')),
                ],
                onChanged: (v) {
                  setState(() => _filtroTipoContratacion = v!);
                  _aplicarFiltros();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            height: 400,
            child: ListView.builder(
              itemCount: _jugadoresFiltrados.length,
              itemBuilder: (context, index) {
                final jugador = _jugadoresFiltrados[index];
                final id = jugador['id'] as int;
                final isSelected = _jugadoresSeleccionados.containsKey(id);
                
                return Card(
                  child: CheckboxListTile(
                    value: isSelected,
                    onChanged: (selected) => _toggleJugador(jugador, selected ?? false),
                    title: Text(jugador['nombre'] as String? ?? ''),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rol: ${jugador['rol'] ?? '-'}'),
                        if (jugador['alias'] != null)
                          Text('Alias: ${jugador['alias']}', 
                            style: const TextStyle(fontStyle: FontStyle.italic)),
                        if (isSelected)
                          Row(
                            children: [
                              const Text('Monto: \$'),
                              SizedBox(
                                width: 100,
                                child: TextFormField(
                                  initialValue: _jugadoresSeleccionados[id]!.monto.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(isDense: true),
                                  onChanged: (v) {
                                    final monto = double.tryParse(v) ?? 0;
                                    _ajustarMontoIndividual(id, monto);
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildStepPreview() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_preview == null) {
      return const Center(child: Text('No se pudo generar el preview'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumen Total',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Acuerdos a crear: ${_preview!.cantidadAcuerdos}'),
                  Text('Compromisos estimados: ${_preview!.totalCompromisos}'),
                  Text('Monto total: ${Format.money(_preview!.totalComprometido)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_validaciones.isNotEmpty)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Advertencias',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                    const SizedBox(height: 8),
                    ..._validaciones.entries.map((entry) {
                      final jugadorId = entry.key;
                      final warnings = entry.value;
                      final jugador = _jugadoresSeleccionados[jugadorId];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              jugador?.nombre ?? 'Jugador #$jugadorId',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            ...warnings.map((w) => Text('• $w')),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Detalle de Acuerdos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...(_preview!.previewsIndividuales.map((preview) {
            return Card(
              child: ExpansionTile(
                title: Text(preview.jugadorNombre),
                subtitle: Text('Monto: ${Format.money(preview.montoAjustado)}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compromisos estimados: ${preview.compromisosEstimados >= 0 ? preview.compromisosEstimados : "Indefinido"}'),
                        if (preview.compromisosEstimados > 0)
                          Text('Total estimado: ${Format.money(preview.montoAjustado * preview.compromisosEstimados)}'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          })),
        ],
      ),
    );
  }

  Widget _buildStepConfirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Todo listo para crear los acuerdos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Se crearán ${_preview?.cantidadAcuerdos ?? 0} acuerdos individuales'),
                if (_generaCompromisos)
                  Text('Se generarán ${_preview?.totalCompromisos ?? 0} compromisos automáticamente'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Generar compromisos automáticamente'),
          subtitle: const Text('Si se desactiva, deberás crearlos manualmente'),
          value: _generaCompromisos,
          onChanged: (value) => setState(() => _generaCompromisos = value),
        ),
        const SizedBox(height: 16),
        const Text(
          'Al confirmar, se creará un registro histórico que agrupa todos los acuerdos.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Future<List<String>> _cargarCategorias() async {
    try {
      print('DEBUG: Cargando categorías para tipo: $_tipo');
      final rawDb = await AppDatabase.instance();
      
      // Consultar categorías de categoria_movimiento según el tipo
      final result = await rawDb.query(
        'categoria_movimiento',
        columns: ['nombre'],
        where: 'activa = ? AND (tipo = ? OR tipo = ?)',
        whereArgs: [1, _tipo, 'AMBOS'],
        orderBy: 'nombre ASC',
      );
      
      print('DEBUG: Categorías encontradas: ${result.length}');
      
      final categorias = result
          .map((r) => r['nombre'] as String?)
          .where((c) => c != null && c.isNotEmpty)
          .cast<String>()
          .toList();
      
      // Si no hay categorías, retornar lista predefinida básica
      if (categorias.isEmpty) {
        print('DEBUG: No hay categorías en DB, usando fallback');
        if (_tipo == 'EGRESO') {
          return ['PAGO JUGADORES', 'SERVICIOS GENERALES / M.de Obra', 'GASTOS ATENCIÓN JUGADORES'];
        } else {
          return ['ENTRADAS', 'PEÑAS E INGRESOS VARIOS', 'COLABORADORES PAGO DT Y JUG'];
        }
      }
      
      print('DEBUG: Categorías cargadas: ${categorias.take(3).toList()}...');
      return categorias;
    } catch (e, stack) {
      print('ERROR: Al cargar categorías: $e');
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.cargar_categorias',
        error: e.toString(),
        stackTrace: stack,
      );
      // Fallback según tipo
      if (_tipo == 'EGRESO') {
        return ['PAGO JUGADORES', 'SERVICIOS GENERALES / M.de Obra'];
      } else {
        return ['ENTRADAS', 'PEÑAS E INGRESOS VARIOS'];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _cargarFrecuencias() async {
    try {
      print('DEBUG: Cargando frecuencias');
      final rawDb = await AppDatabase.instance();
      final result = await rawDb.query(
        'frecuencias',
        columns: ['codigo', 'descripcion'],
        orderBy: 'codigo ASC',
      );
      print('DEBUG: Frecuencias encontradas: ${result.length}');
      if (result.isNotEmpty) {
        print('DEBUG: Primera frecuencia: ${result.first}');
      }
      return result;
    } catch (e, stack) {
      print('ERROR: Al cargar frecuencias: $e');
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.cargar_frecuencias',
        error: e.toString(),
        stackTrace: stack,
      );
      return [];
    }
  }
}
