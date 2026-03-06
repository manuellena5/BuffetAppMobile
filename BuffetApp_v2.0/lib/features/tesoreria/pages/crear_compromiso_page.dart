import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/services/error_handler.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../../features/shared/state/app_settings.dart';
import '../../../features/shared/format.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import '../../shared/utils/category_icon_helper.dart';
import '../../shared/widgets/responsive_container.dart';
import '../widgets/ayuda_tesoreria_dialog.dart';

/// Pagina para crear un nuevo compromiso financiero PUNTUAL.
///
/// Un compromiso es una expectativa futura concreta: un pago o cobro
/// que se espera en una fecha determinada, con un monto especifico.
///
/// Para pagos recurrentes o en cuotas, usar ACUERDOS (crear_acuerdo_page).
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
  final _observacionesController = TextEditingController();

  // Form values
  String _tipo = 'INGRESO';
  String? _codigoCategoria;
  DateTime _fechaProgramada = DateTime.now();
  int _unidadGestionId = 1;
  int? _entidadPlantelId;

  bool _isSubmitting = false;
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
    _montoController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;

    try {
      final db = await AppDatabase.instance();
      final settings = Provider.of<AppSettings>(context, listen: false);

      final unidades = await db.query('unidades_gestion',
          where: 'activo = 1', orderBy: 'nombre');
      final entidades =
          await _plantelService.listarEntidades(soloActivos: true);

      await _cargarCategorias();

      final unidadActivaId = settings.unidadGestionActivaId;

      if (mounted) {
        setState(() {
          _unidades = unidades;
          _entidadesPlantel = entidades;
          if (unidadActivaId != null) {
            _unidadGestionId = unidadActivaId;
          } else if (_unidades.isNotEmpty) {
            _unidadGestionId = _unidades.first['id'] as int;
          }
        });
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'crear_compromiso_page.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
      );
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

  Future<void> _cargarCategorias() async {
    try {
      final cats =
          await CategoriaMovimientoService.obtenerCategoriasPorTipo(tipo: _tipo);
      if (mounted) {
        setState(() {
          _categorias = cats;
          if (_codigoCategoria != null) {
            final esValida =
                _categorias.any((cat) => cat['codigo'] == _codigoCategoria);
            if (!esValida) _codigoCategoria = null;
          }
        });
      }
    } catch (e) {
      // Categorias opcionales
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
            const Text('Confirmar Compromiso'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '�Crear el siguiente compromiso?',
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
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                      'Tipo', _tipo == 'INGRESO' ? 'Ingreso' : 'Egreso'),
                  _buildInfoRow('Monto', Format.money(monto)),
                  _buildInfoRow('Fecha',
                      DateFormat('dd/MM/yyyy').format(_fechaProgramada)),
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isSubmitting = true);

    try {
      // Siempre PAGO_UNICO + UNICA_VEZ para compromisos manuales
      final compromisoId = await _compromisosService.crearCompromiso(
        unidadGestionId: _unidadGestionId,
        nombre: _nombreController.text.trim(),
        tipo: _tipo,
        modalidad: 'PAGO_UNICO',
        monto: monto,
        frecuencia: 'UNICA_VEZ',
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaProgramada),
        categoria: _codigoCategoria ?? '',
        observaciones: _observacionesController.text.trim().isNotEmpty
            ? _observacionesController.text.trim()
            : null,
        entidadPlantelId: _entidadPlantelId,
      );

      // Generar la unica cuota
      final cuotas = await _compromisosService.generarCuotas(compromisoId);
      await _compromisosService.guardarCuotas(compromisoId, cuotas);

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 32),
                const SizedBox(width: 12),
                const Text('Compromiso Creado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('El compromiso se creo correctamente'),
                const SizedBox(height: 12),
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
                      Text('ID: $compromisoId',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Monto: ${Format.money(monto)}'),
                      Text(
                          'Fecha: ${DateFormat('dd/MM/yyyy').format(_fechaProgramada)}'),
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
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        scope: 'tesoreria.crear_compromiso',
        error: e,
        stackTrace: st,
        context: mounted ? context : null,
        userMessage:
            'No se pudo crear el compromiso. Verifica los datos e intenta nuevamente.',
        payload: {
          'tipo': _tipo,
          'unidad_gestion_id': _unidadGestionId,
        },
        showDialog: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Compromiso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Que es un compromiso?',
            onPressed: () => AyudaTesoreriaDialog.show(context),
          ),
        ],
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
                // Banner informativo
                _buildBannerInfo(),
                const SizedBox(height: 24),

                // Nombre
                TextFormField(
                  controller: _nombreController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del compromiso *',
                    border: OutlineInputBorder(),
                    hintText: 'Ej: Pago arbitro partido del sabado',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Ingresa un nombre'
                      : null,
                ),
                const SizedBox(height: 16),

                // Tipo
                const Text('Tipo *',
                    style: TextStyle(fontWeight: FontWeight.w500)),
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

                // Monto
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto *',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Ingresa un monto';
                    final monto = double.tryParse(val);
                    if (monto == null || monto <= 0) return 'Monto invalido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Fecha programada
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha programada *'),
                  subtitle: Text(
                    DateFormat('dd/MM/yyyy').format(_fechaProgramada),
                    style: const TextStyle(fontSize: 16),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final fecha = await showDatePicker(
                      context: context,
                      initialDate: _fechaProgramada,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (fecha != null) {
                      setState(() => _fechaProgramada = fecha);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Unidad de gestion
                if (_unidades.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: _unidadGestionId,
                    decoration: const InputDecoration(
                      labelText: 'Unidad de Gestion *',
                      border: OutlineInputBorder(),
                    ),
                    items: _unidades.map((u) {
                      return DropdownMenuItem<int>(
                        value: u['id'] as int,
                        child: Text(u['nombre'] as String),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _unidadGestionId = val!),
                  ),
                const SizedBox(height: 16),

                // Categoria (Autocomplete)
                if (_categorias.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Autocomplete<Map<String, dynamic>>(
                        initialValue: _codigoCategoria != null
                            ? TextEditingValue(
                                text: _categorias
                                        .where((c) =>
                                            c['codigo'] == _codigoCategoria)
                                        .map((c) => c['nombre'].toString())
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
                          setState(() =>
                              _codigoCategoria = cat['codigo'].toString());
                        },
                        fieldViewBuilder: (context, controller, focusNode,
                            onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Categoria (opcional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.category),
                              hintText: 'Escribi para buscar...',
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
                                _codigoCategoria = null;
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
                                              cat['icono']
                                                  as String?),
                                          size: 20),
                                      title: Text(
                                          cat['nombre'].toString()),
                                      subtitle: Text(
                                        cat['codigo'].toString(),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                Colors.grey.shade600),
                                      ),
                                      onTap: () =>
                                          onSelected(cat),
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
                      labelText: 'Categoria (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      'Sin categorias disponibles',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                const SizedBox(height: 16),

                // Jugador/Staff
                if (_entidadesPlantel.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: _entidadPlantelId,
                    decoration: const InputDecoration(
                      labelText: 'Jugador / Staff (opcional)',
                      border: OutlineInputBorder(),
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
                    onChanged: (v) =>
                        setState(() => _entidadPlantelId = v),
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
                const SizedBox(height: 32),

                // Sugerencia de acuerdo
                _buildSugerenciaAcuerdo(),
                const SizedBox(height: 24),

                // Boton guardar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _guardar,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSubmitting
                          ? 'Guardando...'
                          : 'Crear Compromiso',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Banner informativo que explica que es un compromiso
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Un compromiso es un pago o cobro puntual esperado.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ejemplos: pago de arbitro, inscripcion de torneo, compra de insumos.',
                  style: TextStyle(
                    color: Colors.blue.shade800,
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

  /// Sugerencia para usar Acuerdos si el compromiso es recurrente
  Widget _buildSugerenciaAcuerdo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline,
              color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se repite o tiene cuotas?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Si este pago se repite cada mes o queres dividirlo en cuotas, usa "Nuevo Acuerdo" para que el sistema genere los compromisos automaticamente.',
                  style: TextStyle(
                    color: Colors.amber.shade900,
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
