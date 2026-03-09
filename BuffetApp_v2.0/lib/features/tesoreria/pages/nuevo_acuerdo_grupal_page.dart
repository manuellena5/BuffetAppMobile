import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import '../../shared/utils/category_icon_helper.dart';
import '../../shared/widgets/selectable_card.dart';
import '../../shared/widgets/transaction_result_dialog.dart';
import '../../shared/widgets/wizard_scaffold.dart';
import '../services/acuerdos_grupales_service.dart';

/// Wizard profesional de 6 pasos para crear acuerdos grupales.
///
/// Diseño tipo Dynamics 365 / SAP:
/// - Barra horizontal de progreso
/// - Un paso visible a la vez en tarjeta central
/// - Botones siempre en la misma posición
/// - Tarjetas seleccionables para opciones
/// - Preview claro antes de confirmar
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

  // ---------------------------------------------------------------------------
  // Estado del wizard
  // ---------------------------------------------------------------------------
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Paso 1: Tipo
  String _tipo = 'EGRESO';

  // Paso 2: Datos generales
  final _nombreCtrl = TextEditingController();
  late int _unidadGestionId;
  String _categoria = 'PAGO JUGADORES';
  final _observacionesCtrl = TextEditingController();

  // Paso 3: Condiciones económicas
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
  String _filtroRol = 'TODOS';
  String _filtroTipoContratacion = 'TODOS';
  final _filtroNombreCtrl = TextEditingController();

  // Paso 5: Preview
  PreviewAcuerdoGrupal? _preview;
  Map<int, List<String>> _validaciones = {};

  // Paso 6: Confirmación
  bool _generaCompromisos = true;

  // Catálogos cacheados
  List<Map<String, dynamic>>? _categoriasCache;
  String? _categoriasCacheTipo;
  List<Map<String, dynamic>>? _frecuenciasCache;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Carga de datos
  // ---------------------------------------------------------------------------

  Future<void> _cargarJugadores() async {
    try {
      setState(() => _isLoading = true);
      final rawDb = await AppDatabase.instance();
      final result = await rawDb.query(
        'entidades_plantel',
        columns: [
          'id',
          'nombre',
          'rol',
          'alias',
          'tipo_contratacion',
          'posicion',
          'estado_activo',
        ],
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

  Future<List<Map<String, dynamic>>> _cargarCategorias() async {
    // Usar caché si el tipo no cambió
    if (_categoriasCache != null && _categoriasCacheTipo == _tipo) {
      return _categoriasCache!;
    }
    try {
      final rawDb = await AppDatabase.instance();
      final result = await rawDb.query(
        'categoria_movimiento',
        columns: ['codigo', 'nombre', 'icono'],
        where: 'activa = ? AND (tipo = ? OR tipo = ?)',
        whereArgs: [1, _tipo, 'AMBOS'],
        orderBy: 'nombre ASC',
      );
      if (result.isEmpty) {
        final fallback = _tipo == 'EGRESO'
            ? [
                {'codigo': 'PAGO JUGADORES', 'nombre': 'PAGO JUGADORES', 'icono': 'people'},
                {'codigo': 'SERVICIOS GENERALES / M.de Obra', 'nombre': 'SERVICIOS GENERALES / M.de Obra', 'icono': 'build'},
              ]
            : [
                {'codigo': 'ENTRADAS', 'nombre': 'ENTRADAS', 'icono': 'confirmation_number'},
                {'codigo': 'PEÑAS E INGRESOS VARIOS', 'nombre': 'PEÑAS E INGRESOS VARIOS', 'icono': 'groups'},
              ];
        _categoriasCache = fallback;
        _categoriasCacheTipo = _tipo;
        return fallback;
      }
      _categoriasCache = result;
      _categoriasCacheTipo = _tipo;
      return result;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.cargar_categorias',
        error: e.toString(),
        stackTrace: stack,
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _cargarFrecuencias() async {
    if (_frecuenciasCache != null) return _frecuenciasCache!;
    try {
      final rawDb = await AppDatabase.instance();
      final result = await rawDb.query(
        'frecuencias',
        columns: ['codigo', 'descripcion'],
        orderBy: 'codigo ASC',
      );
      _frecuenciasCache = result;
      return result;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.cargar_frecuencias',
        error: e.toString(),
        stackTrace: stack,
      );
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Filtros de jugadores
  // ---------------------------------------------------------------------------

  void _aplicarFiltros() {
    setState(() {
      _jugadoresFiltrados = _todosJugadores.where((j) {
        final nombre = (j['nombre'] as String? ?? '').toLowerCase();
        final texto = _filtroNombreCtrl.text.toLowerCase();
        if (texto.isNotEmpty && !nombre.contains(texto)) return false;
        if (_filtroRol != 'TODOS' && (j['rol'] as String? ?? '') != _filtroRol)
          return false;
        if (_filtroTipoContratacion != 'TODOS' &&
            (j['tipo_contratacion'] as String? ?? '') !=
                _filtroTipoContratacion) return false;
        return true;
      }).toList();
    });
  }

  void _toggleJugador(Map<String, dynamic> jugador, bool selected) {
    setState(() {
      final id = jugador['id'] as int;
      if (selected) {
        final montoBase = double.tryParse(_montoCtrl.text) ?? 0;
        _jugadoresSeleccionados[id] = JugadorConMonto(
          id: id,
          nombre: jugador['nombre'] as String? ?? '',
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

  void _seleccionarTodos() {
    setState(() {
      final montoBase = double.tryParse(_montoCtrl.text) ?? 0;
      for (final jugador in _jugadoresFiltrados) {
        final id = jugador['id'] as int;
        if (!_jugadoresSeleccionados.containsKey(id)) {
          _jugadoresSeleccionados[id] = JugadorConMonto(
            id: id,
            nombre: jugador['nombre'] as String? ?? '',
            rol: jugador['rol'] as String?,
            alias: jugador['alias'] as String?,
            tipoContratacion: jugador['tipo_contratacion'] as String?,
            posicion: jugador['posicion'] as String?,
            monto: montoBase,
          );
        }
      }
    });
  }

  void _deseleccionarTodos() {
    setState(() => _jugadoresSeleccionados.clear());
  }

  void _ajustarMontoIndividual(int jugadorId, double nuevoMonto) {
    setState(() {
      final j = _jugadoresSeleccionados[jugadorId];
      if (j != null) {
        _jugadoresSeleccionados[jugadorId] = JugadorConMonto(
          id: j.id,
          nombre: j.nombre,
          rol: j.rol,
          alias: j.alias,
          tipoContratacion: j.tipoContratacion,
          posicion: j.posicion,
          monto: nuevoMonto,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Preview & Creación
  // ---------------------------------------------------------------------------

  Future<void> _generarPreview() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final validacionRes = await _grupalSvc.validarJugadores(
        jugadores: _jugadoresSeleccionados.values.toList(),
        unidadGestionId: _unidadGestionId,
        categoria: _categoria,
      );

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
        _preview = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmarCreacion() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final resultado = await _grupalSvc.crearAcuerdosGrupales(
        nombre: _nombreCtrl.text.trim(),
        unidadGestionId: _unidadGestionId,
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

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (resultado.todoExitoso) {
        await TransactionResultDialog.showSuccess(
          context: context,
          title: 'Acuerdo Grupal Creado',
          message:
              'Se crearon ${resultado.cantidadCreados} acuerdos individuales correctamente.',
          details: [
            TransactionDetail(label: 'Nombre', value: _nombreCtrl.text.trim()),
            TransactionDetail(
              label: 'Tipo',
              value: _tipo == 'INGRESO' ? 'Ingreso' : 'Egreso',
            ),
            TransactionDetail(label: 'Categoría', value: _categoria),
            TransactionDetail(label: 'Modalidad', value: _modalidadLabel),
            TransactionDetail(
              label: 'Acuerdos creados',
              value: '${resultado.cantidadCreados}',
              style: TransactionDetailStyle.success,
            ),
            if (_generaCompromisos)
              TransactionDetail(
                label: 'Compromisos generados',
                value: '${_preview?.totalCompromisos ?? '-'}',
                style: TransactionDetailStyle.success,
              ),
            if (_preview != null)
              TransactionDetail(
                label: 'Total comprometido',
                value: Format.money(_preview!.totalComprometido),
                style: TransactionDetailStyle.highlight,
              ),
          ],
          onDismiss: () {
            if (mounted) Navigator.pop(context, resultado);
          },
        );
      } else {
        await TransactionResultDialog.showWarning(
          context: context,
          title: 'Creado con Advertencias',
          message:
              'Se crearon ${resultado.cantidadCreados} acuerdos pero hubo errores.',
          details: [
            TransactionDetail(
              label: 'Creados',
              value: '${resultado.cantidadCreados}',
              style: TransactionDetailStyle.success,
            ),
            TransactionDetail(
              label: 'Errores',
              value: '${resultado.errores.length}',
              style: TransactionDetailStyle.error,
            ),
          ],
          warnings:
              resultado.errores.map((e) => TransactionWarning(e)).toList(),
          onDismiss: () {
            if (mounted) Navigator.pop(context, resultado);
          },
        );
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'nuevo_acuerdo_grupal.confirmar_creacion',
        error: e.toString(),
        stackTrace: stack,
      );

      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al crear acuerdos: ${e.toString()}';
      });

      if (!mounted) return;

      await TransactionResultDialog.showError(
        context: context,
        title: 'Error al Crear Acuerdos',
        message:
            'No se pudo completar la operación. Por favor, revise los datos e intente nuevamente.',
        technicalDetail: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Navegación del wizard
  // ---------------------------------------------------------------------------

  void _onNext() async {
    if (_isLoading) return;

    switch (_currentStep) {
      case 0:
        break;
      case 1:
        if (_nombreCtrl.text.trim().isEmpty) {
          _mostrarError('Debe ingresar un nombre para el acuerdo');
          return;
        }
        if (_categoria.isEmpty) {
          _mostrarError('Debe seleccionar una categoría');
          return;
        }
        break;
      case 2:
        if (_montoCtrl.text.trim().isEmpty) {
          _mostrarError('Debe ingresar un monto');
          return;
        }
        final monto = double.tryParse(_montoCtrl.text);
        if (monto == null || monto <= 0) {
          _mostrarError('El monto debe ser un número válido mayor a 0');
          return;
        }
        if (_modalidad == 'MONTO_TOTAL_CUOTAS' && _cuotas <= 0) {
          _mostrarError('La cantidad de cuotas debe ser mayor a 0');
          return;
        }
        break;
      case 3:
        if (_jugadoresSeleccionados.isEmpty) {
          _mostrarError('Debe seleccionar al menos un jugador');
          return;
        }
        // Generar preview ANTES de entrar al paso de revisión
        await _generarPreview();
        if (_preview == null) return;
        break;
      case 4:
        // Ya se revisó el preview, pasar a confirmación
        break;
      case 5:
        await _confirmarCreacion();
        return;
    }

    setState(() {
      _errorMessage = null;
      _currentStep++;
    });
  }

  void _onBack() {
    if (_currentStep > 0) {
      setState(() {
        _errorMessage = null;
        _currentStep--;
      });
    }
  }

  void _mostrarError(String msg) {
    setState(() => _errorMessage = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.egreso),
    );
  }

  String get _modalidadLabel => _modalidad == 'MONTO_TOTAL_CUOTAS'
      ? 'Monto total en cuotas'
      : 'Recurrente';

  /// Verifica si el formulario tiene datos ingresados.
  bool get _tieneProgreso =>
      _currentStep > 0 ||
      _nombreCtrl.text.trim().isNotEmpty ||
      _montoCtrl.text.trim().isNotEmpty ||
      _jugadoresSeleccionados.isNotEmpty;

  /// Maneja el intento de cancelar/salir del wizard.
  Future<void> _onCancel() async {
    if (_isLoading) return;

    if (_tieneProgreso) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded,
              color: AppColors.advertencia, size: 36),
          title: const Text('¿Desea salir?'),
          content: const Text(
            'Tiene datos ingresados en el formulario. '
            'Si sale ahora, perderá todo el progreso.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.egreso),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salir y descartar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    if (mounted) Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: WizardScaffold(
        title: 'Nuevo Acuerdo Grupal',
        currentStep: _currentStep,
        isLoading: _isLoading,
        onNext: _onNext,
        onBack: _onBack,
        onCancel: _onCancel,
        finalButtonText: 'Crear Acuerdos',
        finalButtonIcon: Icons.check_circle,
        maxWidth: 700,
        steps: [
          WizardStepDef(
            label: 'Tipo',
            title: 'Tipo de Acuerdo',
            subtitle: '¿Qué tipo de acuerdo desea crear?',
            content: _buildStepTipo(),
          ),
          WizardStepDef(
            label: 'Datos',
            title: 'Datos Generales',
            subtitle: 'Información básica del acuerdo grupal',
            content: _buildStepDatos(),
          ),
          WizardStepDef(
            label: 'Condiciones',
            title: 'Condiciones Económicas',
            subtitle: 'Modalidad de pago, monto y frecuencia',
            content: _buildStepCondiciones(),
          ),
          WizardStepDef(
            label: 'Jugadores',
            title: 'Selección de Jugadores',
            subtitle: 'Elija los jugadores que participarán en este acuerdo',
            content: _buildStepJugadores(),
          ),
          WizardStepDef(
            label: 'Revisar',
            title: 'Revisión del Acuerdo',
            subtitle: 'Verifique los datos antes de confirmar',
            content: _buildStepPreview(),
          ),
          WizardStepDef(
            label: 'Confirmar',
            title: 'Confirmación',
            subtitle: 'Revise las opciones finales y confirme la creación',
            content: _buildStepConfirmacion(),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PASO 1: TIPO
  // ===========================================================================

  Widget _buildStepTipo() {
    return Column(
      children: [
        SelectableCard<String>(
          value: 'EGRESO',
          groupValue: _tipo,
          onChanged: (v) => setState(() {
            _tipo = v;
            _categoria = 'PAGO JUGADORES';
            _categoriasCache = null;
          }),
          icon: Icons.trending_down,
          iconColor: AppColors.egreso,
          title: 'Egreso',
          subtitle: 'Sueldos, premios, viáticos, servicios',
        ),
        const SizedBox(height: 12),
        SelectableCard<String>(
          value: 'INGRESO',
          groupValue: _tipo,
          onChanged: (v) => setState(() {
            _tipo = v;
            _categoria = 'ENTRADAS';
            _categoriasCache = null;
          }),
          icon: Icons.trending_up,
          iconColor: AppColors.ingreso,
          title: 'Ingreso',
          subtitle: 'Adhesiones, Sponsor, Colaboraciones',
        ),
      ],
    );
  }

  // ===========================================================================
  // PASO 2: DATOS GENERALES
  // ===========================================================================

  Widget _buildStepDatos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        TextFormField(
          controller: _nombreCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre del acuerdo *',
            hintText: 'Ej: Sueldos Plantel Mayo 2026',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.description_outlined),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey('cat_$_tipo'),
          future: _cargarCategorias(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            final categorias = snap.data ?? [];
            if (categorias.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.advertenciaDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.advertencia),
                ),
                child: const Text(
                  '⚠ No hay categorías configuradas para este tipo',
                  style: TextStyle(color: AppColors.advertencia),
                ),
              );
            }
            // Autoseleccionar si la categoría actual no es válida
            final esValida =
                categorias.any((c) => c['nombre'] == _categoria);
            if (!esValida) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() =>
                    _categoria = categorias.first['nombre'] as String);
              });
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                return Autocomplete<Map<String, dynamic>>(
                  initialValue: TextEditingValue(text: _categoria),
                  displayStringForOption: (cat) =>
                      cat['nombre']?.toString() ?? '',
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) return categorias;
                    final query = textEditingValue.text.toLowerCase();
                    return categorias.where((cat) {
                      final nombre =
                          (cat['nombre']?.toString() ?? '').toLowerCase();
                      final codigo =
                          (cat['codigo']?.toString() ?? '').toLowerCase();
                      return nombre.contains(query) || codigo.contains(query);
                    });
                  },
                  onSelected: (cat) {
                    setState(
                        () => _categoria = cat['nombre']?.toString() ?? '');
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Categoría *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category_outlined),
                        hintText: 'Escribí para buscar...',
                      ),
                      onChanged: (text) {
                        final match = categorias.where((c) =>
                            (c['nombre']?.toString() ?? '').toLowerCase() ==
                            text.toLowerCase());
                        if (match.isEmpty) {
                          _categoria = '';
                        }
                      },
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: 250,
                            maxWidth: constraints.maxWidth,
                          ),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final cat = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  CategoryIconHelper.fromName(
                                      cat['icono'] as String?),
                                  size: 20,
                                ),
                                title: Text(cat['nombre']?.toString() ?? ''),
                                onTap: () => onSelected(cat),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _observacionesCtrl,
          decoration: const InputDecoration(
            labelText: 'Observaciones (opcional)',
            hintText: 'Aplica a todos los acuerdos generados',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          maxLines: 2,
        ),
      ],
    );
  }

  // ===========================================================================
  // PASO 3: CONDICIONES ECONÓMICAS
  // ===========================================================================

  Widget _buildStepCondiciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        const _SectionLabel('Modalidad de pago'),
        const SizedBox(height: 8),
        SelectableCard<String>(
          value: 'RECURRENTE',
          groupValue: _modalidad,
          onChanged: (v) => setState(() => _modalidad = v),
          icon: Icons.repeat,
          title: 'Recurrente',
          subtitle: 'Mismo monto cada período (ej: sueldo mensual)',
        ),
        const SizedBox(height: 8),
        SelectableCard<String>(
          value: 'MONTO_TOTAL_CUOTAS',
          groupValue: _modalidad,
          onChanged: (v) => setState(() => _modalidad = v),
          icon: Icons.pie_chart_outline,
          title: 'Monto total en cuotas',
          subtitle: 'Dividir un monto total en X cuotas iguales',
        ),
        const SizedBox(height: 24),
        const _SectionLabel('Monto'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _montoCtrl,
          decoration: InputDecoration(
            labelText: _modalidad == 'RECURRENTE'
                ? 'Monto periódico *'
                : 'Monto total *',
            prefixText: '\$ ',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.attach_money),
          ),
          keyboardType: TextInputType.number,
        ),
        if (_modalidad == 'MONTO_TOTAL_CUOTAS') ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _cuotas.toString(),
            decoration: const InputDecoration(
              labelText: 'Cantidad de cuotas *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.format_list_numbered),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) => _cuotas = int.tryParse(v) ?? 12,
          ),
        ],
        const SizedBox(height: 24),
        const _SectionLabel('Frecuencia'),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _cargarFrecuencias(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            final frecuencias = snap.data ?? [];
            if (frecuencias.isEmpty) {
              return const Text('No hay frecuencias disponibles',
                  style: TextStyle(color: AppColors.advertencia));
            }
            if (!frecuencias.any((f) => f['codigo'] == _frecuencia)) {
              WidgetsBinding.instance.addPostFrameCallback((_) => setState(
                  () => _frecuencia = frecuencias.first['codigo'] as String));
            }
            return DropdownButtonFormField<String>(
              value: frecuencias.any((f) => f['codigo'] == _frecuencia)
                  ? _frecuencia
                  : frecuencias.first['codigo'] as String,
              decoration: const InputDecoration(
                labelText: 'Frecuencia *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.schedule),
              ),
              items: frecuencias
                  .map((f) => DropdownMenuItem(
                        value: f['codigo'] as String,
                        child: Text(f['descripcion'] as String),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _frecuencia = v!),
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionLabel('Período'),
        const SizedBox(height: 8),
        _DateField(
          label: 'Fecha de inicio *',
          value: _fechaInicio,
          onChanged: (d) => setState(() => _fechaInicio = d),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        ),
        const SizedBox(height: 12),
        if (_modalidad == 'RECURRENTE')
          _DateField(
            label: 'Fecha de fin (opcional)',
            value: _fechaFin ?? _fechaInicio,
            onChanged: (d) => setState(() => _fechaFin = d),
            firstDate: _fechaInicio,
            lastDate: DateTime(2030),
            allowClear: true,
            onClear: () => setState(() => _fechaFin = null),
          ),
      ],
    );
  }

  // ===========================================================================
  // PASO 4: JUGADORES
  // ===========================================================================

  Widget _buildStepJugadores() {
    final total = _jugadoresFiltrados.length;
    final seleccionados = _jugadoresSeleccionados.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),

        // Resumen + acciones
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: seleccionados > 0
                    ? AppColors.ingresoDim
                    : AppColors.bgElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      seleccionados > 0 ? AppColors.ingreso : AppColors.border,
                ),
              ),
              child: Text(
                '$seleccionados seleccionado${seleccionados != 1 ? 's' : ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: seleccionados > 0
                      ? AppColors.ingreso
                      : AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: seleccionados > 0 ? _deseleccionarTodos : null,
              icon: const Icon(Icons.deselect, size: 18),
              label: const Text('Limpiar'),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: total > 0 ? _seleccionarTodos : null,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Todos'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Búsqueda
        TextField(
          controller: _filtroNombreCtrl,
          decoration: const InputDecoration(
            hintText: 'Buscar por nombre...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),

        // Filtros rápidos
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filtroRol,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                  DropdownMenuItem(value: 'JUGADOR', child: Text('Jugador')),
                  DropdownMenuItem(value: 'DT', child: Text('DT')),
                  DropdownMenuItem(
                      value: 'CUERPO_TECNICO', child: Text('Cuerpo Técnico')),
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
                decoration: const InputDecoration(
                  labelText: 'Contratación',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
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
        const SizedBox(height: 12),

        // Lista de jugadores
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_jugadoresFiltrados.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.person_off, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  const Text('No se encontraron jugadores',
                      style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
          )
        else
          ..._jugadoresFiltrados.map((jugador) {
            final id = jugador['id'] as int;
            final isSelected = _jugadoresSeleccionados.containsKey(id);
            final nombre = jugador['nombre'] as String? ?? '';
            final rol = jugador['rol'] as String? ?? '';
            final tipo = jugador['tipo_contratacion'] as String? ?? '';
            final posicion = jugador['posicion'] as String? ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _toggleJugador(jugador, !isSelected),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.infoDim : null,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.info
                            : AppColors.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Checkbox
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color:
                                isSelected ? AppColors.info : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.info
                                  : AppColors.textMuted,
                              width: isSelected ? 0 : 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),

                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                              if (rol.isNotEmpty ||
                                  posicion.isNotEmpty ||
                                  tipo.isNotEmpty)
                                Text(
                                  [
                                    if (rol.isNotEmpty) rol,
                                    if (posicion.isNotEmpty) posicion,
                                    if (tipo.isNotEmpty) tipo,
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Monto individual (solo si seleccionado)
                        if (isSelected)
                          SizedBox(
                            width: 110,
                            child: TextFormField(
                              initialValue: _jugadoresSeleccionados[id]!
                                  .monto
                                  .toStringAsFixed(0),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (v) {
                                final monto = double.tryParse(v) ?? 0;
                                _ajustarMontoIndividual(id, monto);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  // ===========================================================================
  // PASO 5: PREVIEW
  // ===========================================================================

  Widget _buildStepPreview() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generando resumen...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState(onRetry: _generarPreview);
    }

    if (_preview == null) {
      return _buildErrorState(
        message: 'No se pudo generar el resumen',
        onRetry: _generarPreview,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Resumen general
        _SummaryCard(
          items: [
            _SummaryItem(
              icon: Icons.description,
              label: 'Nombre',
              value: _nombreCtrl.text.trim(),
            ),
            _SummaryItem(
              icon: _tipo == 'EGRESO' ? Icons.trending_down : Icons.trending_up,
              label: 'Tipo',
              value: _tipo == 'INGRESO' ? 'Ingreso' : 'Egreso',
            ),
            _SummaryItem(
              icon: Icons.category,
              label: 'Categoría',
              value: _categoria,
            ),
            _SummaryItem(
              icon: Icons.repeat,
              label: 'Modalidad',
              value: _modalidadLabel,
            ),
            _SummaryItem(
              icon: Icons.schedule,
              label: 'Frecuencia',
              value: _frecuencia,
            ),
            _SummaryItem(
              icon: Icons.calendar_today,
              label: 'Desde',
              value: DateFormat('dd/MM/yyyy').format(_fechaInicio),
            ),
            if (_fechaFin != null)
              _SummaryItem(
                icon: Icons.event,
                label: 'Hasta',
                value: DateFormat('dd/MM/yyyy').format(_fechaFin!),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // KPIs
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Acuerdos',
                value: '${_preview!.cantidadAcuerdos}',
                icon: Icons.handshake_outlined,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                label: 'Compromisos',
                value: _preview!.totalCompromisos >= 0
                    ? '${_preview!.totalCompromisos}'
                    : 'Indef.',
                icon: Icons.receipt_long,
                color: AppColors.accentDim,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                label: 'Total',
                value: Format.money(_preview!.totalComprometido),
                icon: Icons.attach_money,
                color: AppColors.ingreso,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Advertencias
        if (_validaciones.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.advertenciaDim,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.advertencia),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber,
                        size: 18, color: AppColors.advertencia),
                    const SizedBox(width: 6),
                    Text(
                      'Advertencias',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.advertencia,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._validaciones.entries.map((entry) {
                  final jugador = _jugadoresSeleccionados[entry.key];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${jugador?.nombre ?? '#${entry.key}'}: ${entry.value.join(', ')}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.advertencia),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Detalle individual
        const _SectionLabel('Detalle por jugador'),
        const SizedBox(height: 8),
        ...(_preview!.previewsIndividuales.map((p) {
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: AppDecorations.cardOf(context),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.infoDim,
                child: Text(
                  p.jugadorNombre.isNotEmpty
                      ? p.jugadorNombre[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.info,
                  ),
                ),
              ),
              title: Text(p.jugadorNombre,
                  style: AppText.bodyMd.copyWith(fontWeight: FontWeight.w500)),
              subtitle: Text(
                '${p.compromisosEstimados >= 0 ? '${p.compromisosEstimados} cuotas' : 'Indefinido'} · ${Format.money(p.montoAjustado)}',
                style: AppText.caption,
              ),
              trailing: p.compromisosEstimados > 0
                  ? Text(
                      Format.money(p.montoAjustado * p.compromisosEstimados),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.ingreso,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
          );
        })),
      ],
    );
  }

  // ===========================================================================
  // PASO 6: CONFIRMACIÓN
  // ===========================================================================

  Widget _buildStepConfirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.ingresoDim,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.ingresoLight),
          ),
          child: Column(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 48, color: AppColors.ingreso),
              const SizedBox(height: 12),
              const Text(
                'Todo listo para crear los acuerdos',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Se crearán ${_preview?.cantidadAcuerdos ?? _jugadoresSeleccionados.length} acuerdos individuales',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (_generaCompromisos && _preview != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Se generarán ${_preview!.totalCompromisos} compromisos automáticamente',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Total comprometido: ${Format.money(_preview!.totalComprometido)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ingreso,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SwitchListTile(
            title: const Text('Generar compromisos automáticamente',
                style: TextStyle(color: AppColors.textPrimary)),
            subtitle: const Text(
                'Si se desactiva, deberá crearlos manualmente después',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            value: _generaCompromisos,
            onChanged: (v) => setState(() => _generaCompromisos = v),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.infoDim,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Al confirmar se creará un registro histórico que agrupa todos los acuerdos. '
                  'Cada acuerdo individual se podrá gestionar de forma independiente.',
                  style: TextStyle(fontSize: 13, color: AppColors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WIDGETS AUXILIARES
  // ===========================================================================

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.egresoDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.egresoLight),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.egreso, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.egreso, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState({String? message, VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.egresoLight),
            const SizedBox(height: 16),
            Text(
              message ?? _errorMessage ?? 'Ocurrió un error',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.egreso),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// WIDGETS PRIVADOS AUXILIARES
// =============================================================================

/// Etiqueta de sección usada dentro de los pasos del wizard.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7280),
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Campo de fecha con botón de calendario y opción de limpieza.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool allowClear;
  final VoidCallback? onClear;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.allowClear = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: allowClear && onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(DateFormat('dd/MM/yyyy').format(value)),
      ),
    );
  }
}

/// Card con ítems de resumen (icono + label + valor).
class _SummaryCard extends StatelessWidget {
  final List<_SummaryItem> items;
  const _SummaryCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        item.value,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _SummaryItem {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Tarjeta de KPI para métricas clave.
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
