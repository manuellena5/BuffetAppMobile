import 'package:flutter/material.dart';
import '../../../data/dao/db.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../../features/shared/services/acuerdos_service.dart';
import '../../shared/widgets/responsive_container.dart';
import 'editar_jugador_page.dart';
import 'detalle_acuerdo_page.dart';

/// FASE 17.5: Pantalla de detalle de un jugador/staff.
/// Muestra información completa, compromisos asociados, estado económico e historial de pagos.
class DetalleJugadorPage extends StatefulWidget {
  final int entidadId;

  const DetalleJugadorPage({
    Key? key,
    required this.entidadId,
  }) : super(key: key);

  @override
  State<DetalleJugadorPage> createState() => _DetalleJugadorPageState();
}

class _DetalleJugadorPageState extends State<DetalleJugadorPage> {
  final _plantelSvc = PlantelService.instance;

  bool _cargando = true;
  Map<String, dynamic>? _entidad;
  List<Map<String, dynamic>> _compromisos = [];
  Map<String, dynamic> _estadoMensual = {};
  List<Map<String, dynamic>> _historialPagos = [];
  String? _errorCompromisos;
  
  // FASE 19: Acuerdos activos de esta entidad
  List<Map<String, dynamic>> _acuerdosActivos = [];

  late int _mesActual;
  late int _anioActual;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _mesActual = ahora.month;
    _anioActual = ahora.year;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final entidad = await _plantelSvc.obtenerEntidad(widget.entidadId);
      if (entidad == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entidad no encontrada')),
          );
          Navigator.pop(context);
        }
        return;
      }

      // Cargar compromisos con manejo de errores
      List<Map<String, dynamic>> compromisos = [];
      String? errorCompromisos;
      try {
        compromisos = await _plantelSvc.listarCompromisosDeEntidad(widget.entidadId);
      } catch (e, stack) {
        errorCompromisos = 'Error al cargar compromisos: ${e.toString()}';
        await AppDatabase.logLocalError(
          scope: 'detalle_jugador.cargar_compromisos',
          error: e.toString(),
          stackTrace: stack,
          payload: {'entidad_id': widget.entidadId},
        );
      }

      final estadoMensual = await _plantelSvc.calcularEstadoMensualPorEntidad(
        widget.entidadId,
        _anioActual,
        _mesActual,
      );
      
      // Calcular rango de últimos 6 meses
      final ahora = DateTime(_anioActual, _mesActual, 1);
      final hace6Meses = DateTime(ahora.year, ahora.month - 6, 1);
      
      final historialPagos = await _plantelSvc.obtenerHistorialPagosPorEntidad(
        widget.entidadId,
        desde: hace6Meses,
        hasta: ahora,
      );
      
      // FASE 19: Cargar acuerdos activos de esta entidad
      List<Map<String, dynamic>> acuerdos = [];
      try {
        acuerdos = await AcuerdosService.listarAcuerdos(
          entidadPlantelId: widget.entidadId,
          soloActivos: true,
        );
      } catch (e, stack) {
        await AppDatabase.logLocalError(
          scope: 'detalle_jugador.cargar_acuerdos',
          error: e.toString(),
          stackTrace: stack,
          payload: {'entidad_id': widget.entidadId},
        );
        // No fallar por esto
      }

      setState(() {
        _entidad = entidad;
        _compromisos = compromisos;
        _estadoMensual = estadoMensual;
        _historialPagos = historialPagos;
        _errorCompromisos = errorCompromisos;
        _acuerdosActivos = acuerdos;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar detalle: $e')),
        );
      }
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarEstado() async {
    if (_entidad == null) return;

    final activo = (_entidad!['estado_activo'] as int) == 1;
    final accion = activo ? 'dar de baja' : 'reactivar';

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${accion[0].toUpperCase()}${accion.substring(1)}'),
        content: Text(
          activo
              ? '¿Dar de baja a ${_entidad!['nombre']}?\nSolo se permite si no tiene compromisos activos.'
              : '¿Reactivar a ${_entidad!['nombre']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      if (activo) {
        await _plantelSvc.darDeBajaEntidad(widget.entidadId);
      } else {
        await _plantelSvc.reactivarEntidad(widget.entidadId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(activo ? 'Dado de baja correctamente' : 'Reactivado correctamente')),
        );
      }
      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _irAEditar() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarJugadorPage(entidadId: widget.entidadId),
      ),
    );
    await _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    final activo = _entidad != null && (_entidad!['estado_activo'] as int) == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(_entidad?['nombre'] ?? 'Detalle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Editar',
            onPressed: _cargando ? null : _irAEditar,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'estado') {
                _cambiarEstado();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'estado',
                child: Row(
                  children: [
                    Icon(activo ? Icons.block : Icons.check_circle, size: 20),
                    const SizedBox(width: 8),
                    Text(activo ? 'Dar de baja' : 'Reactivar'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 800,
              child: RefreshIndicator(
                onRefresh: _cargarDatos,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                    // Información básica
                    _buildInformacionBasica(),

                    const Divider(height: 1),

                    // Resumen económico mensual
                    _buildResumenEconomico(),

                    const Divider(height: 1),

                    // FASE 19: Acuerdos activos
                    if (_acuerdosActivos.isNotEmpty) ...[
                      _buildAcuerdos(),
                      const Divider(height: 1),
                    ],

                    // Compromisos asociados
                    _buildCompromisos(),

                    const Divider(height: 1),

                    // Historial de pagos
                    _buildHistorialPagos(),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            ),
    );
  }

  Widget _buildInformacionBasica() {
    if (_entidad == null) return const SizedBox.shrink();

    final nombre = _entidad!['nombre'] as String;
    final rol = _entidad!['rol'] as String;
    final activo = (_entidad!['estado_activo'] as int) == 1;
    final contacto = _entidad!['contacto'] as String?;
    final dni = _entidad!['dni'] as String?;
    final fechaNac = _entidad!['fecha_nacimiento'] as String?;
    final observaciones = _entidad!['observaciones'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      color: activo ? Colors.blue.shade50 : Colors.grey.shade200,
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: _colorPorRol(rol),
            child: Text(
              _inicialesNombre(nombre),
              style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            nombre,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              decoration: activo ? null : TextDecoration.lineThrough,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Chip(
            label: Text(_nombreRol(rol)),
            backgroundColor: _colorPorRol(rol).withOpacity(0.2),
          ),
          const SizedBox(height: 8),
          if (!activo)
            const Chip(
              label: Text('DADO DE BAJA'),
              backgroundColor: Colors.red,
              labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          const Divider(height: 24),
          if (contacto != null && contacto.isNotEmpty)
            _buildInfoRow(Icons.phone, 'Contacto', contacto),
          if (dni != null && dni.isNotEmpty)
            _buildInfoRow(Icons.badge, 'DNI', dni),
          if (fechaNac != null && fechaNac.isNotEmpty)
            _buildInfoRow(Icons.cake, 'Fecha nacimiento', fechaNac),
          if (observaciones != null && observaciones.isNotEmpty)
            _buildInfoRow(Icons.notes, 'Observaciones', observaciones),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icono, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenEconomico() {
    final totalComprometido = _estadoMensual['totalComprometido'] as double? ?? 0.0;
    final pagado = _estadoMensual['pagado'] as double? ?? 0.0;
    final esperado = _estadoMensual['esperado'] as double? ?? 0.0;
    final atrasado = _estadoMensual['atrasado'] as double? ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_money, color: Colors.blue.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                'Resumen Económico - ${_nombreMes(_mesActual)} $_anioActual',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard('Total mensual', '\$${_formatMonto(totalComprometido)}', Colors.blue),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard('Pagado', '\$${_formatMonto(pagado)}', Colors.green),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard('Esperado', '\$${_formatMonto(esperado)}', Colors.orange),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard('Atrasado', '\$${_formatMonto(atrasado)}', Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String valor, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompromisos() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Compromisos Asociados',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Mostrar error si hubo problemas al cargar
          if (_errorCompromisos != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se pudieron cargar los compromisos. Por favor, intente nuevamente.',
                        style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_compromisos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sin compromisos asociados',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _compromisos.length,
              itemBuilder: (context, index) {
                try {
                  final comp = _compromisos[index];
                  // Usar 'nombre' en lugar de 'concepto' y manejar nulls
                  final nombre = comp['nombre']?.toString() ?? 'Sin nombre';
                  final monto = (comp['monto'] as num?)?.toDouble() ?? 0.0;
                  final activo = (comp['activo'] as int?) == 1;
                  final fechaInicio = comp['fecha_inicio']?.toString();
                  final fechaFin = comp['fecha_fin']?.toString();
                  final categoria = comp['categoria']?.toString();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: activo ? null : Colors.grey.shade100,
                    child: ListTile(
                      leading: Icon(
                        activo ? Icons.check_circle : Icons.cancel,
                        color: activo ? Colors.green : Colors.grey,
                      ),
                      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (categoria != null)
                            Text(categoria, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          Text('\$${_formatMonto(monto)} mensual', style: const TextStyle(fontSize: 12)),
                          if (fechaInicio != null || fechaFin != null)
                            Text(
                              '${fechaInicio ?? '?'} → ${fechaFin ?? 'vigente'}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                      trailing: activo
                          ? const Chip(
                              label: Text('Activo', style: TextStyle(fontSize: 10)),
                              backgroundColor: Colors.green,
                              labelStyle: TextStyle(color: Colors.white),
                            )
                          : const Chip(
                              label: Text('Inactivo', style: TextStyle(fontSize: 10)),
                              backgroundColor: Colors.grey,
                              labelStyle: TextStyle(color: Colors.white),
                            ),
                    ),
                  );
                } catch (e, stack) {
                  // Loguear error individual y mostrar item de error
                  AppDatabase.logLocalError(
                    scope: 'detalle_jugador.render_compromiso',
                    error: e.toString(),
                    stackTrace: stack,
                    payload: {'index': index, 'compromiso': _compromisos[index]},
                  );
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.orange.shade50,
                    child: ListTile(
                      leading: Icon(Icons.warning, color: Colors.orange.shade700),
                      title: const Text('Error al mostrar compromiso'),
                      subtitle: const Text(
                        'Algunos datos no están disponibles',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistorialPagos() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.purple.shade700, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Historial de Pagos (últimos 6 meses)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_historialPagos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sin pagos registrados',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _historialPagos.length,
              itemBuilder: (context, index) {
                final pago = _historialPagos[index];
                final mesAnio = pago['mes_anio'] as String;
                final totalPagado = pago['totalPagado'] as double;
                final cantidadMovimientos = pago['cantidadMovimientos'] as int;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.payment, color: Colors.green),
                    title: Text(mesAnio, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('$cantidadMovimientos pago(s)', style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      '\$${_formatMonto(totalPagado)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatMonto(double monto) {
    return monto.toStringAsFixed(0);
  }

  String _nombreMes(int mes) {
    const meses = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return meses[mes - 1];
  }

  String _nombreRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return 'Jugador';
      case 'DT':
        return 'Director Técnico';
      case 'AYUDANTE':
        return 'Ayudante de Campo';
      case 'PF':
        return 'Preparador Físico';
      case 'OTRO':
        return 'Otro';
      default:
        return rol;
    }
  }

  String _inicialesNombre(String nombre) {
    final partes = nombre.trim().split(' ');
    if (partes.length >= 2) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    } else if (partes.isNotEmpty) {
      return partes[0][0].toUpperCase();
    }
    return '?';
  }

  Color _colorPorRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return Colors.blue;
      case 'DT':
        return Colors.purple;
      case 'AYUDANTE':
        return Colors.teal;
      case 'PF':
        return Colors.orange;
      case 'OTRO':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
  
  // FASE 19: Widget de sección de acuerdos activos
  Widget _buildAcuerdos() {
    return ExpansionTile(
      leading: const Icon(Icons.handshake),
      title: const Text('Acuerdos Económicos'),
      subtitle: Text('${_acuerdosActivos.length} activos'),
      initiallyExpanded: true,
      children: _acuerdosActivos.map((acuerdo) {
        final nombre = acuerdo['nombre']?.toString() ?? 'Sin nombre';
        final modalidad = acuerdo['modalidad']?.toString() ?? 'RECURRENTE';
        final origenGrupal = (acuerdo['origen_grupal'] as int?) == 1;
        
        final monto = modalidad == 'MONTO_TOTAL_CUOTAS'
            ? (acuerdo['monto_total'] as num?)?.toDouble() ?? 0.0
            : (acuerdo['monto_periodico'] as num?)?.toDouble() ?? 0.0;
        
        final frecuencia = acuerdo['frecuencia']?.toString() ?? '';
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: origenGrupal
                ? const Icon(Icons.group, color: Colors.blue)
                : const Icon(Icons.person),
            title: Text(nombre),
            subtitle: Text(
              '\$${monto.toStringAsFixed(2)} - $frecuencia',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (origenGrupal)
                  Chip(
                    label: const Text('Grupal', style: TextStyle(fontSize: 10)),
                    padding: const EdgeInsets.all(4),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.blue.shade100,
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => DetalleAcuerdoPage(
                    acuerdoId: acuerdo['id'] as int,
                  ),
                ),
              ).then((_) => _cargarDatos());
            },
          ),
        );
      }).toList(),
    );
  }
}
