import 'package:flutter/material.dart';
import '../../../data/dao/db.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import 'detalle_jugador_page.dart';
import 'gestionar_jugadores_page.dart';

/// FASE 17.4: Pantalla resumen de la situación económica del plantel.
/// Vista de solo lectura que muestra el estado de pagos de jugadores/cuerpo técnico.
class PlantelPage extends StatefulWidget {
  const PlantelPage({Key? key}) : super(key: key);

  @override
  State<PlantelPage> createState() => _PlantelPageState();
}

class _PlantelPageState extends State<PlantelPage> {
  final _plantelSvc = PlantelService.instance;

  bool _cargando = true;
  String _filtroRol = 'TODOS';
  String _filtroEstado = 'ACTIVOS';
  bool _vistaTabla = false;

  // Resumen general
  Map<String, dynamic> _resumenGeneral = {};

  // Entidades con su estado económico
  List<Map<String, dynamic>> _entidadesConEstado = [];

  // Mes actual
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
      // Cargar resumen general
      final resumen = await _plantelSvc.calcularResumenGeneral(_anioActual, _mesActual);

      // Cargar entidades según filtros
      var entidades = await _plantelSvc.listarEntidades(
        rol: _filtroRol == 'TODOS' ? null : _filtroRol,
        soloActivos: _filtroEstado == 'ACTIVOS',
      );

      // Filtrar manualmente si se seleccionó BAJA
      if (_filtroEstado == 'BAJA') {
        entidades = entidades.where((e) => (e['estado_activo'] as int) == 0).toList();
      }

      // Calcular estado económico de cada entidad
      final entidadesConEstado = <Map<String, dynamic>>[];
      for (final entidad in entidades) {
        try {
          final id = entidad['id'] as int;
          final estado = await _plantelSvc.calcularEstadoMensualPorEntidad(
            id,
            _anioActual,
            _mesActual,
          );

          entidadesConEstado.add({
            ...entidad,
            'totalComprometido': estado['totalComprometido'],
            'pagado': estado['pagado'],
            'esperado': estado['esperado'],
            'atrasado': estado['atrasado'],
          });
        } catch (e, stack) {
          // Loguear error individual pero continuar con otros
          await AppDatabase.logLocalError(
            scope: 'plantel_page.cargar_estado_entidad',
            error: e.toString(),
            stackTrace: stack,
            payload: {'entidad_id': entidad['id']},
          );
        }
      }

      setState(() {
        _resumenGeneral = resumen;
        _entidadesConEstado = entidadesConEstado;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'plantel_page.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
        payload: {'filtro_rol': _filtroRol, 'filtro_estado': _filtroEstado},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar datos del plantel. Por favor, intente nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _irADetalle(int entidadId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleJugadorPage(entidadId: entidadId),
      ),
    ).then((_) => _cargarDatos()); // Recargar al volver
  }

  void _irAGestionar() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GestionarJugadoresPage()),
    ).then((_) => _cargarDatos());
  }

  @override
  Widget build(BuildContext context) {
    return TesoreriaScaffold(
      title: 'Plantel - ${_nombreMes(_mesActual)} $_anioActual',
      currentRouteName: '/plantel',
      actions: [
        IconButton(
          icon: Icon(_vistaTabla ? Icons.view_module : Icons.table_chart),
          tooltip: _vistaTabla ? 'Ver tarjetas' : 'Ver tabla',
          onPressed: () => setState(() => _vistaTabla = !_vistaTabla),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _irAGestionar,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.settings),
        label: const Text('Gestionar'),
      ),
      body: ResponsiveContainer(
        maxWidth: 1000,
        child: RefreshIndicator(
          onRefresh: _cargarDatos,
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // BLOQUE 1: Resumen General
                    _buildResumenGeneral(),

                    const Divider(height: 1),

                    // Filtros
                    _buildFiltros(),

                    const Divider(height: 1),

                    // BLOQUE 2: Lista de jugadores
                    if (_entidadesConEstado.isEmpty)
                      _buildEmpty()
                    else if (_vistaTabla)
                      _buildTabla()
                    else
                      _buildTarjetas(),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildResumenGeneral() {
    final totalComprometido = _resumenGeneral['totalMensualComprometido'] as double? ?? 0.0;
    final pagado = _resumenGeneral['pagadoEsteMes'] as double? ?? 0.0;
    final pendiente = _resumenGeneral['pendienteEsteMes'] as double? ?? 0.0;
    final cantidadJugadores = _resumenGeneral['cantidadJugadores'] as int? ?? 0;
    final jugadoresAlDia = _resumenGeneral['jugadoresAlDia'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups, color: Colors.blue.shade700, size: 28),
              const SizedBox(width: 12),
              Text(
                'Resumen General',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Totales
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  'Total mensual',
                  '\$ ${_formatMonto(totalComprometido)}',
                  Icons.attach_money,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  'Pagado',
                  '\$ ${_formatMonto(pagado)}',
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  'Pendiente',
                  '\$ ${_formatMonto(pendiente)}',
                  Icons.pending,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  'Jugadores al día',
                  '$jugadoresAlDia / $cantidadJugadores',
                  Icons.people_alt,
                  jugadoresAlDia == cantidadJugadores ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String valor, IconData icono, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 16, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade100,
      child: Column(
        children: [
          Row(
            children: [
              const Text('Rol:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [
                    _buildChipFiltro('TODOS', _filtroRol == 'TODOS', esRol: true),
                    _buildChipFiltro('JUGADOR', _filtroRol == 'JUGADOR', esRol: true),
                    _buildChipFiltro('DT', _filtroRol == 'DT', esRol: true),
                    _buildChipFiltro('AYUDANTE', _filtroRol == 'AYUDANTE', esRol: true),
                    _buildChipFiltro('PF', _filtroRol == 'PF', esRol: true),
                    _buildChipFiltro('OTRO', _filtroRol == 'OTRO', esRol: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Estado:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: [
                    _buildChipFiltro('ACTIVOS', _filtroEstado == 'ACTIVOS', esRol: false),
                    _buildChipFiltro('BAJA', _filtroEstado == 'BAJA', esRol: false),
                    _buildChipFiltro('TODOS', _filtroEstado == 'TODOS', esRol: false),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro(String label, bool selected, {required bool esRol}) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (value) {
        setState(() {
          if (esRol) {
            _filtroRol = label;
          } else {
            _filtroEstado = label;
          }
        });
        _cargarDatos();
      },
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No hay entidades para mostrar',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _irAGestionar,
            icon: const Icon(Icons.settings),
            label: const Text('Gestionar jugadores'),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetas() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: _entidadesConEstado.length,
      itemBuilder: (context, index) {
        final entidad = _entidadesConEstado[index];
        return _buildTarjetaEntidad(entidad);
      },
    );
  }

  Widget _buildTarjetaEntidad(Map<String, dynamic> entidad) {
    try {
      final id = entidad['id'] as int;
      final nombre = entidad['nombre']?.toString() ?? 'Sin nombre';
      final rol = entidad['rol']?.toString() ?? 'OTRO';
      final activo = (entidad['estado_activo'] as int?) == 1;
      final totalComprometido = (entidad['totalComprometido'] as num?)?.toDouble() ?? 0.0;
      final pagado = (entidad['pagado'] as num?)?.toDouble() ?? 0.0;
      final esperado = (entidad['esperado'] as num?)?.toDouble() ?? 0.0;

      final estadoPago = esperado == 0 ? 'Al día' : pagado == 0 ? 'Sin pagos' : 'Pendiente';
      final colorEstado = esperado == 0
          ? Colors.green
          : pagado == 0
              ? Colors.red
              : Colors.orange;

      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: activo ? null : Colors.grey.shade200,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _colorPorRol(rol),
            child: Text(
              _inicialesRol(rol),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            nombre,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              decoration: activo ? null : TextDecoration.lineThrough,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_nombreRol(rol), style: const TextStyle(fontSize: 12)),
                  // Mostrar alias si existe
                  if (entidad['alias'] != null && (entidad['alias'] as String).isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '"${entidad['alias']}"',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
              // Mostrar tipo_contratacion y posicion para JUGADOR
              if (rol == 'JUGADOR') ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (entidad['tipo_contratacion'] != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: entidad['tipo_contratacion'] == 'LOCAL'
                              ? Colors.blue.shade50
                              : entidad['tipo_contratacion'] == 'REFUERZO'
                                  ? Colors.purple.shade50
                                  : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: entidad['tipo_contratacion'] == 'LOCAL'
                                ? Colors.blue.shade300
                                : entidad['tipo_contratacion'] == 'REFUERZO'
                                    ? Colors.purple.shade300
                                    : Colors.grey.shade400,
                          ),
                        ),
                        child: Text(
                          entidad['tipo_contratacion'].toString(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (entidad['posicion'] != null) ...[
                      Icon(_iconPosicion(entidad['posicion'].toString()), size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        _nombrePosicion(entidad['posicion'].toString()),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.attach_money, size: 14, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Total: \$${_formatMonto(totalComprometido)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text('Pagado: \$${_formatMonto(pagado)}', style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  Icon(Icons.pending, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text('Pendiente: \$${_formatMonto(esperado)}', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
          trailing: Chip(
            label: Text(estadoPago, style: const TextStyle(fontSize: 10)),
            backgroundColor: colorEstado.withOpacity(0.2),
            side: BorderSide(color: colorEstado),
          ),
          onTap: () => _irADetalle(id),
        ),
      );
    } catch (e, stack) {
      // Loguear error y mostrar tarjeta de error
      AppDatabase.logLocalError(
        scope: 'plantel_page.render_tarjeta',
        error: e.toString(),
        stackTrace: stack,
        payload: {'entidad': entidad},
      );
      
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Colors.orange.shade50,
        child: ListTile(
          leading: Icon(Icons.warning, color: Colors.orange.shade700),
          title: const Text('Error al mostrar entidad'),
          subtitle: const Text('Algunos datos no están disponibles', style: TextStyle(fontSize: 11)),
        ),
      );
    }
  }

  Widget _buildTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
        columns: const [
          DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Rol', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total Mensual', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Pagado', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Pendiente', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _entidadesConEstado.map((entidad) {
          final id = entidad['id'] as int;
          final nombre = entidad['nombre'] as String;
          final rol = entidad['rol'] as String;
          final activo = (entidad['estado_activo'] as int) == 1;
          final totalComprometido = entidad['totalComprometido'] as double;
          final pagado = entidad['pagado'] as double;
          final esperado = entidad['esperado'] as double;

          final estadoPago = esperado == 0 ? '✅ Al día' : pagado == 0 ? '⚠ Sin pagos' : '⏳ Pendiente';

          return DataRow(
            color: MaterialStateProperty.all(activo ? null : Colors.grey.shade100),
            cells: [
              DataCell(Text(nombre, style: TextStyle(decoration: activo ? null : TextDecoration.lineThrough))),
              DataCell(Text(_nombreRol(rol))),
              DataCell(Text('\$ ${_formatMonto(totalComprometido)}')),
              DataCell(Text('\$ ${_formatMonto(pagado)}', style: TextStyle(color: Colors.green.shade700))),
              DataCell(Text('\$ ${_formatMonto(esperado)}', style: TextStyle(color: Colors.orange.shade700))),
              DataCell(Text(estadoPago)),
            ],
            onSelectChanged: (_) => _irADetalle(id),
          );
        }).toList(),
      ),
    );
  }

  String _formatMonto(double monto) {
    if (monto >= 1000000) {
      return '${(monto / 1000000).toStringAsFixed(1)}M';
    } else if (monto >= 1000) {
      return '${(monto / 1000).toStringAsFixed(0)}k';
    } else {
      return monto.toStringAsFixed(0);
    }
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

  String _inicialesRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return 'J';
      case 'DT':
        return 'DT';
      case 'AYUDANTE':
        return 'AC';
      case 'PF':
        return 'PF';
      case 'OTRO':
        return 'O';
      default:
        return '?';
    }
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

  String _nombrePosicion(String posicion) {
    switch (posicion) {
      case 'ARQUERO':
        return 'Arquero';
      case 'DEFENSOR':
        return 'Defensor';
      case 'MEDIOCAMPISTA':
        return 'Mediocampista';
      case 'DELANTERO':
        return 'Delantero';
      case 'STAFF_CT':
        return 'Staff CT';
      default:
        return posicion;
    }
  }

  IconData _iconPosicion(String posicion) {
    switch (posicion) {
      case 'ARQUERO':
        return Icons.sports_handball;
      case 'DEFENSOR':
        return Icons.shield;
      case 'MEDIOCAMPISTA':
        return Icons.swap_horiz;
      case 'DELANTERO':
        return Icons.flash_on;
      case 'STAFF_CT':
        return Icons.person;
      default:
        return Icons.sports;
    }
  }
}
