import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/dao/db.dart';
import '../../shared/services/plantel_service.dart';
import '../../shared/services/export_service.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../../layout/erp_layout.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/widgets/progress_dialog.dart';
import '../../shared/format.dart';
import '../../shared/state/app_settings.dart';
import '../services/reporte_pdf_service.dart';
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
            backgroundColor: AppColors.egreso,
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
                Icon(Icons.check_circle, color: AppColors.ingreso, size: 32),
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
                const SnackBar(content: Text('No se pudo abrir el archivo. Intente nuevamente.')),
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
            content: const Text('Error al exportar. Intente nuevamente.'),
            backgroundColor: AppColors.egreso,
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
    return ErpLayout(
      title: 'Reporte Mensual de Plantel',
      currentRoute: '/reportes/plantel_mensual',
      actions: [
        if (_entidadesConEstado.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () async {
              try {
                await ReportePdfService.instance.shareReportePlantel(
                  entidades: _entidadesConEstado,
                  resumen: {
                    'totalComprometido': _totalIngresosEsperados,
                    'totalPagado': _totalPagado,
                    'totalPendiente': _totalPendiente,
                  },
                  mes: _mesActual,
                  anio: _anioActual,
                );
              } catch (e, st) {
                await AppDatabase.logLocalError(
                  scope: 'reporte_plantel.export_pdf',
                  error: e,
                  stackTrace: st,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error al generar PDF. Intente nuevamente.')),
                  );
                }
              }
            },
            tooltip: 'Exportar a PDF',
          ),
      ],
      body: ResponsiveContainer(
        maxWidth: 1400,
        child: Column(
          children: [
            _buildCarruselMes(),
            _buildResumenGeneral(),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargarDatos,
                child: _cargando
                    ? SkeletonLoader.table(rows: 5, columns: 4)
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: _entidadesConEstado.isEmpty
                            ? _buildEmpty()
                            : _buildTabla(),
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _entidadesConEstado.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _exportarExcel,
              icon: const Icon(Icons.table_chart),
              label: const Text('Exportar Excel'),
              backgroundColor: AppColors.ingreso,
            )
          : null,
    );
  }

  Widget _buildCarruselMes() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: context.appColors.bgElevated,
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: context.appColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.summarize, color: AppColors.info, size: 20),
              SizedBox(width: 6),
              Text(
                'Resumen General',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  'Comprometido',
                  Format.money(_totalIngresosEsperados),
                  Icons.account_balance_wallet,
                  AppColors.info,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildKpiCard(
                  'Pagado',
                  Format.money(_totalPagado),
                  Icons.check_circle,
                  AppColors.ingreso,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildKpiCard(
                  'Pendiente',
                  Format.money(_totalPendiente),
                  Icons.pending,
                  AppColors.advertencia,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  'Entidades',
                  '${_entidadesConEstado.length}',
                  Icons.people,
                  AppColors.accent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildKpiCard(
                  'Mov. (↓)',
                  Format.money(_totalMovimientosAsociadosIngresos),
                  Icons.arrow_downward,
                  AppColors.ingreso,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildKpiCard(
                  'Mov. (↑)',
                  Format.money(_totalMovimientosAsociadosEgresos),
                  Icons.arrow_upward,
                  AppColors.egreso,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String valor, IconData icono, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: AppDecorations.cardOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 14, color: color),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const EmptyState(
      icon: Icons.calendar_today,
      title: 'No hay movimientos en este mes',
      subtitle: 'Navegá a otro mes usando las flechas',
    );
  }

  Widget _buildTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(context.appColors.bgElevated),
        columns: [
          DataColumn(label: Text('Nombre', style: AppText.label)),
          DataColumn(label: Text('Rol', style: AppText.label)),
          DataColumn(label: Text('Total Mensual', style: AppText.label)),
          DataColumn(label: Text('Pagado', style: AppText.label)),
          DataColumn(label: Text('Pendiente', style: AppText.label)),
          DataColumn(label: Text('Montos Asociados', style: AppText.label)),
          DataColumn(label: Text('Total', style: AppText.label)),
          DataColumn(label: Text('Acciones', style: AppText.label)),
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
                    color: pagado > 0 ? AppColors.ingreso : AppColors.textMuted,
                    fontWeight: pagado > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              DataCell(
                Text(
                  Format.money(esperado),
                  style: TextStyle(
                    color: esperado > 0 ? AppColors.advertencia : AppColors.textMuted,
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
                        style: const TextStyle(color: AppColors.ingreso, fontSize: 11),
                      ),
                    if (movEgresos > 0)
                      Text(
                        '↑ ${Format.money(movEgresos)}',
                        style: const TextStyle(color: AppColors.egreso, fontSize: 11),
                      ),
                    if (movNeto != 0)
                      Text(
                        '= ${Format.money(movNeto)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: movNeto > 0 ? AppColors.ingreso : AppColors.egreso,
                        ),
                      ),
                    if (movIngresos == 0 && movEgresos == 0)
                      Text(
                        '-',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  Format.money(total),
                  style: AppText.monoBold.copyWith(color: AppColors.textPrimary),
                ),
              ),
              DataCell(
                OutlinedButton.icon(
                  onPressed: () => _verDetalle(id),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Ver Detalle', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
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
