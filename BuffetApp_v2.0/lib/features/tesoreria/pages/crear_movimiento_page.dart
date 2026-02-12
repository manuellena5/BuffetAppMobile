import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../../shared/services/movimiento_service.dart';
import '../../shared/services/attachment_service.dart';
import '../../shared/services/error_handler.dart';
import '../../shared/services/plantel_service.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import '../../../data/dao/db.dart';
import '../../../domain/models.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/widgets/responsive_container.dart';
import '../services/cuenta_service.dart';

/// Pantalla para crear o editar un movimiento financiero (ingreso/egreso)
class CrearMovimientoPage extends StatefulWidget {
  final Map<String, dynamic>? movimientoExistente;
  final int? unidadGestionIdInicial;
  final String? eventoIdInicial;
  final int? cuentaIdInicial;
  
  const CrearMovimientoPage({
    super.key,
    this.movimientoExistente,
    this.unidadGestionIdInicial,
    this.eventoIdInicial,
    this.cuentaIdInicial,
  });

  @override
  State<CrearMovimientoPage> createState() => _CrearMovimientoPageState();
}

class _CrearMovimientoPageState extends State<CrearMovimientoPage> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  
  String _tipo = 'INGRESO';
  String? _codigoCategoria;
  int? _medioPagoId;
  int? _cuentaId;
  int? _entidadPlantelId;
  File? _attachmentFile;
  
  List<Map<String, dynamic>> _metodosPago = [];
  List<Map<String, dynamic>> _categorias = [];
  List<CuentaFondos> _cuentas = [];
  List<Map<String, dynamic>> _entidadesPlantel = [];
  
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    
    // FASE 22.2: Si se pasan parámetros iniciales, usarlos
    if (widget.cuentaIdInicial != null) {
      _cuentaId = widget.cuentaIdInicial;
    }
    
    // Si es edición, pre-cargar los datos
    if (widget.movimientoExistente != null) {
      final mov = widget.movimientoExistente!;
      _tipo = mov['tipo'] as String? ?? 'INGRESO';
      _codigoCategoria = mov['categoria'] as String?;
      _medioPagoId = mov['medio_pago_id'] as int?;
      _cuentaId = mov['cuenta_id'] as int?;
      _entidadPlantelId = mov['entidad_plantel_id'] as int?;
      _montoCtrl.text = (mov['monto'] as num?)?.toString() ?? '';
      _obsCtrl.text = mov['observacion'] as String? ?? '';
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarDatos());
  }

  Future<void> _cargarDatos() async {
    try {
      final db = await AppDatabase.instance();
      final settings = context.read<AppSettings>();
      final unidadId = settings.disciplinaActivaId;
      
      // Cargar métodos de pago
      final metodos = await db.query('metodos_pago', orderBy: 'id ASC');
      
      // Cargar categorías para el tipo inicial
      final cats = await db.query(
        'categoria_movimiento',
        where: "(tipo = ? OR tipo = 'AMBOS') AND activa = 1",
        whereArgs: [_tipo],
        orderBy: 'nombre ASC',
      );
      
      // Cargar cuentas activas de la unidad
      List<CuentaFondos> cuentas = [];
      if (unidadId != null) {
        final cuentaService = CuentaService();
        cuentas = await cuentaService.listarPorUnidad(unidadId, soloActivas: true);
      }
      
      // Cargar entidades del plantel (jugadores y staff)
      final entidades = await PlantelService.instance.listarEntidades(soloActivos: true);
      
      if (!mounted) return;
      
      setState(() {
        _metodosPago = metodos;
        _categorias = cats;
        _cuentas = cuentas;
        _entidadesPlantel = entidades;
        _medioPagoId = metodos.isNotEmpty ? metodos.first['id'] as int? : null;
        // FASE 22.2: Mantener cuentaId inicial si se pasó, sino usar primera cuenta
        if (_cuentaId == null || !cuentas.any((c) => c.id == _cuentaId)) {
          _cuentaId = cuentas.isNotEmpty ? cuentas.first.id : null;
        }
        _cargando = false;
      });
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        scope: 'tesoreria.cargar_formulario',
        error: e,
        stackTrace: st,
        context: mounted ? context : null,
      );
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }
  
  Future<void> _cargarCategorias() async {
    try {
      final db = await AppDatabase.instance();
      final cats = await db.query(
        'categoria_movimiento',
        where: "(tipo = ? OR tipo = 'AMBOS') AND activa = 1",
        whereArgs: [_tipo],
        orderBy: 'nombre ASC',
      );
      
      if (!mounted) return;
      
      setState(() {
        _categorias = cats;
        // Limpiar categoría si ya no es válida
        if (_codigoCategoria != null) {
          final esValida = _categorias.any((c) => c['codigo'] == _codigoCategoria);
          if (!esValida) _codigoCategoria = null;
        }
      });
    } catch (e) {
      // Error silencioso
      if (mounted) {
        setState(() => _categorias = []);
      }
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    
    final settings = context.read<AppSettings>();
    final unidadGestionId = settings.unidadGestionActivaId;
    final disciplinaId = settings.disciplinaActivaId ?? unidadGestionId;
    
    if (unidadGestionId == null || disciplinaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una Unidad de Gestión primero')),
      );
      return;
    }
    
    if (_codigoCategoria == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una categoría')),
      );
      return;
    }
    
    if (_cuentaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná una cuenta')),
      );
      return;
    }
    
    setState(() => _guardando = true);
    
    try {
      final svc = EventoMovimientoService();
      final attachmentSvc = AttachmentService();
      
      // Manejar archivo adjunto
      String? archivoLocalPath;
      String? archivoNombre;
      String? archivoTipo;
      int? archivoSize;
      
      if (_attachmentFile != null) {
        final savedAttachment = await attachmentSvc.saveAttachment(_attachmentFile!);
        archivoLocalPath = savedAttachment['archivo_local_path'];
        archivoNombre = savedAttachment['archivo_nombre'];
        archivoTipo = savedAttachment['archivo_tipo'];
        archivoSize = savedAttachment['archivo_size'];
      }
      
      final monto = double.parse(_montoCtrl.text.trim().replaceAll(',', '.'));
      
      if (widget.movimientoExistente != null) {
        // Actualizar movimiento existente
        final movId = widget.movimientoExistente!['id'] as int;
        await svc.actualizar(
          id: movId,
          disciplinaId: disciplinaId,
          cuentaId: _cuentaId!,
          eventoId: settings.eventoActivoId,
          tipo: _tipo,
          categoria: _codigoCategoria!,
          monto: monto,
          medioPagoId: _medioPagoId!,
          observacion: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
          archivoLocalPath: archivoLocalPath,
          archivoNombre: archivoNombre,
          archivoTipo: archivoTipo,
          archivoSize: archivoSize,
          entidadPlantelId: _entidadPlantelId,
        );
      } else {
        // Crear nuevo movimiento
        await svc.crear(
          disciplinaId: disciplinaId,
          cuentaId: _cuentaId!,
          eventoId: settings.eventoActivoId,
          tipo: _tipo,
          categoria: _codigoCategoria!,
          monto: monto,
          medioPagoId: _medioPagoId!,
          observacion: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
          archivoLocalPath: archivoLocalPath,
          archivoNombre: archivoNombre,
          archivoTipo: archivoTipo,
          archivoSize: archivoSize,
          entidadPlantelId: _entidadPlantelId,
        );
        
        // Lógica de comisión semiautomática (solo para movimientos nuevos)
        await _verificarComision(_cuentaId!, monto, disciplinaId, settings.eventoActivoId);
      }
      
      if (!mounted) return;
      
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Movimiento guardado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        scope: 'tesoreria.crear_movimiento',
        error: e,
        stackTrace: st,
        context: mounted ? context : null,
        userMessage: 'No se pudo guardar el movimiento',
        showDialog: true,
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _seleccionarArchivo() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Archivo PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            if (_attachmentFile != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    
    if (result == null) return;
    
    try {
      final attachmentSvc = AttachmentService();
      
      if (result == 'remove') {
        setState(() => _attachmentFile = null);
      } else if (result == 'gallery') {
        final file = await attachmentSvc.pickFromGallery();
        if (file != null) setState(() => _attachmentFile = file);
      } else if (result == 'camera') {
        final file = await attachmentSvc.pickFromCamera();
        if (file != null) setState(() => _attachmentFile = file);
      } else if (result == 'pdf') {
        final file = await attachmentSvc.pickPdf();
        if (file != null) setState(() => _attachmentFile = file);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final unidadGestionId = settings.unidadGestionActivaId;
    
    return TesoreriaScaffold(
      title: widget.movimientoExistente != null ? 'Editar Movimiento' : 'Nuevo Movimiento',
      currentRouteName: '/crear_movimiento',
      appBarColor: Colors.teal,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : unidadGestionId == null
              ? _buildSinUnidadGestion()
              : _buildFormulario(),
    );
  }
  
  Widget _buildSinUnidadGestion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, size: 64, color: Colors.orange.shade700),
            const SizedBox(height: 24),
            const Text(
              'Seleccioná una Unidad de Gestión',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Para cargar movimientos necesitás seleccionar primero una Unidad de Gestión desde Eventos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFormulario() {
    return ResponsiveContainer(
      maxWidth: 800,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          // Tipo de movimiento
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tipo de movimiento',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  RadioListTile<String>(
                    title: const Text('💰 Ingreso'),
                    value: 'INGRESO',
                    groupValue: _tipo,
                    activeColor: Colors.green,
                    onChanged: (v) {
                      setState(() => _tipo = v!);
                      _cargarCategorias();
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('💸 Egreso'),
                    value: 'EGRESO',
                    groupValue: _tipo,
                    activeColor: Colors.red,
                    onChanged: (v) {
                      setState(() => _tipo = v!);
                      _cargarCategorias();
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Categoría
          if (_categorias.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _codigoCategoria,
              decoration: const InputDecoration(
                labelText: 'Categoría *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _categorias.map((cat) {
                final codigo = cat['codigo'].toString();
                final nombre = cat['nombre'].toString();
                return DropdownMenuItem<String>(
                  value: codigo,
                  child: Text(nombre),
                );
              }).toList(),
              onChanged: (v) => setState(() => _codigoCategoria = v),
              validator: (v) => v == null ? 'Requerido' : null,
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Text(
                '⚠ No hay categorías configuradas para este tipo',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Monto
          TextFormField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monto *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.attach_money),
              prefixText: '\$ ',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              final monto = double.tryParse(v.trim().replaceAll(',', '.'));
              if (monto == null || monto <= 0) return 'Debe ser mayor a 0';
              return null;
            },
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
            items: _metodosPago.map((m) {
              return DropdownMenuItem<int>(
                value: m['id'] as int,
                child: Text(m['descripcion'].toString()),
              );
            }).toList(),
            onChanged: (v) => setState(() => _medioPagoId = v),
            validator: (v) => v == null ? 'Requerido' : null,
          ),
          
          const SizedBox(height: 16),
          
          // Cuenta
          if (_cuentas.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _cuentaId,
              decoration: const InputDecoration(
                labelText: 'Cuenta *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance_wallet),
                helperText: 'Cuenta donde se registra el movimiento',
              ),
              items: _cuentas.map((cuenta) {
                return DropdownMenuItem<int>(
                  value: cuenta.id,
                  child: Text('${cuenta.nombre} (${cuenta.tipo})'),
                );
              }).toList(),
              onChanged: (v) => setState(() => _cuentaId = v),
              validator: (v) => v == null ? 'Requerido' : null,
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Text(
                '⚠ No hay cuentas disponibles. Creá una cuenta primero.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Entidad del plantel (opcional)
          DropdownButtonFormField<int?>(
            value: _entidadPlantelId,
            decoration: const InputDecoration(
              labelText: 'Asociar a jugador/staff (opcional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
              helperText: 'Podés asociar este movimiento a una persona del plantel',
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Sin asociar'),
              ),
              ..._entidadesPlantel.map((entidad) {
                final id = entidad['id'] as int;
                final nombre = entidad['nombre'] as String;
                final rol = entidad['rol'] as String;
                return DropdownMenuItem<int?>(
                  value: id,
                  child: Text('$nombre ($rol)'),
                );
              }),
            ],
            onChanged: (v) => setState(() => _entidadPlantelId = v),
          ),
          
          const SizedBox(height: 16),
          
          // Observación
          TextFormField(
            controller: _obsCtrl,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 3,
          ),
          
          const SizedBox(height: 16),
          
          // Archivo adjunto
          OutlinedButton.icon(
            onPressed: _seleccionarArchivo,
            icon: Icon(_attachmentFile != null ? Icons.check_circle : Icons.attach_file),
            label: Text(_attachmentFile != null ? '📎 Archivo adjunto' : 'Adjuntar comprobante'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
              side: BorderSide(
                color: _attachmentFile != null ? Colors.green : Colors.grey,
              ),
            ),
          ),
          
          if (_attachmentFile != null) ...[
            const SizedBox(height: 12),
            // Mostrar nombre del archivo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    _attachmentFile!.path.toLowerCase().endsWith('.pdf')
                        ? Icons.picture_as_pdf
                        : Icons.image,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.basename(_attachmentFile!.path),
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Mostrar preview solo si es imagen (no PDF)
            if (!_attachmentFile!.path.toLowerCase().endsWith('.pdf'))
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _attachmentFile!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
          ],
          
          const SizedBox(height: 24),
          
          // Botón guardar
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.all(16),
            ),
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(
              _guardando 
                  ? 'Guardando...' 
                  : widget.movimientoExistente != null 
                      ? 'Actualizar Movimiento' 
                      : 'Guardar Movimiento',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Verifica si la cuenta tiene comisión y ofrece registrarla
  Future<void> _verificarComision(int cuentaId, double monto, int disciplinaId, String? eventoId) async {
    try {
      final cuentaService = CuentaService();
      final comision = await cuentaService.calcularComision(cuentaId, monto);
      
      if (comision == null || comision <= 0) return;
      
      if (!mounted) return;
      
      // Mostrar dialog de confirmación con campos editables
      final resultado = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (context) => _DialogComision(
          comision: comision,
          cuenta: _cuentas.firstWhere((c) => c.id == cuentaId),
          montoTransferido: monto,
          observacionMovimiento: _obsCtrl.text.trim(),
        ),
      );
      
      if (resultado == null) return; // Usuario canceló
      
      // Obtener valores editados del diálogo
      final montoComision = resultado['monto'] as double? ?? comision;
      final observacionExtra = resultado['observacion'] as String?;
      
      // Registrar comisión como movimiento separado con valores editados
      final svc = EventoMovimientoService();
      await svc.crear(
        disciplinaId: disciplinaId,
        cuentaId: cuentaId,
        eventoId: eventoId,
        tipo: 'EGRESO',
        categoria: 'COM_BANC',
        monto: montoComision,
        medioPagoId: _medioPagoId!,
        observacion: observacionExtra ?? 'Comisión bancaria',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Comisión de \$${comision.toStringAsFixed(2)} registrada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'crear_movimiento_page.verificar_comision',
        error: e,
        stackTrace: st,
      );
      // Error silencioso - la comisión es opcional
    }
  }
}

/// Dialog para confirmar y editar comisión bancaria
class _DialogComision extends StatefulWidget {
  final double comision;
  final CuentaFondos cuenta;
  final double montoTransferido;
  final String observacionMovimiento;

  const _DialogComision({
    required this.comision,
    required this.cuenta,
    required this.montoTransferido,
    required this.observacionMovimiento,
  });

  @override
  State<_DialogComision> createState() => _DialogComisionState();
}

class _DialogComisionState extends State<_DialogComision> {
  late TextEditingController _montoController;
  late TextEditingController _observacionController;
  
  @override
  void initState() {
    super.initState();
    _montoController = TextEditingController(text: widget.comision.toStringAsFixed(2));
    
    // Precargar observación con prefijo
    final observacionPrefijo = widget.observacionMovimiento.isNotEmpty
        ? 'Comisión bancaria: ${widget.observacionMovimiento}'
        : 'Comisión bancaria';
    _observacionController = TextEditingController(text: observacionPrefijo);
  }

  @override
  void dispose() {
    _montoController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final porcentaje = widget.cuenta.comisionPorcentaje ?? 0.0;
    
    return AlertDialog(
      icon: const Icon(Icons.account_balance, size: 48, color: Colors.orange),
      title: const Text('Comisión Bancaria'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La cuenta "${widget.cuenta.nombre}" cobra comisión del $porcentaje%.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            // Info de cálculo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Monto transferido:'),
                      Text(
                        '\$ ${widget.montoTransferido.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Porcentaje comisión:'),
                      Text(
                        '$porcentaje%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Comisión calculada:'),
                      Text(
                        '\$ ${widget.comision.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            const Text(
              'Monto de comisión (editable):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _montoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '\$ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 16),
            const Text(
              'Observación (opcional):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _observacionController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Detalles adicionales...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final montoEditado = double.tryParse(_montoController.text) ?? widget.comision;
            final observacion = _observacionController.text.trim();
            
            Navigator.pop(context, {
              'monto': montoEditado,
              'observacion': observacion.isEmpty ? null : observacion,
            });
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
