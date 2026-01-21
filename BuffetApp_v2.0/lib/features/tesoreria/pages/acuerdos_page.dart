import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/responsive_container.dart';

import '../../../features/shared/services/acuerdos_service.dart';
import '../../../features/shared/format.dart';
import '../../../data/dao/db.dart';
import 'crear_acuerdo_page.dart';
import 'detalle_acuerdo_page.dart';
import 'nuevo_acuerdo_grupal_page.dart';

/// FASE 18.5: Página principal de gestión de acuerdos financieros
/// 
/// Muestra lista de acuerdos con filtros y acciones.
/// Los acuerdos son reglas/contratos que generan compromisos automáticamente.
class AcuerdosPage extends StatefulWidget {
  const AcuerdosPage({super.key});

  @override
  State<AcuerdosPage> createState() => _AcuerdosPageState();
}

class _AcuerdosPageState extends State<AcuerdosPage> {
  List<Map<String, dynamic>> _acuerdos = [];
  List<Map<String, dynamic>> _unidadesGestion = [];
  List<Map<String, dynamic>> _entidadesPlantel = [];
  bool _isLoading = true;
  
  // Filtros
  int? _unidadGestionId;
  int? _entidadPlantelId;
  String? _tipoFiltro; // 'INGRESO', 'EGRESO', null = todos
  bool? _activoFiltro; // true = activos, false = finalizados, null = todos
  String? _origenFiltro; // 'MANUAL', 'GRUPAL', null = todos
  
  // Vista
  bool _vistaTabla = true; // false = tarjetas, true = tabla

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    
    try {
      final db = await AppDatabase.instance();
      
      // Cargar catálogos
      final unidades = await db.query('unidades_gestion', where: 'activo = 1', orderBy: 'nombre');
      final entidades = await db.query('entidades_plantel', where: 'estado_activo = 1', orderBy: 'nombre');
      
      // Cargar acuerdos con filtro de origen
      List<Map<String, dynamic>> acuerdosRaw;
      
      if (_origenFiltro != null) {
        final soloGrupal = _origenFiltro == 'GRUPAL';
        acuerdosRaw = await AcuerdosService.listarAcuerdos(
          unidadGestionId: _unidadGestionId,
          entidadPlantelId: _entidadPlantelId,
          tipo: _tipoFiltro,
          soloActivos: _activoFiltro,
        );
        
        // Filtrar por origen
        acuerdosRaw = acuerdosRaw.where((a) {
          final origenGrupal = (a['origen_grupal'] as int?) == 1;
          return origenGrupal == soloGrupal;
        }).toList();
      } else {
        acuerdosRaw = await AcuerdosService.listarAcuerdos(
          unidadGestionId: _unidadGestionId,
          entidadPlantelId: _entidadPlantelId,
          tipo: _tipoFiltro,
          soloActivos: _activoFiltro,
        );
      }
      
      // Convertir a Maps mutables para poder enriquecerlos
      final acuerdos = acuerdosRaw.map((a) => Map<String, dynamic>.from(a)).toList();
      
      // Enriquecer acuerdos con nombres de catálogos
      for (final acuerdo in acuerdos) {
        final unidadId = acuerdo['unidad_gestion_id'] as int?;
        final entidadId = acuerdo['entidad_plantel_id'] as int?;
        
        if (unidadId != null) {
          final unidad = unidades.firstWhere(
            (u) => u['id'] == unidadId,
            orElse: () => {'nombre': 'Desconocida'},
          );
          acuerdo['_unidad_nombre'] = unidad['nombre'];
        }
        
        if (entidadId != null) {
          final entidad = entidades.firstWhere(
            (e) => e['id'] == entidadId,
            orElse: () => {'nombre': 'Desconocido'},
          );
          acuerdo['_entidad_nombre'] = entidad['nombre'];
        }
        
        // Cargar estadísticas
        final stats = await AcuerdosService.obtenerEstadisticasAcuerdo(acuerdo['id'] as int);
        acuerdo['_stats'] = stats;
      }
      
      setState(() {
        _acuerdos = acuerdos;
        _unidadesGestion = unidades;
        _entidadesPlantel = entidades;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_page.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
      );
      
      setState(() {
        _acuerdos = [];
        _unidadesGestion = [];
        _entidadesPlantel = [];
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar acuerdos. Por favor, intente nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _aplicarFiltros() {
    _cargarDatos();
  }

  void _limpiarFiltros() {
    setState(() {
      _unidadGestionId = null;
      _entidadPlantelId = null;
      _tipoFiltro = null;
      _activoFiltro = null;
      _origenFiltro = null;
    });
    _cargarDatos();
  }

  Future<void> _finalizarAcuerdo(int id, String nombre) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Acuerdo'),
        content: Text('¿Finalizar el acuerdo "$nombre"?\n\nEsto marcará el acuerdo como inactivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    try {
      await AcuerdosService.finalizarAcuerdo(id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acuerdo finalizado correctamente')),
        );
      }
      
      _cargarDatos();
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_page.finalizar_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al finalizar: ${e.toString()}'),
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
        title: const Text('Acuerdos'),
        actions: [
          IconButton(
            icon: Icon(_vistaTabla ? Icons.view_list : Icons.table_chart),
            tooltip: _vistaTabla ? 'Vista tarjetas' : 'Vista tabla',
            onPressed: () => setState(() => _vistaTabla = !_vistaTabla),
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt),
            tooltip: 'Filtros',
            onPressed: _mostrarFiltros,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: _vistaTabla ? 1400 : 1000,
              child: Column(
                children: [
                  if (_tieneFiltrosActivos()) _buildFiltrosActivos(),
                  Expanded(
                    child: _acuerdos.isEmpty
                        ? _buildEmptyState()
                        : _vistaTabla
                            ? _buildVistaTabla()
                            : _buildVistaTarjetas(),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarMenuCreacion,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Acuerdo'),
      ),
    );
  }

  Future<void> _mostrarMenuCreacion() async {
    final opcion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear Acuerdo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Acuerdo Individual'),
              subtitle: const Text('Para un solo jugador/DT'),
              onTap: () => Navigator.pop(ctx, 'INDIVIDUAL'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Acuerdo Grupal'),
              subtitle: const Text('Para múltiples jugadores'),
              onTap: () => Navigator.pop(ctx, 'GRUPAL'),
            ),
          ],
        ),
      ),
    );
    
    if (opcion == 'INDIVIDUAL') {
      _crearNuevoAcuerdo();
    } else if (opcion == 'GRUPAL') {
      _crearAcuerdoGrupal();
    }
  }

  Future<void> _crearAcuerdoGrupal() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => NuevoAcuerdoGrupalPage(unidadGestionId: _unidadGestionId ?? 1),
      ),
    );
    
    if (resultado != null) {
      _cargarDatos();
    }
  }

  bool _tieneFiltrosActivos() {
    return _unidadGestionId != null ||
        _entidadPlantelId != null ||
        _tipoFiltro != null ||
        _activoFiltro != null ||
        _origenFiltro != null;
  }

  Widget _buildFiltrosActivos() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                if (_unidadGestionId != null)
                  Chip(
                    label: Text(_unidadesGestion
                        .firstWhere((u) => u['id'] == _unidadGestionId)['nombre']
                        .toString()),
                    onDeleted: () {
                      setState(() => _unidadGestionId = null);
                      _cargarDatos();
                    },
                  ),
                if (_entidadPlantelId != null)
                  Chip(
                    label: Text(_entidadesPlantel
                        .firstWhere((e) => e['id'] == _entidadPlantelId)['nombre']
                        .toString()),
                    onDeleted: () {
                      setState(() => _entidadPlantelId = null);
                      _cargarDatos();
                    },
                  ),
                if (_tipoFiltro != null)
                  Chip(
                    label: Text(_tipoFiltro!),
                    onDeleted: () {
                      setState(() => _tipoFiltro = null);
                      _cargarDatos();
                    },
                  ),
                if (_activoFiltro != null)
                  Chip(
                    label: Text(_activoFiltro! ? 'Activos' : 'Finalizados'),
                    onDeleted: () {
                      setState(() => _activoFiltro = null);
                      _cargarDatos();
                    },
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _limpiarFiltros,
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            _tieneFiltrosActivos()
                ? 'No hay acuerdos con los filtros aplicados'
                : 'No hay acuerdos registrados',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!_tieneFiltrosActivos())
            Text(
              'Crea tu primer acuerdo para comenzar',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildVistaTarjetas() {
    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _acuerdos.length,
        itemBuilder: (context, index) {
          try {
            final acuerdo = _acuerdos[index];
            return _buildTarjetaAcuerdo(acuerdo);
          } catch (e, stack) {
            AppDatabase.logLocalError(
              scope: 'acuerdos_page.render_tarjeta',
              error: e.toString(),
              stackTrace: stack,
              payload: {'index': index},
            );
            return Card(
              child: ListTile(
                leading: const Icon(Icons.warning, color: Colors.orange),
                title: const Text('Error al mostrar acuerdo'),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildTarjetaAcuerdo(Map<String, dynamic> acuerdo) {
    final id = acuerdo['id'] as int;
    final nombre = acuerdo['nombre']?.toString() ?? 'Sin nombre';
    final tipo = acuerdo['tipo']?.toString() ?? 'EGRESO';
    final modalidad = acuerdo['modalidad']?.toString() ?? 'RECURRENTE';
    final activo = (acuerdo['activo'] as int?) == 1;
    final origenGrupal = (acuerdo['origen_grupal'] as int?) == 1; // FASE 19
    final unidadNombre = acuerdo['_unidad_nombre']?.toString() ?? 'Desconocida';
    final entidadNombre = acuerdo['_entidad_nombre']?.toString();
    final stats = acuerdo['_stats'] as Map<String, dynamic>?;
    
    final montoDisplay = modalidad == 'MONTO_TOTAL_CUOTAS'
        ? (acuerdo['monto_total'] as num?)?.toDouble() ?? 0.0
        : (acuerdo['monto_periodico'] as num?)?.toDouble() ?? 0.0;
    
    final cuotasConfirmadas = stats?['cuotas_confirmadas'] as int? ?? 0;
    final cuotasEsperadas = stats?['cuotas_esperadas'] as int? ?? 0;
    final cuotasTotal = cuotasConfirmadas + cuotasEsperadas;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final resultado = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (ctx) => DetalleAcuerdoPage(acuerdoId: id),
            ),
          );
          if (resultado == true) {
            _cargarDatos();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    tipo == 'INGRESO' ? Icons.arrow_downward : Icons.arrow_upward,
                    color: tipo == 'INGRESO' ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nombre,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (origenGrupal) // FASE 19: Badge de origen grupal
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: const Icon(Icons.group, size: 16, color: Colors.white),
                        label: const Text('Grupal', style: TextStyle(fontSize: 11, color: Colors.white)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  if (!activo)
                    Chip(
                      label: const Text('Finalizado', style: TextStyle(fontSize: 11)),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.grey.shade300,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Unidad de gestión y entidad
              Row(
                children: [
                  Icon(Icons.business, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    unidadNombre,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (entidadNombre != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entidadNombre,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              
              // Monto y modalidad
              Row(
                children: [
                  Text(
                    Format.money(montoDisplay),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: tipo == 'INGRESO' ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      _modalidadLabel(modalidad),
                      style: const TextStyle(fontSize: 11),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              
              // Progreso de cuotas
              if (cuotasTotal > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: cuotasTotal > 0 ? cuotasConfirmadas / cuotasTotal : 0,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    tipo == 'INGRESO' ? Colors.green : Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$cuotasConfirmadas de $cuotasTotal cuotas confirmadas',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (activo)
                    TextButton.icon(
                      onPressed: () => _finalizarAcuerdo(id, nombre),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Finalizar'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final resultado = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => DetalleAcuerdoPage(acuerdoId: id),
                        ),
                      );
                      if (resultado == true) {
                        _cargarDatos();
                      }
                    },
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Ver Detalle'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVistaTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Entidad')),
            DataColumn(label: Text('Monto')),
            DataColumn(label: Text('Modalidad')),
            DataColumn(label: Text('Progreso')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: _acuerdos.map((acuerdo) {
            try {
              return _buildFilaTabla(acuerdo);
            } catch (e, stack) {
              AppDatabase.logLocalError(
                scope: 'acuerdos_page.render_fila_tabla',
                error: e.toString(),
                stackTrace: stack,
                payload: {'acuerdo_id': acuerdo['id']},
              );
              return DataRow(cells: [
                DataCell(const Text('Error')),
                DataCell(Container()),
                DataCell(Container()),
                DataCell(Container()),
                DataCell(Container()),
                DataCell(Container()),
                DataCell(Container()),
                DataCell(Container()),
              ]);
            }
          }).toList(),
        ),
      ),
    );
  }

  DataRow _buildFilaTabla(Map<String, dynamic> acuerdo) {
    final id = acuerdo['id'] as int;
    final nombre = acuerdo['nombre']?.toString() ?? 'Sin nombre';
    final tipo = acuerdo['tipo']?.toString() ?? 'EGRESO';
    final modalidad = acuerdo['modalidad']?.toString() ?? 'RECURRENTE';
    final activo = (acuerdo['activo'] as int?) == 1;
    final entidadNombre = acuerdo['_entidad_nombre']?.toString() ?? '-';
    final stats = acuerdo['_stats'] as Map<String, dynamic>?;
    
    final montoDisplay = modalidad == 'MONTO_TOTAL_CUOTAS'
        ? (acuerdo['monto_total'] as num?)?.toDouble() ?? 0.0
        : (acuerdo['monto_periodico'] as num?)?.toDouble() ?? 0.0;
    
    final cuotasConfirmadas = stats?['cuotas_confirmadas'] as int? ?? 0;
    final cuotasEsperadas = stats?['cuotas_esperadas'] as int? ?? 0;
    final cuotasTotal = cuotasConfirmadas + cuotasEsperadas;
    
    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(nombre, overflow: TextOverflow.ellipsis),
          ),
        ),
        DataCell(
          Icon(
            tipo == 'INGRESO' ? Icons.arrow_downward : Icons.arrow_upward,
            color: tipo == 'INGRESO' ? Colors.green : Colors.red,
            size: 18,
          ),
        ),
        DataCell(Text(entidadNombre)),
        DataCell(Text(Format.money(montoDisplay))),
        DataCell(Text(_modalidadLabel(modalidad))),
        DataCell(Text('$cuotasConfirmadas / $cuotasTotal')),
        DataCell(
          Chip(
            label: Text(activo ? 'Activo' : 'Finalizado', style: const TextStyle(fontSize: 11)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
            backgroundColor: activo ? Colors.green.shade100 : Colors.grey.shade300,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                tooltip: 'Ver detalle',
                onPressed: () async {
                  final resultado = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => DetalleAcuerdoPage(acuerdoId: id),
                    ),
                  );
                  if (resultado == true) {
                    _cargarDatos();
                  }
                },
              ),
              if (activo)
                IconButton(
                  icon: const Icon(Icons.stop, size: 18),
                  tooltip: 'Finalizar',
                  onPressed: () => _finalizarAcuerdo(id, nombre),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _mostrarFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: scrollController,
              children: [
                Text(
                  'Filtros',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(),
                
                // Unidad de gestión
                DropdownButtonFormField<int?>(
                  value: _unidadGestionId,
                  decoration: const InputDecoration(labelText: 'Unidad de Gestión'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ..._unidadesGestion.map((u) => DropdownMenuItem(
                          value: u['id'] as int,
                          child: Text(u['nombre'].toString()),
                        )),
                  ],
                  onChanged: (val) => setModalState(() => _unidadGestionId = val),
                ),
                const SizedBox(height: 16),
                
                // Entidad del plantel
                DropdownButtonFormField<int?>(
                  value: _entidadPlantelId,
                  decoration: const InputDecoration(labelText: 'Jugador / Técnico'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ..._entidadesPlantel.map((e) => DropdownMenuItem(
                          value: e['id'] as int,
                          child: Text(e['nombre'].toString()),
                        )),
                  ],
                  onChanged: (val) => setModalState(() => _entidadPlantelId = val),
                ),
                const SizedBox(height: 16),
                
                // Tipo
                DropdownButtonFormField<String?>(
                  value: _tipoFiltro,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(value: 'INGRESO', child: Text('Ingresos')),
                    DropdownMenuItem(value: 'EGRESO', child: Text('Egresos')),
                  ],
                  onChanged: (val) => setModalState(() => _tipoFiltro = val),
                ),
                const SizedBox(height: 16),
                
                // Estado
                DropdownButtonFormField<bool?>(
                  value: _activoFiltro,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(value: true, child: Text('Activos')),
                    DropdownMenuItem(value: false, child: Text('Finalizados')),
                  ],
                  onChanged: (val) => setModalState(() => _activoFiltro = val),
                ),
                const SizedBox(height: 16),
                
                // Origen (NUEVO - FASE 19)
                DropdownButtonFormField<String?>(
                  value: _origenFiltro,
                  decoration: const InputDecoration(labelText: 'Origen'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(value: 'MANUAL', child: Text('Individual')),
                    DropdownMenuItem(value: 'GRUPAL', child: Text('Grupal')),
                  ],
                  onChanged: (val) => setModalState(() => _origenFiltro = val),
                ),
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          _unidadGestionId = null;
                          _entidadPlantelId = null;
                          _tipoFiltro = null;
                          _activoFiltro = null;
                          _origenFiltro = null;
                        });
                      },
                      child: const Text('Limpiar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {}); // Actualizar estado principal
                        _aplicarFiltros();
                      },
                      child: const Text('Aplicar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _crearNuevoAcuerdo() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => const CrearAcuerdoPage(),
      ),
    );
    
    if (resultado == true) {
      _cargarDatos();
    }
  }

  String _modalidadLabel(String modalidad) {
    switch (modalidad) {
      case 'MONTO_TOTAL_CUOTAS':
        return 'Cuotas';
      case 'RECURRENTE':
        return 'Recurrente';
      default:
        return modalidad;
    }
  }
}
