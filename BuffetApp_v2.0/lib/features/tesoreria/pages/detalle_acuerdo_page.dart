import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/responsive_container.dart';

import '../../../features/shared/services/acuerdos_service.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/format.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import 'editar_acuerdo_page.dart';
import 'detalle_compromiso_page.dart';

/// FASE 18.7: Página de detalle de un acuerdo
/// 
/// Muestra:
/// - Información completa del acuerdo
/// - Estadísticas de progreso
/// - Lista de compromisos generados
/// - Acciones: editar, finalizar, eliminar
class DetalleAcuerdoPage extends StatefulWidget {
  final int acuerdoId;

  const DetalleAcuerdoPage({super.key, required this.acuerdoId});

  @override
  State<DetalleAcuerdoPage> createState() => _DetalleAcuerdoPageState();
}

class _DetalleAcuerdoPageState extends State<DetalleAcuerdoPage> {
  final _compromisosService = CompromisosService.instance;
  
  Map<String, dynamic>? _acuerdo;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _compromisos = [];
  bool _isLoading = true;
  String? _categoriaNombre;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    
    try {
      final acuerdoRaw = await AcuerdosService.obtenerAcuerdo(widget.acuerdoId);
      
      if (acuerdoRaw == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Acuerdo no encontrado')),
          );
          Navigator.pop(context);
        }
        return;
      }
      
      // Convertir a Map mutable para poder enriquecerlo
      final acuerdo = Map<String, dynamic>.from(acuerdoRaw);
      
      final stats = await AcuerdosService.obtenerEstadisticasAcuerdo(widget.acuerdoId);
      final compromisosRaw = await _compromisosService.listarCompromisosPorAcuerdo(widget.acuerdoId);
      
      // Convertir compromisos a Maps mutables
      final compromisos = compromisosRaw.map((c) => Map<String, dynamic>.from(c)).toList();
      
      // Enriquecer acuerdo con nombres
      final db = await AppDatabase.instance();
      final unidadId = acuerdo['unidad_gestion_id'] as int?;
      final entidadId = acuerdo['entidad_plantel_id'] as int?;
      
      if (unidadId != null) {
        final unidad = await db.query('unidades_gestion', where: 'id = ?', whereArgs: [unidadId]);
        if (unidad.isNotEmpty) {
          acuerdo['_unidad_nombre'] = unidad.first['nombre'];
        }
      }
      
      if (entidadId != null) {
        final entidad = await db.query('entidades_plantel', where: 'id = ?', whereArgs: [entidadId]);
        if (entidad.isNotEmpty) {
          acuerdo['_entidad_nombre'] = entidad.first['nombre'];
        }
      }
      
      // Enriquecer compromisos con estadísticas de cuotas
      for (final compromiso in compromisos) {
        final cuotasStats = await db.rawQuery('''
          SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN estado = 'ESPERADO' THEN 1 ELSE 0 END) as esperadas,
            SUM(CASE WHEN estado = 'CONFIRMADO' THEN 1 ELSE 0 END) as confirmadas
          FROM compromiso_cuotas
          WHERE compromiso_id = ?
        ''', [compromiso['id']]);
        
        if (cuotasStats.isNotEmpty) {
          compromiso['_cuotas_stats'] = cuotasStats.first;
        }
      }
      
      // Cargar nombre de categoría
      String? catNombre;
      final codigoCat = acuerdo['categoria']?.toString();
      if (codigoCat != null && codigoCat.isNotEmpty && codigoCat != '-') {
        catNombre = await CategoriaMovimientoService.obtenerNombrePorCodigo(codigoCat);
      }
      
      setState(() {
        _acuerdo = acuerdo;
        _stats = stats;
        _compromisos = compromisos;
        _categoriaNombre = catNombre;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'detalle_acuerdo_page.cargar_datos',
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

  Future<void> _finalizarAcuerdo() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Acuerdo'),
        content: Text(
          '¿Finalizar el acuerdo "${_acuerdo!['nombre']}"?\n\n'
          'Esto marcará el acuerdo como inactivo y no se generarán más compromisos.',
        ),
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
      await AcuerdosService.finalizarAcuerdo(widget.acuerdoId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acuerdo finalizado')),
        );
        _cargarDatos();
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'detalle_acuerdo_page.finalizar_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'acuerdo_id': widget.acuerdoId},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editarAcuerdo() async {
    // Verificar si tiene compromisos confirmados
    final cuotasConfirmadas = _stats?['cuotas_confirmadas'] as int? ?? 0;
    
    if (cuotasConfirmadas > 0) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No se puede editar'),
          content: const Text(
            'Este acuerdo ya tiene compromisos confirmados y no puede ser editado.\n\n'
            'Si necesita modificarlo, puede finalizarlo y crear uno nuevo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => EditarAcuerdoPage(acuerdoId: widget.acuerdoId),
      ),
    );
    
    if (resultado == true) {
      _cargarDatos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Acuerdo'),
        actions: [
          if (_acuerdo != null && (_acuerdo!['activo'] as int) == 1)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'editar':
                    _editarAcuerdo();
                    break;
                  case 'finalizar':
                    _finalizarAcuerdo();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'finalizar',
                  child: Row(
                    children: [
                      Icon(Icons.stop),
                      SizedBox(width: 8),
                      Text('Finalizar'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 800,
              child: RefreshIndicator(
                onRefresh: _cargarDatos,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  _buildEstadisticasCard(),
                  const SizedBox(height: 16),
                  _buildCompromisosCard(),
                ],
              ),
            ),
            ),
    );
  }

  Widget _buildInfoCard() {
    final nombre = _acuerdo!['nombre']?.toString() ?? 'Sin nombre';
    final tipo = _acuerdo!['tipo']?.toString() ?? 'EGRESO';
    final modalidad = _acuerdo!['modalidad']?.toString() ?? 'RECURRENTE';
    final activo = (_acuerdo!['activo'] as int?) == 1;
    final categoria = _acuerdo!['categoria']?.toString() ?? '-';
    final fechaInicio = _acuerdo!['fecha_inicio']?.toString() ?? '-';
    final fechaFin = _acuerdo!['fecha_fin']?.toString();
    final observaciones = _acuerdo!['observaciones']?.toString();
    final unidadNombre = _acuerdo!['_unidad_nombre']?.toString() ?? 'Desconocida';
    final entidadNombre = _acuerdo!['_entidad_nombre']?.toString();
    final frecuencia = _acuerdo!['frecuencia']?.toString() ?? '-';
    
    final montoDisplay = modalidad == 'MONTO_TOTAL_CUOTAS'
        ? (_acuerdo!['monto_total'] as num?)?.toDouble() ?? 0.0
        : (_acuerdo!['monto_periodico'] as num?)?.toDouble() ?? 0.0;
    
    final cuotas = _acuerdo!['cuotas'] as int?;
    
    return Card(
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
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (!activo)
                        Chip(
                          label: const Text('Finalizado', style: TextStyle(fontSize: 11)),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.grey.shade300,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            _buildInfoRow('Unidad de Gestión', unidadNombre, Icons.business),
            if (entidadNombre != null)
              _buildInfoRow('Entidad', entidadNombre, Icons.person),
            _buildInfoRow('Tipo', tipo, Icons.category),
            _buildInfoRow('Categoría', _categoriaNombre ?? categoria, Icons.label),
            _buildInfoRow('Modalidad', _modalidadLabel(modalidad), Icons.payment),
            _buildInfoRow('Monto', Format.money(montoDisplay), Icons.attach_money),
            if (cuotas != null)
              _buildInfoRow('Cuotas', cuotas.toString(), Icons.format_list_numbered),
            _buildInfoRow('Frecuencia', frecuencia, Icons.schedule),
            _buildInfoRow('Fecha Inicio', fechaInicio, Icons.calendar_today),
            if (fechaFin != null)
              _buildInfoRow('Fecha Fin', fechaFin, Icons.event),
            
            if (observaciones != null && observaciones.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Observaciones',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(observaciones),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticasCard() {
    final cuotasEsperadas = _stats?['cuotas_esperadas'] as int? ?? 0;
    final cuotasConfirmadas = _stats?['cuotas_confirmadas'] as int? ?? 0;
    final cuotasCanceladas = _stats?['cuotas_canceladas'] as int? ?? 0;
    final cuotasTotal = cuotasEsperadas + cuotasConfirmadas + cuotasCanceladas;
    final montoEsperado = (_stats?['monto_total_esperado'] as num?)?.toDouble() ?? 0.0;
    final montoConfirmado = (_stats?['monto_total_confirmado'] as num?)?.toDouble() ?? 0.0;
    
    final progreso = cuotasTotal > 0 ? cuotasConfirmadas / cuotasTotal : 0.0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estadísticas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            
            LinearProgressIndicator(
              value: progreso,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                _acuerdo!['tipo'] == 'INGRESO' ? Colors.green : Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progreso * 100).toStringAsFixed(1)}% completado',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Esperadas',
                    cuotasEsperadas.toString(),
                    Colors.orange,
                    Icons.schedule,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Confirmadas',
                    cuotasConfirmadas.toString(),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Canceladas',
                    cuotasCanceladas.toString(),
                    Colors.red,
                    Icons.cancel,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      'Monto Esperado',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Format.money(montoEsperado),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Monto Confirmado',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Format.money(montoConfirmado),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCompromisosCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compromisos Generados (${_compromisos.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            
            if (_compromisos.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay compromisos generados'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _compromisos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final compromiso = _compromisos[index];
                  final stats = compromiso['_cuotas_stats'] as Map<String, dynamic>?;
                  final confirmadas = (stats?['confirmadas'] as int?) ?? 0;
                  final total = (stats?['total'] as int?) ?? 0;
                  
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text('${index + 1}'),
                    ),
                    title: Text(compromiso['nombre']?.toString() ?? 'Sin nombre'),
                    subtitle: Text(
                      'Cuotas: $confirmadas/$total confirmadas',
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => DetalleCompromisoPage(
                            compromisoId: compromiso['id'] as int,
                          ),
                        ),
                      ).then((_) => _cargarDatos());
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
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
