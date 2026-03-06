import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../services/proyeccion_flujo_service.dart';
import '../../../data/dao/db.dart';

/// Pantalla de proyección de flujo de caja a 1, 3 y 6 meses.
///
/// Muestra:
/// - KPIs con saldo proyectado a distintos horizontes
/// - Tabla mes a mes con compromisos, presupuesto y saldo proyectado
/// - Gráfico de línea con evolución del saldo
class ProyeccionFlujoPage extends StatefulWidget {
  const ProyeccionFlujoPage({super.key});

  @override
  State<ProyeccionFlujoPage> createState() => _ProyeccionFlujoPageState();
}

class _ProyeccionFlujoPageState extends State<ProyeccionFlujoPage> {
  final _service = ProyeccionFlujoService.instance;

  int? _unidadGestionId;
  String? _unidadNombre;
  int _mesesFuturos = 6;

  List<Map<String, dynamic>> _proyeccion = [];
  Map<String, double> _resumen = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      final settings = context.read<AppSettings>();
      _unidadGestionId = settings.unidadGestionActivaId;

      if (_unidadGestionId != null) {
        final db = await AppDatabase.instance();
        final rows = await db.query('unidades_gestion',
            columns: ['nombre'],
            where: 'id=?',
            whereArgs: [_unidadGestionId],
            limit: 1);
        if (rows.isNotEmpty) {
          _unidadNombre = rows.first['nombre']?.toString();
        }
      }
    } catch (_) {}

    await _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    if (_unidadGestionId == null) {
      setState(() {
        _proyeccion = [];
        _resumen = {};
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final proyeccion = await _service.calcularProyeccion(
        unidadGestionId: _unidadGestionId!,
        mesesFuturos: _mesesFuturos,
      );

      final resumen = await _service.resumenRapido(
        unidadGestionId: _unidadGestionId!,
      );

      if (mounted) {
        setState(() {
          _proyeccion = proyeccion;
          _resumen = resumen;
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'proyeccion_flujo_page.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = 'Error al calcular proyección. Intente nuevamente.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TesoreriaScaffold(
      title: 'Proyección Flujo de Caja',
      currentRouteName: '/reportes/proyeccion_flujo',
      appBarColor: Colors.deepOrange,
      body: _loading
          ? SkeletonLoader.cards(count: 3)
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  iconColor: Colors.red,
                  title: _error!,
                  action: ElevatedButton.icon(
                    onPressed: _cargarDatos,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                )
              : ResponsiveContainer(
                  maxWidth: 1000,
                  child: RefreshIndicator(
                    onRefresh: _cargarDatos,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (_unidadNombre != null) _buildUnidadHeader(),
                          const SizedBox(height: 12),
                          _buildHorizonteSelector(),
                          const SizedBox(height: 16),
                          _buildKpis(),
                          const SizedBox(height: 20),
                          _buildGrafico(),
                          const SizedBox(height: 20),
                          _buildTabla(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildUnidadHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _unidadNombre!,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.purple,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─────────── Selector horizonte ───────────
  Widget _buildHorizonteSelector() {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 3, label: Text('3 meses')),
        ButtonSegment(value: 6, label: Text('6 meses')),
        ButtonSegment(value: 12, label: Text('12 meses')),
      ],
      selected: {_mesesFuturos},
      onSelectionChanged: (val) {
        setState(() => _mesesFuturos = val.first);
        _cargarDatos();
      },
    );
  }

  // ─────────── KPIs ───────────
  Widget _buildKpis() {
    final saldoActual = _resumen['saldo_actual'] ?? 0.0;
    final saldo1m = _resumen['saldo_1m'] ?? 0.0;
    final saldo3m = _resumen['saldo_3m'] ?? 0.0;
    final saldo6m = _resumen['saldo_6m'] ?? 0.0;

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            'Actual',
            Format.money(saldoActual),
            saldoActual >= 0 ? Colors.blue : Colors.red,
            Icons.account_balance_wallet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            '+1 mes',
            Format.money(saldo1m),
            saldo1m >= 0 ? Colors.green : Colors.red,
            Icons.trending_flat,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            '+3 meses',
            Format.money(saldo3m),
            saldo3m >= 0 ? Colors.green : Colors.red,
            Icons.trending_up,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            '+6 meses',
            Format.money(saldo6m),
            saldo6m >= 0 ? Colors.green : Colors.red,
            Icons.double_arrow,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Gráfico ───────────
  Widget _buildGrafico() {
    if (_proyeccion.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];

    // Punto 0 = saldo actual
    final saldoActual = _resumen['saldo_actual'] ?? 0.0;
    spots.add(FlSpot(0, saldoActual));

    for (var i = 0; i < _proyeccion.length; i++) {
      final saldo =
          (_proyeccion[i]['saldo_proyectado'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot((i + 1).toDouble(), saldo));
    }

    final allY = spots.map((s) => s.y).toList();
    final minY = allY.reduce((a, b) => a < b ? a : b);
    final maxY = allY.reduce((a, b) => a > b ? a : b);
    final range = (maxY - minY).abs();
    final padding = range > 0 ? range * 0.15 : 1000;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evolución Proyectada del Saldo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: minY - padding,
                  maxY: maxY + padding,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((s) {
                          final idx = s.x.toInt();
                          String label;
                          if (idx == 0) {
                            label = 'Hoy';
                          } else if (idx <= _proyeccion.length) {
                            final p = _proyeccion[idx - 1];
                            final m = p['mes'] as int;
                            final a = p['anio'] as int;
                            label = DateFormat('MMM yy', 'es_AR')
                                .format(DateTime(a, m));
                          } else {
                            label = '';
                          }
                          return LineTooltipItem(
                            '$label\n${Format.money(s.y)}',
                            const TextStyle(
                                color: Colors.white, fontSize: 11),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: range > 0 ? range / 4 : 1,
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx == 0) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child:
                                  Text('Hoy', style: TextStyle(fontSize: 10)),
                            );
                          }
                          if (idx < 1 || idx > _proyeccion.length) {
                            return const SizedBox.shrink();
                          }
                          final p = _proyeccion[idx - 1];
                          final m = p['mes'] as int;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormat('MMM', 'es_AR')
                                  .format(DateTime(_proyeccion[idx - 1]['anio'] as int, m)),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 55,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            _formatCompact(value),
                            style: const TextStyle(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                      left: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  // Línea horizontal en y=0
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 0,
                        color: Colors.grey.shade400,
                        strokeWidth: 1,
                        dashArray: [5, 3],
                      ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.deepOrange,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          final isNegative = spot.y < 0;
                          return FlDotCirclePainter(
                            radius: 4,
                            color: isNegative ? Colors.red : Colors.white,
                            strokeWidth: 2,
                            strokeColor: Colors.deepOrange,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.deepOrange.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Tabla detalle ───────────
  Widget _buildTabla() {
    if (_proyeccion.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalle Mensual',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(Colors.deepOrange.shade50),
                border:
                    TableBorder.all(color: Colors.grey.shade300, width: 1),
                columnSpacing: 14,
                columns: const [
                  DataColumn(
                      label: Text('Mes',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Saldo Inicio',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('Ing. Proy.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('Egr. Proy.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('Saldo Proy.',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                ],
                rows: _proyeccion.map((p) {
                  final mes = p['mes'] as int;
                  final anio = p['anio'] as int;
                  final mesNombre = DateFormat('MMM yy', 'es_AR')
                      .format(DateTime(anio, mes));
                  final saldoInicio =
                      (p['saldo_inicio_mes'] as num?)?.toDouble() ?? 0.0;
                  final ingProy =
                      (p['ingresos_proyectados'] as num?)?.toDouble() ?? 0.0;
                  final egrProy =
                      (p['egresos_proyectados'] as num?)?.toDouble() ?? 0.0;
                  final saldoProy =
                      (p['saldo_proyectado'] as num?)?.toDouble() ?? 0.0;

                  return DataRow(cells: [
                    DataCell(Text(
                      '${mesNombre[0].toUpperCase()}${mesNombre.substring(1)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(
                      Format.money(saldoInicio),
                      style: TextStyle(
                        fontSize: 12,
                        color: saldoInicio >= 0 ? Colors.blue : Colors.red,
                      ),
                    )),
                    DataCell(Text(
                      Format.money(ingProy),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.green),
                    )),
                    DataCell(Text(
                      Format.money(egrProy),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.red),
                    )),
                    DataCell(Text(
                      Format.money(saldoProy),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: saldoProy >= 0 ? Colors.blue : Colors.red,
                      ),
                    )),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fuentes: compromisos esperados + presupuesto mensual como respaldo',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCompact(double value) {
    if (value.abs() >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }
}
