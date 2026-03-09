import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme/app_theme.dart';
import '../features/shared/format.dart';

/// Dato mensual para el gráfico de proyección.
class ProyeccionMes {
  final String label;       // Ej. "Ene", "Feb"
  final double ingresosPrometidos;
  final double ingresosCobrados;
  final double egresosPrometidos;
  final double egresosPagados;
  final bool esPasado;      // true si el mes ya terminó

  const ProyeccionMes({
    required this.label,
    required this.ingresosPrometidos,
    required this.ingresosCobrados,
    required this.egresosPrometidos,
    required this.egresosPagados,
    required this.esPasado,
  });

  double get resultado => ingresosPrometidos - egresosPrometidos;
}

/// Gráfico de barras dobles: prometido vs cobrado/pagado por mes.
///
/// Reutilizable en Acuerdos, Dashboard y Reportes.
/// Muestra 4 barras por mes: ingresos prometidos/cobrados y egresos prometidos/pagados.
/// Incluye tooltip al hacer tap/hover y totales en la parte inferior.
class ProyeccionBarChart extends StatefulWidget {
  final List<ProyeccionMes> datos;
  final String? titulo;
  final String? subtitulo;

  const ProyeccionBarChart({
    super.key,
    required this.datos,
    this.titulo,
    this.subtitulo,
  });

  @override
  State<ProyeccionBarChart> createState() => _ProyeccionBarChartState();
}

class _ProyeccionBarChartState extends State<ProyeccionBarChart> {
  double get _maxVal {
    double m = 0;
    for (final d in widget.datos) {
      if (d.ingresosPrometidos > m) m = d.ingresosPrometidos;
      if (d.egresosPrometidos > m) m = d.egresosPrometidos;
    }
    return m == 0 ? 1 : m;
  }

  @override
  Widget build(BuildContext context) {
    final datos = widget.datos;
    if (datos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.appColors.border),
        boxShadow: AppShadows.cardFor(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + leyenda
          _buildHeader(),
          const SizedBox(height: AppSpacing.xl),

          // Barras
          SizedBox(
            height: 180,
            child: _buildBarras(datos),
          ),

          // Totales
          const SizedBox(height: AppSpacing.lg),
          _buildTotales(datos),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.titulo != null)
                Text(widget.titulo!, style: AppText.titleMd),
              if (widget.subtitulo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(widget.subtitulo!, style: AppText.caption),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            _leyendaItem(AppColors.ingreso, 'Ing. prometidos'),
            _leyendaItem(AppColors.ingreso.withValues(alpha: 0.35), 'Cobrado'),
            _leyendaItem(AppColors.egreso, 'Egr. prometidos'),
            _leyendaItem(AppColors.egreso.withValues(alpha: 0.35), 'Pagado'),
          ],
        ),
      ],
    );
  }

  Widget _leyendaItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.caption),
      ],
    );
  }

  Widget _buildBarras(List<ProyeccionMes> datos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barGroupWidth = constraints.maxWidth / datos.length;
        final barWidth = (barGroupWidth - 12) / 4; // 4 barras + gaps

        return BarChart(
          BarChartData(
            maxY: _maxVal * 1.05,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => context.appColors.bgElevated,
                tooltipBorder: BorderSide(color: context.appColors.border),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm,
                ),
                getTooltipItem: (group, groupIdx, rod, rodIdx) {
                  if (groupIdx >= datos.length) return null;
                  final d = datos[groupIdx];
                  // Solo mostrar en la primera barra del grupo
                  if (rodIdx != 0) return null;
                  return BarTooltipItem(
                    '${d.label}\n',
                    AppText.titleSm,
                    children: [
                      TextSpan(
                        text: '↑ Prometido: ${Format.moneyNoDecimals(d.ingresosPrometidos)}\n',
                        style: AppText.bodySm.copyWith(color: AppColors.ingreso),
                      ),
                      TextSpan(
                        text: '↑ Cobrado: ${Format.moneyNoDecimals(d.ingresosCobrados)}\n',
                        style: AppText.bodySm.copyWith(color: AppColors.ingresoLight),
                      ),
                      TextSpan(
                        text: '↓ Prometido: ${Format.moneyNoDecimals(d.egresosPrometidos)}\n',
                        style: AppText.bodySm.copyWith(color: AppColors.egreso),
                      ),
                      TextSpan(
                        text: '↓ Pagado: ${Format.moneyNoDecimals(d.egresosPagados)}\n',
                        style: AppText.bodySm.copyWith(color: AppColors.egresoLight),
                      ),
                      TextSpan(
                        text: 'Resultado: ${Format.moneyNoDecimals(d.resultado)}',
                        style: AppText.titleSm.copyWith(
                          color: d.resultado >= 0 ? AppColors.ingreso : AppColors.egreso,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= datos.length) {
                      return const SizedBox.shrink();
                    }
                    final d = datos[idx];
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        d.label,
                        style: AppText.label.copyWith(
                          color: d.esPasado ? context.appColors.textMuted : context.appColors.textDisabled,
                          fontWeight: d.esPasado ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(datos.length, (i) {
              final d = datos[i];
              final opacityMult = d.esPasado ? 1.0 : 0.45;
              final bw = barWidth.clamp(3.0, 16.0);

              return BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  // Ingresos prometidos
                  BarChartRodData(
                    toY: d.ingresosPrometidos,
                    color: AppColors.ingreso.withValues(alpha: opacityMult),
                    width: bw,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    backDrawRodData: BackgroundBarChartRodData(show: false),
                  ),
                  // Ingresos cobrados
                  BarChartRodData(
                    toY: d.ingresosCobrados,
                    color: AppColors.ingreso.withValues(alpha: 0.35),
                    width: bw,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                  // Egresos prometidos
                  BarChartRodData(
                    toY: d.egresosPrometidos,
                    color: AppColors.egreso.withValues(alpha: opacityMult),
                    width: bw,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                  // Egresos pagados
                  BarChartRodData(
                    toY: d.egresosPagados,
                    color: AppColors.egreso.withValues(alpha: 0.35),
                    width: bw,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              );
            }),
          ),
          duration: const Duration(milliseconds: 300),
        );
      },
    );
  }

  Widget _buildTotales(List<ProyeccionMes> datos) {
    final totalIngProm = datos.fold(0.0, (s, d) => s + d.ingresosPrometidos);
    final totalIngCob = datos.fold(0.0, (s, d) => s + d.ingresosCobrados);
    final totalEgrProm = datos.fold(0.0, (s, d) => s + d.egresosPrometidos);
    final totalEgrPag = datos.fold(0.0, (s, d) => s + d.egresosPagados);

    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: _totalItem('Total ing. prom.', totalIngProm, AppColors.ingreso)),
          Expanded(child: _totalItem('Total cobrado', totalIngCob, AppColors.ingresoLight)),
          Expanded(child: _totalItem('Total egr. prom.', totalEgrProm, AppColors.egreso)),
          Expanded(child: _totalItem('Total pagado', totalEgrPag, AppColors.egresoLight)),
        ],
      ),
    );
  }

  Widget _totalItem(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.sm,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: context.appColors.bgBase,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label),
          const SizedBox(height: 4),
          Text(Format.moneyNoDecimals(value),
              style: AppText.kpiSm.copyWith(color: color)),
        ],
      ),
    );
  }
}
