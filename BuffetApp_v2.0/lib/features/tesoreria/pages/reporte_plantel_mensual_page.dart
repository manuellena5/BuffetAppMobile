import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../data/dao/db.dart';
import '../../shared/services/plantel_service.dart';
import '../../shared/services/export_service.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import '../../shared/widgets/progress_dialog.dart';
import '../../shared/format.dart';
import '../../shared/state/app_settings.dart';
import 'detalle_movimientos_entidad_page.dart';

/// FASE 35: Reporte mensual de estado de pagos por entidad (jugador/staff CT)
/// Muestra tabla con columnas: Nombre, Rol, Total Mensual, Pagado, Pendiente, Total
/// Permite navegar mes a mes y exportar a Excel
class ReportePlantelMensualPage extends StatefulWidget {
  const ReportePlantelMensualPage({super.key});

  @override
  State<ReportePlantelMensualPage> createState() => _ReportePlantelMensualPageState();
}

class _ReportePlantelMensualPageState extends State<ReportePlantelMensualPage> {
  final _plantelSvc = PlantelService.instance;
  final _exportSvc = ExportService();

  bool _cargando = true;
  int _mesActual = DateTime.now().month;
  int _anioActual = DateTime.now().year;

  // Datos cargados
  List<Map<String, dynamic>> _entidadesConEstado = [];
  
  // Resumen general
  double _totalIngresosEsperados = 0.0;
  double _totalPagado = 0.0;
  double _totalPendiente = 0.0;
  double _totalMovimientosAsociadosIngresos = 0.0;
  double _totalMovimientosAsociadosEgresos = 0.0;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    
    try {
      final settings = context.read<AppSettings>();
      final unidadGestionId = settings.unidadGestionActivaId;
      
      if (unidadGestionId == null) {
        if (mounted) {
          setState(() => _cargando = false);
        }
        return;
      }

      // Cargar todas las entidades activas
      final entidades = await _plantelSvc.listarEntidades(soloActivos: true);

      // Calcular estado económico de cada entidad para el mes actual
      final entidadesConEstado = <Map<String, dynamic>>[];
      double sumaIngresosEsperados = 0.0;
      double sumaPagado = 0.0;
      double sumaPendiente = 0.0;
      double sumaMovAsociadosIngresos = 0.0;
      double sumaMovAsociadosEgresos = 0.0;

      for (final entidad in entidades) {
        try {
          final id = entidad['id'] as int;
          final estado = await _plantelSvc.calcularEstadoMensualPorEntidad(
            id,
            _anioActual,
            _mesActual,
          );

          final totalComprometido = (estado['totalComprometido'] as num?)?.toDouble() ?? 0.0;
          final pagado = (estado['pagado'] as num?)?.toDouble() ?? 0.0;
          final esperado = (estado['esperado'] as num?)?.toDouble() ?? 0.0;
          final movAsociados = await _plantelSvc.calcularMovimientosAsociadosPorEntidad(
            id,
            _anioActual,
            _mesActual,
          );
          final movIngreso = movAsociados['ingresos'] ?? 0.0;
          final movEgreso = movAsociados['egresos'] ?? 0.0;

          // Solo incluir entidades que tengan movimientos en el mes
          if (totalComprometido > 0 || pagado > 0 || movIngreso > 0 || movEgreso > 0) {
            entidadesConEstado.add({
              ...entidad,
              'totalComprometido': totalComprometido,
              'pagado': pagado,
              'esperado': esperado,
              'movimientos_ingresos': movIngreso,
              'movimientos_egresos': movEgreso,
              'movimientos_neto': movIngreso - movEgreso,
            });

            // Acumular totales
            sumaIngresosEsperados += totalComprometido;
            sumaPagado += pagado;
            sumaPendiente += esperado;
            sumaMovAsociadosIngresos += movIngreso;
            sumaMovAsociadosEgresos += movEgreso;
            sumaPagado += pagado;
            sumaPendiente += esperado;
          }
        } catch (e, stack) {
          await AppDatabase.logLocalError(
            scope: 'reporte_plantel.cargar_estado_entidad',
            error: e,
            stackTrace: stack,
            payload: {'entidad_id': entidad['id']},
          );
        }
      }

      if (mounted) {
        setState(() {
          _entidadesConEstado = entidadesConEstado;
          _totalIngresosEsperados = sumaIngresosEsperados;
          _totalPagado = sumaPagado;
          _totalPendiente = sumaPendiente;
          _totalMovimientosAsociadosIngresos = sumaMovAsociadosIngresos;
          _totalMovimientosAsociadosEgresos = sumaMovAsociadosEgresos;
        });
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'reporte_plantel.cargar_datos',
        error: e,
        stackTrace: stack,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar datos. Por favor, intente nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _mesSiguiente() {
    setState(() {
      if (_mesActual == 12) {
        _mesActual = 1;
        _anioActual++;
      } else {
        _mesActual++;
      }
    });
    _cargarDatos();
  }

  void _mesAnterior() {
    setState(() {
      if (_mesActual == 1) {
        _mesActual = 12;
        _anioActual--;
      } else {
        _mesActual--;
      }
    });
    _cargarDatos();
  }

  Future<void> _exportarExcel() async {
    if (_entidadesConEstado.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar')),
      );
      return;
    }

    if (!mounted) return;
    ProgressDialog.show(context, 'Generando archivo Excel...');

    try {
      final mesStr = _mesActual.toString().padLeft(2, '0');
      final filename = 'plantel_mensual_$_anioActual-$mesStr';

      final savedPath = await _exportSvc.exportPlantelMensualExcel(
        entidades: _entidadesConEstado,
        mes: _mesActual,
        anio: _anioActual,
        totalComprometido: _totalIngresosEsperados,
        totalPagado: _totalPagado,
        totalPendiente: _totalPendiente,
        filename: filename,
      );

      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo de progreso

        final abrir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 32),
                SizedBox(width: 12),
                Text('Excel Generado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('El archivo se guardó correctamente.'),
                const SizedBox(height: 8),
                Text(
                  savedPath,
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir'),
              ),
            ],
          ),
        );

        if (abrir == true) {
          try {
            await OpenFilex.open(savedPath);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('No se pudo abrir el archivo: $e')),
              );
            }
          }
        }
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'reporte_plantel.exportar_excel',
        error: e,
        stackTrace: stack,
      );

      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo de progreso
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _verDetalle(int entidadId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleMovimientosEntidadPage(
          entidadId: entidadId,
          mesInicial: _mesActual,
          anioInicial: _anioActual,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TesoreriaScaffold(
      title: 'Reporte Mensual de Plantel',
      currentRouteName: '/reportes/plantel_mensual',
      appBarColor: Colors.blue,
      body: ResponsiveContainer(
        maxWidth: 1400,
        child: RefreshIndicator(
          onRefresh: _cargarDatos,
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      _buildCarruselMes(),
                      _buildResumenGeneral(),
                      const Divider(),
                      _entidadesConEstado.isEmpty
                          ? _buildEmpty()
                          : _buildTabla(),
                    ],
                  ),
                ),
        ),
      ),
      floatingActionButton: _entidadesConEstado.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _exportarExcel,
              icon: const Icon(Icons.table_chart),
              label: const Text('Exportar Excel'),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  Widget _buildCarruselMes() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: Colors.blue.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 32),
            onPressed: _cargando ? null : _mesAnterior,
            tooltip: 'Mes anterior',
          ),
          Text(
            '${_nombreMes(_mesActual)} $_anioActual',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 32),
            onPressed: _cargando ? null : _mesSiguiente,
            tooltip: 'Mes siguiente',
          ),
        ],
      ),
    );
  }

  Widget _buildResumenGeneral() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.summarize, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Text(
                'Resumen General',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  'Total Comprometido',
                  Format.money(_totalIngresosEsperados),
                  Icons.account_balance_wallet,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  'Pagado',
                  Format.money(_totalPagado),
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
                  Format.money(_totalPendiente),
                  Icons.pending,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  'Entidades',
                  '${_entidadesConEstado.length}',
                  Icons.people,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  'Mov. Asociados (↓)',
                  Format.money(_totalMovimientosAsociadosIngresos),
                  Icons.arrow_downward,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  'Mov. Asociados (↑)',
                  Format.money(_totalMovimientosAsociadosEgresos),
                  Icons.arrow_upward,
                  Colors.red,
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No hay movimientos en este mes',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Navegá a otro mes usando las flechas',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(Colors.blue.shade100),
        columns: const [
          DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Rol', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total Mensual', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Pagado', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Pendiente', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Montos Asociados', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _entidadesConEstado.map((entidad) {
          final id = entidad['id'] as int;
          final nombre = entidad['nombre']?.toString() ?? 'Sin nombre';
          final rol = entidad['rol']?.toString() ?? 'OTRO';
          final totalComprometido = (entidad['totalComprometido'] as num?)?.toDouble() ?? 0.0;
          final pagado = (entidad['pagado'] as num?)?.toDouble() ?? 0.0;
          final esperado = (entidad['esperado'] as num?)?.toDouble() ?? 0.0;
          final movIngresos = (entidad['movimientos_ingresos'] as num?)?.toDouble() ?? 0.0;
          final movEgresos = (entidad['movimientos_egresos'] as num?)?.toDouble() ?? 0.0;
          final movNeto = movIngresos - movEgresos;
          final total = pagado + esperado;

          return DataRow(
            cells: [
              DataCell(Text(nombre)),
              DataCell(Text(_nombreRol(rol))),
              DataCell(Text(Format.money(totalComprometido))),
              DataCell(
                Text(
                  Format.money(pagado),
                  style: TextStyle(
                    color: pagado > 0 ? Colors.green.shade700 : Colors.grey.shade600,
                    fontWeight: pagado > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              DataCell(
                Text(
                  Format.money(esperado),
                  style: TextStyle(
                    color: esperado > 0 ? Colors.orange.shade700 : Colors.grey.shade600,
                    fontWeight: esperado > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (movIngresos > 0)
                      Text(
                        '↓ ${Format.money(movIngresos)}',
                        style: const TextStyle(color: Colors.green, fontSize: 11),
                      ),
                    if (movEgresos > 0)
                      Text(
                        '↑ ${Format.money(movEgresos)}',
                        style: const TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    if (movNeto != 0)
                      Text(
                        '= ${Format.money(movNeto)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: movNeto > 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    if (movIngresos == 0 && movEgresos == 0)
                      Text(
                        '-',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  Format.money(total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(
                ElevatedButton.icon(
                  onPressed: () => _verDetalle(id),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Ver Detalle', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
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
}
