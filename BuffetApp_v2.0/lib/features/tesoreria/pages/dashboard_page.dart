import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../services/reporte_resumen_service.dart';
import '../services/reporte_categorias_service.dart';
import '../../../data/dao/db.dart';

/// Dashboard visual con gráficos de tesorería.
///
/// Incluye:
/// - Gráfico de torta: distribución de egresos por categoría
/// - Gráfico de barras: ingresos vs egresos mes a mes
/// - Gráfico de línea: evolución del saldo acumulado
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _yearSeleccionado = DateTime.now().year;
  bool _loading = true;
  String? _error;

  // Datos para gráficos
  List<Map<String, dynamic>> _resumenMensual = [];
  List<Map<String, dynamic>> _categoriasEgresos = [];
  Map<String, double> _totales = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = context.read<AppSettings>();
      final unidadId = settings.unidadGestionActivaId;

      // Cargar resumen mensual (barras + línea)
      final mensual = await ReporteResumenService.obtenerResumenMensual(
        year: _yearSeleccionado,
        unidadGestionId: unidadId,
      );

      // Cargar categorías del año completo (torta)
      final inicioAnio = DateTime(_yearSeleccionado, 1, 1);
      final finAnio = DateTime(_yearSeleccionado, 12, 31);
      final categorias = await ReporteCategoriasService.obtenerResumenPorCategoria(
        fechaDesde: inicioAnio,
        fechaHasta: finAnio,
        unidadGestionId: unidadId,
      );
      final totales = await ReporteCategoriasService.obtenerTotalesGenerales(
        fechaDesde: inicioAnio,
        fechaHasta: finAnio,
        unidadGestionId: unidadId,
      );

      // Filtrar solo egresos para la torta
      final soloEgresos = categorias
          .where((c) => ((c['egresos'] as num?)?.toDouble() ?? 0.0) > 0)
          .toList();

      if (mounted) {
        setState(() {
          _resumenMensual = mensual;
          _categoriasEgresos = soloEgresos;
          _totales = totales;
          _loading = false;
        });
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'dashboard.cargar_datos',
        error: e.toString(),
        stackTrace: stack,
      );
      if (mounted) {
        setState(() {
          _error = 'Error al cargar datos del dashboard. Intente nuevamente.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;

    return ErpLayout(
      currentRoute: '/dashboard',
      title: 'Dashboard $_yearSeleccionado',
      body: Column(
        children: [
          Expanded(
            child: _loading
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
                        maxWidth: 1200,
                        child: RefreshIndicator(
                          onRefresh: _cargarDatos,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildSelectorAnio(),
                                const SizedBox(height: 16),
                                _buildKpis(),
                                const SizedBox(height: 24),
                                _buildBarrasIngresosEgresos(),
                                const SizedBox(height: 24),
                                _buildLineaSaldo(),
                                const SizedBox(height: 24),
                                _buildTortaEgresos(),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ───────────── Selector de Año ─────────────
  Widget _buildSelectorAnio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _yearSeleccionado--);
              _cargarDatos();
            },
          ),
          Text(
            '$_yearSeleccionado',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _yearSeleccionado == DateTime.now().year
                ? null
                : () {
                    setState(() => _yearSeleccionado++);
                    _cargarDatos();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() => _yearSeleccionado = DateTime.now().year);
              _cargarDatos();
            },
            tooltip: 'Año actual',
          ),
        ],
      ),
    );
  }

  // ───────────── KPIs ─────────────
  Widget _buildKpis() {
    final ingresos = _totales['ingresos'] ?? 0.0;
    final egresos = _totales['egresos'] ?? 0.0;
    final saldo = _totales['saldo'] ?? (ingresos - egresos);

    return Row(
      children: [
        Expanded(child: _kpiCard('Ingresos', Format.money(ingresos), Colors.green)),
        const SizedBox(width: 8),
        Expanded(child: _kpiCard('Egresos', Format.money(egresos), Colors.red)),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(
            'Resultado',
            Format.money(saldo),
            saldo >= 0 ? Colors.blue : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── Gráfico Barras: Ingresos vs Egresos ─────────────
  Widget _buildBarrasIngresosEgresos() {
    if (_resumenMensual.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxValue = _resumenMensual.fold<double>(0.0, (prev, e) {
      final i = (e['ingresos'] as num?)?.toDouble() ?? 0.0;
      final eg = (e['egresos'] as num?)?.toDouble() ?? 0.0;
      final m = i > eg ? i : eg;
      return m > prev ? m : prev;
    });

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresos vs Egresos por Mes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem('Ingresos', Colors.green.shade400),
                const SizedBox(width: 16),
                _legendItem('Egresos', Colors.red.shade400),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxValue * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final mes = _resumenMensual[groupIndex]['mes'] as int;
                        final mesNombre = DateFormat('MMM', 'es_AR').format(DateTime(_yearSeleccionado, mes));
                        final tipo = rodIndex == 0 ? 'Ingresos' : 'Egresos';
                        return BarTooltipItem(
                          '$mesNombre\n$tipo: ${Format.money(rod.toY)}',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _resumenMensual.length) {
                            return const SizedBox.shrink();
                          }
                          final mes = _resumenMensual[idx]['mes'] as int;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormat('MMM', 'es_AR').format(DateTime(_yearSeleccionado, mes)),
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
                          if (value == 0) return const SizedBox.shrink();
                          return Text(
                            _formatCompact(value),
                            style: const TextStyle(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxValue > 0 ? maxValue / 4 : 1,
                  ),
                  barGroups: List.generate(_resumenMensual.length, (index) {
                    final dato = _resumenMensual[index];
                    final ing = (dato['ingresos'] as num?)?.toDouble() ?? 0.0;
                    final egr = (dato['egresos'] as num?)?.toDouble() ?? 0.0;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: ing,
                          color: Colors.green.shade400,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                        BarChartRodData(
                          toY: egr,
                          color: Colors.red.shade400,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── Gráfico Línea: Saldo Acumulado ─────────────
  Widget _buildLineaSaldo() {
    if (_resumenMensual.isEmpty) {
      return const SizedBox.shrink();
    }

    final spots = _resumenMensual.asMap().entries.map((entry) {
      final saldoAcum = (entry.value['saldo_acumulado'] as num?)?.toDouble() ?? 0.0;
      return FlSpot(entry.key.toDouble(), saldoAcum);
    }).toList();

    final minY = spots.fold<double>(0, (prev, s) => s.y < prev ? s.y : prev);
    final maxY = spots.fold<double>(0, (prev, s) => s.y > prev ? s.y : prev);
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
              'Evolución del Saldo Acumulado',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: minY - padding,
                  maxY: maxY + padding,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((s) {
                          final idx = s.x.toInt();
                          if (idx < 0 || idx >= _resumenMensual.length) return null;
                          final mes = _resumenMensual[idx]['mes'] as int;
                          final mesNombre = DateFormat('MMM', 'es_AR').format(DateTime(_yearSeleccionado, mes));
                          return LineTooltipItem(
                            '$mesNombre\n${Format.money(s.y)}',
                            const TextStyle(color: Colors.white, fontSize: 11),
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
                          if (idx < 0 || idx >= _resumenMensual.length) {
                            return const SizedBox.shrink();
                          }
                          final mes = _resumenMensual[idx]['mes'] as int;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormat('MMM', 'es_AR').format(DateTime(_yearSeleccionado, mes)),
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
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                      left: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: Colors.indigo,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.indigo.withValues(alpha: 0.1),
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

  // ───────────── Gráfico Torta: Egresos por Categoría ─────────────
  Widget _buildTortaEgresos() {
    if (_categoriasEgresos.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Distribución de Egresos por Categoría',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'No hay egresos registrados en $_yearSeleccionado',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    final colors = [
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.amber.shade400,
      Colors.teal.shade400,
      Colors.blue.shade400,
      Colors.purple.shade400,
      Colors.pink.shade400,
      Colors.brown.shade400,
      Colors.cyan.shade400,
      Colors.lime.shade400,
      Colors.indigo.shade400,
      Colors.deepOrange.shade400,
    ];

    final totalEgresos = _categoriasEgresos.fold<double>(
      0.0,
      (prev, c) => prev + ((c['egresos'] as num?)?.toDouble() ?? 0.0),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Distribución de Egresos por Categoría',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  // Torta
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 35,
                        sections: List.generate(
                          _categoriasEgresos.length > 10 ? 10 : _categoriasEgresos.length,
                          (index) {
                            final cat = _categoriasEgresos[index];
                            final egreso = (cat['egresos'] as num?)?.toDouble() ?? 0.0;
                            final porcentaje = totalEgresos > 0
                                ? (egreso / totalEgresos * 100)
                                : 0.0;
                            return PieChartSectionData(
                              color: colors[index % colors.length],
                              value: egreso,
                              title: '${porcentaje.toStringAsFixed(0)}%',
                              titleStyle: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              radius: 55,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Leyenda
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(
                          _categoriasEgresos.length > 10 ? 10 : _categoriasEgresos.length,
                          (index) {
                            final cat = _categoriasEgresos[index];
                            final nombre = cat['categoria']?.toString() ?? 'Sin cat.';
                            final egreso = (cat['egresos'] as num?)?.toDouble() ?? 0.0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: colors[index % colors.length],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      nombre,
                                      style: const TextStyle(fontSize: 10),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    Format.money(egreso),
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── Helpers ─────────────
  Widget _legendItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  /// Formatea números grandes de forma compacta (ej: 1.5M, 250K).
  String _formatCompact(double value) {
    if (value.abs() >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }
}
