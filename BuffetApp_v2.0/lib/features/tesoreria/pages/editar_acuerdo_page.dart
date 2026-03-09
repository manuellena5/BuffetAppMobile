import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../features/shared/services/acuerdos_service.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import '../../shared/utils/category_icon_helper.dart';
import '../../shared/widgets/responsive_container.dart';
import '../widgets/ayuda_tesoreria_dialog.dart';

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

  // Categoría / subcategoría
  String? _codigoCategoria;
  int? _subcategoriaId;
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _subcategorias = [];

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _tieneConfirmados = false;
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

      // Verificar compromisos confirmados (informativo, no bloquea)
      final stats =
          await AcuerdosService.obtenerEstadisticasAcuerdo(widget.acuerdoId);
      final cuotasConfirmadas = stats['cuotas_confirmadas'] as int? ?? 0;

      // Cargar catálogos de categorías y subcategorías
      final categorias = await CategoriaMovimientoService.obtenerCategorias();
      final db = await AppDatabase.instance();
      final subcategorias = await db.query(
        'subcategorias',
        where: 'activa = 1',
        orderBy: 'categoria_id, orden, nombre',
      );

      // Cargar datos al formulario
      _nombreController.text = acuerdo['nombre']?.toString() ?? '';
      _observacionesController.text =
          acuerdo['observaciones']?.toString() ?? '';

      final fechaInicioStr = acuerdo['fecha_inicio']?.toString();
      final fechaFinStr = acuerdo['fecha_fin']?.toString();

      setState(() {
        _acuerdo = acuerdo;
        _fechaInicio =
            fechaInicioStr != null ? DateTime.parse(fechaInicioStr) : null;
        _fechaFin = fechaFinStr != null ? DateTime.parse(fechaFinStr) : null;
        _tieneConfirmados = cuotasConfirmadas > 0;
        _categorias = categorias;
        _subcategorias = subcategorias;
        _codigoCategoria = acuerdo['categoria']?.toString();
        _subcategoriaId = (acuerdo['subcategoria_id'] as num?)?.toInt();
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
        categoria: _codigoCategoria,
        subcategoriaId: _subcategoriaId,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Ayuda',
            onPressed: () => AyudaTesoreriaDialog.show(context),
          ),
        ],
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
                    if (_tieneConfirmados)
                      Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_outlined,
                                  color: Colors.orange.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Este acuerdo tiene compromisos confirmados. Solo podés editar nombre, fecha de fin, observaciones y categoría.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.blue.shade700),
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
                      validator: (val) =>
                          val?.trim().isEmpty ?? true ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    // Categoría (Autocomplete — permite tipear + buscar)
                    Builder(
                      builder: (context) {
                        if (_categorias.isEmpty) {
                          return InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Categoría',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              'Cargando categorías...',
                              style:
                                  TextStyle(color: Colors.grey.shade500),
                            ),
                          );
                        }
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return Autocomplete<Map<String, dynamic>>(
                              initialValue: _codigoCategoria != null
                                  ? TextEditingValue(
                                      text: _categorias
                                              .where((c) =>
                                                  c['codigo'] ==
                                                  _codigoCategoria)
                                              .map((c) =>
                                                  c['nombre'].toString())
                                              .firstOrNull ??
                                          '',
                                    )
                                  : TextEditingValue.empty,
                              displayStringForOption: (cat) =>
                                  cat['nombre'].toString(),
                              optionsBuilder: (textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return _categorias;
                                }
                                final query =
                                    textEditingValue.text.toLowerCase();
                                return _categorias.where((cat) {
                                  final nombre =
                                      cat['nombre'].toString().toLowerCase();
                                  final codigo =
                                      cat['codigo'].toString().toLowerCase();
                                  return nombre.contains(query) ||
                                      codigo.contains(query);
                                });
                              },
                              onSelected: (cat) {
                                setState(() {
                                  _codigoCategoria =
                                      cat['codigo'].toString();
                                  _subcategoriaId = null;
                                });
                              },
                              fieldViewBuilder: (context, controller,
                                  focusNode, onFieldSubmitted) {
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'Categoría',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.category),
                                    hintText: 'Escribí para buscar...',
                                  ),
                                  onChanged: (text) {
                                    final match = _categorias.where(
                                      (c) =>
                                          c['nombre']
                                              .toString()
                                              .toLowerCase() ==
                                          text.toLowerCase(),
                                    );
                                    if (match.isEmpty) {
                                      setState(() {
                                        _codigoCategoria = null;
                                        _subcategoriaId = null;
                                      });
                                    }
                                  },
                                );
                              },
                              optionsViewBuilder:
                                  (context, onSelected, options) {
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
                                          final cat =
                                              options.elementAt(index);
                                          return ListTile(
                                            dense: true,
                                            leading: Icon(
                                              CategoryIconHelper.fromName(
                                                  cat['icono'] as String?),
                                              size: 20,
                                            ),
                                            title: Text(
                                                cat['nombre'].toString()),
                                            subtitle: Text(
                                              cat['codigo'].toString(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
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
                    // Subcategoría (dinámica, según la categoría seleccionada)
                    if (_subcategoriasActuales.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: _subcategoriaId,
                        decoration: const InputDecoration(
                          labelText: 'Subcategoría',
                          border: OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.subdirectory_arrow_right),
                        ),
                        items: _subcategoriasActuales
                            .map((s) => DropdownMenuItem<int>(
                                  value: s['id'] as int,
                                  child: Text(s['nombre'].toString()),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _subcategoriaId = val);
                        },
                      ),
                    ],
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
                              onPressed: () =>
                                  setState(() => _fechaFin = null),
                            )
                          : null,
                      onTap: () async {
                        final fecha = await showDatePicker(
                          context: context,
                          initialDate:
                              _fechaFin ?? _fechaInicio ?? DateTime.now(),
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
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.outline,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Los siguientes campos no se pueden modificar porque afectarían los compromisos ya generados:',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (_acuerdo != null) ...[
                      _buildInfoReadOnly(
                          'Tipo', _acuerdo!['tipo']?.toString() ?? '-'),
                      _buildInfoReadOnly(
                          'Modalidad',
                          _modalidadLabel(
                              _acuerdo!['modalidad']?.toString() ?? '-')),
                      _buildInfoReadOnly(
                        'Monto',
                        _acuerdo!['modalidad'] == 'MONTO_TOTAL_CUOTAS'
                            ? '\$ ${_acuerdo!['monto_total']}'
                            : '\$ ${_acuerdo!['monto_periodico']}',
                      ),
                      _buildInfoReadOnly('Frecuencia',
                          _acuerdo!['frecuencia']?.toString() ?? '-'),
                      _buildInfoReadOnly(
                        'Fecha Inicio',
                        _fechaInicio != null
                            ? DateFormat('dd/MM/yyyy').format(_fechaInicio!)
                            : '-',
                      ),
                    ],
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                _isSubmitting ? null : _guardarCambios,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Guardar Cambios'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Map<String, dynamic>> get _subcategoriasActuales {
    if (_codigoCategoria == null) return [];
    final matchingCats =
        _categorias.where((c) => c['codigo'] == _codigoCategoria);
    if (matchingCats.isEmpty) return [];
    final catId = matchingCats.first['id'] as int?;
    if (catId == null) return [];
    return _subcategorias
        .where((s) =>
            s['categoria_id'] == catId && (s['activa'] as int? ?? 1) == 1)
        .toList();
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
