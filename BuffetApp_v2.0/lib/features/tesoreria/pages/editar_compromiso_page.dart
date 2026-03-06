import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../../features/shared/state/app_settings.dart';
import '../../../features/shared/format.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import '../../shared/utils/category_icon_helper.dart';
import '../../shared/widgets/responsive_container.dart';
import '../widgets/ayuda_tesoreria_dialog.dart';

/// Pagina para editar un compromiso financiero existente.
///
/// Compromisos PAGO_UNICO (manuales): se editan todos los campos.
/// Compromisos generados por Acuerdo: solo se editan nombre, observaciones
/// y fecha. Para cambiar montos/frecuencia, editar el Acuerdo origen.
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
  final _plantelService = PlantelService.instance;

  // Controllers
  final _nombreController = TextEditingController();
  final _montoController = TextEditingController();
  final _observacionesController = TextEditingController();

  // Form values
  String _tipo = 'INGRESO';
  String _modalidad = 'PAGO_UNICO';
  String _frecuencia = 'UNICA_VEZ';
  DateTime _fechaInicio = DateTime.now();
  int _unidadGestionId = 1;
  String? _codigoCategoria;
  int? _entidadPlantelId;
  int? _acuerdoId;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _entidadesPlantel = [];

  /// true si el compromiso fue generado automaticamente por un Acuerdo
  bool get _esDeAcuerdo => _acuerdoId != null;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    _observacionesController.dispose();
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

      // Cargar entidades del plantel
      final entidades = await _plantelService.listarEntidades(soloActivos: true);

      // Cargar categorias
      final categorias = await CategoriaMovimientoService.obtenerCategoriasPorTipo(
        tipo: compromiso['tipo'] as String? ?? 'INGRESO',
      );

      // Llenar campos con datos existentes
      _nombreController.text = compromiso['nombre'] as String? ?? '';
      _montoController.text = (compromiso['monto'] as double?)?.toString() ?? '';
      _codigoCategoria = compromiso['categoria'] as String?;
      _observacionesController.text = compromiso['observaciones'] as String? ?? '';

      _tipo = compromiso['tipo'] as String? ?? 'INGRESO';
      _modalidad = compromiso['modalidad'] as String? ?? 'PAGO_UNICO';
      _frecuencia = compromiso['frecuencia'] as String? ?? 'UNICA_VEZ';
      _acuerdoId = compromiso['acuerdo_id'] as int?;

      final unidadActivaId = settings.unidadGestionActivaId;
      _unidadGestionId = unidadActivaId ?? compromiso['unidad_gestion_id'] as int? ?? 1;

      if (compromiso['fecha_inicio'] != null) {
        _fechaInicio = DateTime.parse(compromiso['fecha_inicio'] as String);
      }

      _entidadPlantelId = compromiso['entidad_plantel_id'] as int?;

      setState(() {
        _categorias = categorias;
        _entidadesPlantel = entidades;
        _isLoading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'editar_compromiso.cargar',
        error: e,
        stackTrace: st,
        payload: {'compromisoId': widget.compromisoId},
      );

      setState(() {
        _error = 'Error al cargar los datos del compromiso.';
        _isLoading = false;
      });
    }
  }

  /// Recarga categorias cuando cambia el tipo (INGRESO/EGRESO)
  Future<void> _cargarCategorias() async {
    try {
      final cats = await CategoriaMovimientoService.obtenerCategoriasPorTipo(tipo: _tipo);
      setState(() {
        _categorias = cats;
        if (_codigoCategoria != null) {
          final esValida = _categorias.any((cat) => cat['codigo'] == _codigoCategoria);
          if (!esValida) {
            _codigoCategoria = null;
          }
        }
      });
    } catch (e) {
      // Mantener lista vacia
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final monto = double.parse(_montoController.text);

    // Modal de confirmacion
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.orange[700]),
            const SizedBox(width: 12),
            const Text('Confirmar Cambios'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Guardar los cambios del compromiso?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
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
                  _buildInfoRow('Monto', Format.money(monto)),
                  _buildInfoRow('Fecha', DateFormat('dd/MM/yyyy').format(_fechaInicio)),
                ],
              ),
            ),
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
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isSubmitting = true);

    try {
      await _compromisosService.actualizarCompromiso(
        widget.compromisoId,
        nombre: _nombreController.text.trim(),
        tipo: _tipo,
        modalidad: _modalidad,
        monto: monto,
        frecuencia: _frecuencia,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        categoria: _codigoCategoria ?? '',
        observaciones: _observacionesController.text.trim().isNotEmpty
            ? _observacionesController.text.trim()
            : null,
        entidadPlantelId: _entidadPlantelId,
      );

      // Para PAGO_UNICO sin acuerdo, regenerar la unica cuota
      if (!_esDeAcuerdo) {
        final db = await AppDatabase.instance();
        await db.delete('compromiso_cuotas',
            where: 'compromiso_id = ?', whereArgs: [widget.compromisoId]);
        final cuotas = await _compromisosService.generarCuotas(widget.compromisoId);
        await _compromisosService.guardarCuotas(widget.compromisoId, cuotas);
      }

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                const SizedBox(width: 12),
                const Text('Compromiso Actualizado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('El compromiso se actualizo correctamente.'),
                const SizedBox(height: 12),
                _buildInfoRow('Nombre', _nombreController.text.trim()),
                _buildInfoRow('Tipo', _tipo),
                _buildInfoRow('Monto', Format.money(monto)),
                _buildInfoRow('Fecha', DateFormat('dd/MM/yyyy').format(_fechaInicio)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Cierra dialog
                  Navigator.pop(context, true); // Retorna a pantalla anterior
                },
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
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
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 32),
                const SizedBox(width: 12),
                const Text('Error al Actualizar'),
              ],
            ),
            content: const Text(
              'No se pudo actualizar el compromiso. Por favor, intente nuevamente.',
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
        title: const Text('Editar Compromiso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Ayuda',
            onPressed: () => AyudaTesoreriaDialog.show(context),
          ),
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

    return ResponsiveContainer(
      maxWidth: 800,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner si es de acuerdo
              if (_esDeAcuerdo) _buildBannerAcuerdo(),
              if (_esDeAcuerdo) const SizedBox(height: 16),

              // Banner informativo
              _buildBannerInfo(),
              const SizedBox(height: 24),

              // Nombre
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'ej: Pago arbitro del sabado',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 16),

              // Tipo (no editable si es de acuerdo)
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
                onChanged: (_isSubmitting || _esDeAcuerdo) ? null : (v) {
                  if (v != null) {
                    setState(() => _tipo = v);
                    _cargarCategorias();
                  }
                },
              ),
              const SizedBox(height: 16),

              // Monto (no editable si es de acuerdo)
              TextFormField(
                controller: _montoController,
                decoration: const InputDecoration(
                  labelText: 'Monto *',
                  hintText: 'ej: 50000',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
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
                enabled: !_isSubmitting && !_esDeAcuerdo,
              ),
              const SizedBox(height: 16),

              // Fecha
              ListTile(
                title: const Text('Fecha programada *'),
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
                  }
                },
              ),
              const SizedBox(height: 16),

              // Categoria
              if (_categorias.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<Map<String, dynamic>>(
                      initialValue: _codigoCategoria != null
                          ? TextEditingValue(
                              text: _categorias
                                  .where((c) => c['codigo'] == _codigoCategoria)
                                  .map((c) => c['nombre'].toString())
                                  .firstOrNull ?? '',
                            )
                          : TextEditingValue.empty,
                      displayStringForOption: (cat) => cat['nombre'].toString(),
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _categorias;
                        final query = textEditingValue.text.toLowerCase();
                        return _categorias.where((cat) {
                          final nombre = cat['nombre'].toString().toLowerCase();
                          final codigo = cat['codigo'].toString().toLowerCase();
                          return nombre.contains(query) || codigo.contains(query);
                        });
                      },
                      onSelected: (cat) {
                        setState(() => _codigoCategoria = cat['codigo'].toString());
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Categoria (opcional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category),
                            hintText: 'Escribi para buscar...',
                          ),
                          enabled: !_isSubmitting,
                          onChanged: (text) {
                            final match = _categorias.where(
                              (c) => c['nombre'].toString().toLowerCase() == text.toLowerCase(),
                            );
                            if (match.isEmpty) _codigoCategoria = null;
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
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final cat = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                        CategoryIconHelper.fromName(cat['icono'] as String?),
                                        size: 20),
                                    title: Text(cat['nombre'].toString()),
                                    subtitle: Text(
                                      cat['codigo'].toString(),
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                )
              else
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    'Sin categorias disponibles',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              const SizedBox(height: 16),

              // Jugador/Staff del plantel
              if (_entidadesPlantel.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: _entidadPlantelId,
                  decoration: const InputDecoration(
                    labelText: 'Jugador / Staff (opcional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
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
                  onChanged: !_isSubmitting ? (v) => setState(() => _entidadPlantelId = v) : null,
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

              // Boton guardar
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
      ),
    );
  }

  /// Banner informativo
  Widget _buildBannerInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Editando compromiso puntual. Los campos marcados con * son obligatorios.',
              style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner para compromisos generados por un Acuerdo
  Widget _buildBannerAcuerdo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.handshake, color: Colors.purple.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este compromiso fue generado por un Acuerdo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El tipo y monto no se pueden modificar directamente. '
                  'Para cambiar esos valores, edita el Acuerdo origen.',
                  style: TextStyle(
                    color: Colors.purple.shade800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
