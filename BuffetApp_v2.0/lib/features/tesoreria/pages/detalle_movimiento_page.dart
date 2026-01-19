import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/responsive_container.dart';
import 'package:open_filex/open_filex.dart';
import '../../shared/services/movimiento_service.dart';
import '../../shared/services/tesoreria_sync_service.dart';
import '../../shared/services/compromisos_service.dart';
import '../../shared/format.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import 'crear_movimiento_page.dart';

/// Pantalla de detalle de un movimiento financiero
/// Permite ver toda la información y modificar/eliminar
class DetalleMovimientoPage extends StatefulWidget {
  final int movimientoId;

  const DetalleMovimientoPage({
    super.key,
    required this.movimientoId,
  });

  @override
  State<DetalleMovimientoPage> createState() => _DetalleMovimientoPageState();
}

class _DetalleMovimientoPageState extends State<DetalleMovimientoPage> {
  final _svc = EventoMovimientoService();
  final _syncSvc = TesoreriaSyncService();
  final _compromisosService = CompromisosService.instance;
  Map<String, dynamic>? _movimiento;
  Map<String, dynamic>? _compromiso;
  bool _loading = true;
  bool _deleting = false;
  String? _categoriaNombre;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mov = await _svc.obtenerPorId(widget.movimientoId);
      
      // Cargar compromiso asociado si existe
      Map<String, dynamic>? compromiso;
      if (mov != null && mov['compromiso_id'] != null) {
        final compromisoId = mov['compromiso_id'] as int;
        compromiso = await _compromisosService.obtenerCompromiso(compromisoId);
      }
      
      // Cargar nombre de categoría
      String? catNombre;
      if (mov != null) {
        final codigoCat = (mov['categoria'] ?? '').toString();
        if (codigoCat.isNotEmpty) {
          catNombre = await CategoriaMovimientoService.obtenerNombrePorCodigo(codigoCat);
        }
      }
      
      if (mounted) {
        setState(() {
          _movimiento = mov;
          _compromiso = compromiso;
          _categoriaNombre = catNombre;
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_movimiento.load',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    }
  }

  Future<void> _sincronizar() async {
    if (_movimiento == null) return;

    final syncEstado = (_movimiento!['sync_estado'] ?? '').toString().toUpperCase();
    
    // Si ya está sincronizado, mostrar mensaje
    if (syncEstado == 'SINCRONIZADA') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este movimiento ya está sincronizado')),
      );
      return;
    }

    // Verificar conexión
    final conectado = await _syncSvc.verificarConexion();
    if (!conectado) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.orange),
                SizedBox(width: 8),
                Text('Sin conexión'),
              ],
            ),
            content: const Text(
              'No se pudo conectar con Supabase.\n\n'
              'Verificá tu conexión a internet e intentá nuevamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Mostrar diálogo de progreso
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Sincronizando movimiento...'),
          ],
        ),
      ),
    );

    try {
      final success = await _syncSvc.syncMovimiento(widget.movimientoId);

      if (mounted) {
        // Cerrar progreso
        Navigator.pop(context);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Movimiento sincronizado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
          await _load(); // Recargar para actualizar estado
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Error al sincronizar'),
                ],
              ),
              content: const Text('No se pudo sincronizar el movimiento.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_movimiento.sincronizar',
        error: e,
        stackTrace: st,
      );

      if (mounted) {
        // Cerrar progreso
        Navigator.pop(context);

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error al sincronizar'),
              ],
            ),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _modificar() async {
    if (_movimiento == null) return;
    
    // TODO: Implementar edición de movimientos
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('La edición de movimientos estará disponible próximamente'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _eliminar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: const Text(
          '¿Estás seguro de que querés eliminar este movimiento?\n\n'
          'Esta acción ocultará el movimiento de la lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await _svc.eliminar(widget.movimientoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Movimiento eliminado'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true); // Volver con indicador de cambio
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_movimiento.eliminar',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '-';
    DateTime? fecha;
    if (ts is int) {
      fecha = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      fecha = DateTime.tryParse(ts);
    }
    if (fecha == null) return '-';
    return DateFormat('dd/MM/yyyy HH:mm').format(fecha);
  }

  String _getModalidadLabel(String? modalidad) {
    if (modalidad == null) return '-';
    switch (modalidad) {
      case 'PAGO_UNICO':
        return 'Pago único';
      case 'MONTO_TOTAL_CUOTAS':
        return 'Monto total en cuotas';
      case 'RECURRENTE':
        return 'Recurrente';
      default:
        return modalidad;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Movimiento'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_movimiento != null) ...[
            // Botón de sincronización
            if ((_movimiento!['sync_estado'] ?? '').toString().toUpperCase() != 'SINCRONIZADA')
              IconButton(
                icon: const Icon(Icons.cloud_upload),
                tooltip: 'Sincronizar con Supabase',
                onPressed: _sincronizar,
              ),
            // Edición deshabilitada temporalmente
            // IconButton(
            //   icon: const Icon(Icons.edit),
            //   tooltip: 'Modificar',
            //   onPressed: _modificar,
            // ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Eliminar',
              onPressed: _deleting ? null : _eliminar,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _movimiento == null
              ? const Center(
                  child: Text('Movimiento no encontrado'),
                )
              : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final mov = _movimiento!;
    final tipo = (mov['tipo'] ?? '').toString();
    final esIngreso = tipo == 'INGRESO';
    final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
    final categoria = (mov['categoria'] ?? '').toString();
    final medioPago = (mov['medio_pago_desc'] ?? '').toString();
    final obs = (mov['observacion'] ?? '').toString();
    final syncEstado = (mov['sync_estado'] ?? '').toString();
    final archivoPath = (mov['archivo_local_path'] ?? '').toString();
    final archivoNombre = (mov['archivo_nombre'] ?? '').toString();

    return ResponsiveContainer(
      maxWidth: 800,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header con tipo y monto
          Card(
            elevation: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: esIngreso
                      ? [Colors.green.shade400, Colors.green.shade600]
                      : [Colors.red.shade400, Colors.red.shade600],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tipo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Format.money(monto),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Compromiso asociado (si existe)
          if (_compromiso != null) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_note, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Compromiso Asociado',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildDetailRow(
                      icon: Icons.title,
                      label: 'Nombre',
                      value: _compromiso!['nombre'] as String? ?? '-',
                    ),
                    _buildDetailRow(
                      icon: Icons.info_outline,
                      label: 'Tipo',
                      value: _compromiso!['tipo'] as String? ?? '-',
                    ),
                    _buildDetailRow(
                      icon: Icons.repeat,
                      label: 'Modalidad',
                      value: _getModalidadLabel(_compromiso!['modalidad'] as String?),
                    ),
                    _buildDetailRow(
                      icon: Icons.schedule,
                      label: 'Frecuencia',
                      value: _compromiso!['frecuencia'] as String? ?? '-',
                    ),
                    if (_compromiso!['cuotas'] != null)
                      _buildDetailRow(
                        icon: Icons.numbers,
                        label: 'Cuotas',
                        value: '${_compromiso!['cuotas_confirmadas'] ?? 0}/${_compromiso!['cuotas']} confirmadas',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Detalles
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detalles',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  _buildDetailRow(
                    icon: Icons.category,
                    label: 'Categoría',
                    value: categoria.isEmpty ? 'Sin categoría' : (_categoriaNombre ?? categoria),
                  ),
                  _buildDetailRow(
                    icon: Icons.payment,
                    label: 'Medio de pago',
                    value: medioPago.isEmpty ? '-' : medioPago,
                  ),
                  if (obs.isNotEmpty)
                    _buildDetailRow(
                      icon: Icons.notes,
                      label: 'Observación',
                      value: obs,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Fechas
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fechas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  _buildDetailRow(
                    icon: Icons.calendar_today,
                    label: 'Fecha de creación',
                    value: _formatTimestamp(mov['created_ts']),
                  ),
                  if (mov['updated_ts'] != null)
                    _buildDetailRow(
                      icon: Icons.edit_calendar,
                      label: 'Última modificación',
                      value: _formatTimestamp(mov['updated_ts']),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Archivo adjunto
          if (archivoPath.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Archivo adjunto',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        const Icon(Icons.attach_file, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            archivoNombre.isNotEmpty ? archivoNombre : 'Archivo adjunto',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (File(archivoPath).existsSync())
                      GestureDetector(
                        onTap: () async {
                          try {
                            final result = await OpenFilex.open(archivoPath);
                            if (result.type != ResultType.done && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('No se pudo abrir el archivo: ${result.message}'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error al abrir archivo: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              Image.file(
                                File(archivoPath),
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 100,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.broken_image, size: 48),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app, color: Colors.white, size: 16),
                                      SizedBox(width: 4),
                                      Text(
                                        'Toca para abrir',
                                        style: TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text('Archivo no disponible'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Estado de sincronización
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sincronización',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  _buildSyncStatus(syncEstado),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Botón de acción
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _deleting ? null : _eliminar,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete),
              label: Text(_deleting ? 'Eliminando...' : 'Eliminar Movimiento'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatus(String syncEstado) {
    IconData icon;
    Color color;
    String text;

    switch (syncEstado.toUpperCase()) {
      case 'SINCRONIZADA':
        icon = Icons.cloud_done;
        color = Colors.green;
        text = 'Sincronizado';
        break;
      case 'ERROR':
        icon = Icons.error_outline;
        color = Colors.red;
        text = 'Error de sincronización';
        break;
      default:
        icon = Icons.cloud_queue;
        color = Colors.orange;
        text = 'Pendiente de sincronización';
    }

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
