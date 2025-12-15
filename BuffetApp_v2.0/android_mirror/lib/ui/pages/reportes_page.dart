import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../state/reportes_model.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});
  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  final model = ReportesModel();

  @override
  void initState() {
    super.initState();
    model.inicializar();
    model.addListener(_onModelChange);
  }

  @override
  void dispose() {
    model.removeListener(_onModelChange);
    model.dispose();
    super.dispose();
  }

  void _onModelChange() => setState(() {});
  // Método obsoleto eliminado (_pickDesde)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: model.loading && model.serie.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => model.cargarDatos(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _filtros(),
                  const SizedBox(height: 16),
                  _barChart(),
                  const SizedBox(height: 16),
                  _kpis(),
                  const SizedBox(height: 16),
                  _ventasPorMetodo(),
                  const SizedBox(height: 16),
                  _rankingProductos(),
                ],
              ),
            ),
    );
  }

  Widget _barChart() {
    final isDia = model.agregacion == AggregacionFecha.dia && model.desde != null && model.hasta != null && model.desde == model.hasta;
    final sinDatos = (
      (isDia && model.disciplinaDiaVentas.isEmpty) ||
      (!isDia && model.agregacion == AggregacionFecha.mes && model.diaDisciplinaMes.isEmpty) ||
      (!isDia && model.agregacion == AggregacionFecha.anio && model.serie.isEmpty)
    );
    if (sinDatos) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDia
                  ? 'Ventas por Disciplina (día)'
                  : (model.agregacion == AggregacionFecha.mes
                      ? 'Ventas Diarias por Disciplina (Mes)'
                      : 'Ventas Mensuales (Año)'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _calendarInline(),
              const SizedBox(height: 12),
              const Text('Sin datos disponibles para el rango seleccionado.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    late final double maxTotal;
    final List<BarChartGroupData> groups = [];

    if (isDia) {
      maxTotal = model.disciplinaDiaVentas.map((e) => e.total).fold<double>(0, (p, c) => c > p ? c : p);
      for (var i = 0; i < model.disciplinaDiaVentas.length; i++) {
        final d = model.disciplinaDiaVentas[i];
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: d.total,
                color: model.disciplinaColor[d.disciplina] ?? Colors.grey,
                width: 18,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      }
    } else {
      if (model.agregacion == AggregacionFecha.mes) {
        // barras por día desagregadas por disciplina
        final dias = model.diaDisciplinaMes.keys.toList()..sort((a,b)=>a.compareTo(b));
        double tmpMax = 0;
        for (var i = 0; i < dias.length; i++) {
          final dia = dias[i];
          final lista = model.diaDisciplinaMes[dia]!;
          final rods = <BarChartRodData>[];
          double sumDia = 0;
          for (final d in lista) {
            sumDia += d.total;
            rods.add(BarChartRodData(
              toY: d.total,
              color: model.disciplinaColor[d.disciplina] ?? Colors.grey,
              width: 14,
              borderRadius: BorderRadius.circular(2),
            ));
          }
          if (sumDia > tmpMax) tmpMax = sumDia;
          groups.add(BarChartGroupData(x: i, barRods: rods));
        }
        maxTotal = tmpMax;
      } else { // año (mensual)
        maxTotal = model.serie.map((e) => e.totalVentas).fold<double>(0, (p, c) => c > p ? c : p);
        for (var i = 0; i < model.serie.length; i++) {
          final p = model.serie[i];
          groups.add(
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: p.totalVentas,
                  color: Colors.green.shade600,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          );
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                isDia
                  ? 'Ventas por Disciplina (día)'
                  : (model.agregacion == AggregacionFecha.mes
                    ? 'Ventas Diarias por Disciplina (Mes)'
                    : 'Ventas Mensuales (Año)'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _calendarInline(),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chart = BarChart(
                    BarChartData(
                      maxY: maxTotal * 1.15,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: maxTotal == 0 ? 1 : maxTotal / 4,
                            getTitlesWidget: (value, meta) => Text(
                              value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}K' : value.toStringAsFixed(0),
                              style: const TextStyle(fontSize: 10),
                            ),
                            reservedSize: 42,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (isDia) {
                                if (idx < 0 || idx >= model.disciplinaDiaVentas.length) return const SizedBox.shrink();
                                final label = model.disciplinaDiaVentas[idx].disciplina;
                                return SizedBox(
                                  width: 70,
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 10),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                );
                              } else if (model.agregacion == AggregacionFecha.mes) {
                                final dias = model.diaDisciplinaMes.keys.toList()..sort((a,b)=>a.compareTo(b));
                                if (idx < 0 || idx >= dias.length) return const SizedBox.shrink();
                                final label = dias[idx].day.toString().padLeft(2,'0');
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              } else {
                                if (idx < 0 || idx >= model.serie.length) return const SizedBox.shrink();
                                final label = model.serie[idx].periodo;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(label, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                                );
                              }
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      barGroups: groups,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBgColor: Colors.black87,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (isDia) {
                              final d = model.disciplinaDiaVentas[group.x.toInt()];
                              return BarTooltipItem(
                                '${d.disciplina}\n${_fmtMoney(rod.toY)}',
                                const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            } else if (model.agregacion == AggregacionFecha.mes) {
                              final dias = model.diaDisciplinaMes.keys.toList()..sort((a,b)=>a.compareTo(b));
                              final dia = dias[group.x.toInt()];
                              return BarTooltipItem(
                                '${dia.day.toString().padLeft(2,'0')}\n${_fmtMoney(rod.toY)}',
                                const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            } else {
                              final periodo = model.serie[group.x.toInt()].periodo;
                              return BarTooltipItem(
                                '$periodo\n${_fmtMoney(rod.toY)}',
                                const TextStyle(color: Colors.white, fontSize: 12),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  );
                  // Calcular posiciones aproximadas para labels encima de barras
                  final count = groups.length;
                  final labels = <Widget>[];
                  final usableWidth = constraints.maxWidth - 16; // margen aproximado
                  for (var i = 0; i < count; i++) {
                    final g = groups[i];
                    // Para agrupados por disciplina (mes) mostrar label con suma del día sobre las barras
                    final value = model.agregacion == AggregacionFecha.mes
                        ? g.barRods.fold<double>(0, (p,c)=>p + c.toY)
                        : g.barRods.first.toY;
                    final text = _fmtMoney(value);
                    final xRatio = (i + 1) / (count + 1); // spaceAround aproximado
                    final topRatio = value <= 0 ? 1.0 : (1 - (value / (maxTotal * 1.15)));
                    labels.add(Positioned(
                      left: 8 + usableWidth * xRatio - 30,
                      top: 10 + (constraints.maxHeight - 40) * topRatio,
                      width: 60,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            text,
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ));
                  }
                  return Stack(children: [chart, ...labels]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtros', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              DropdownButton<AggregacionFecha>(
                value: model.agregacion,
                onChanged: (val) {
                  if (val == null) return;
                  if (val == AggregacionFecha.mes) {
                    model.seleccionarMes(model.currentMonth);
                  } else if (val == AggregacionFecha.anio) {
                    model.seleccionarAnio(model.currentMonth.year);
                  } else if (val == AggregacionFecha.dia) {
                    final firstDay = DateTime(model.currentMonth.year, model.currentMonth.month, 1);
                    model.seleccionarDia(firstDay);
                  }
                },
                items: AggregacionFecha.values.map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<String?> (
                  isExpanded: true,
                  value: model.disciplina,
                  hint: const Text('Disciplina (filtrar caja)'),
                  onChanged: (v) => model.actualizarFiltros(nuevaDisciplina: v),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ...model.disciplinasDisponibles.map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  ],
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _calendarInline() {
    // Vista anual
    if (model.agregacion == AggregacionFecha.anio) {
      final year = model.currentMonth.year;
      final meses = List.generate(12, (i) => DateTime(year, i + 1, 1));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => model.seleccionarAnio(year - 1),
                tooltip: 'Año anterior',
              ),
              Expanded(
                child: Center(
                  child: Text('$year', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => model.seleccionarAnio(year + 1),
                tooltip: 'Año siguiente',
              ),
            ],
          ),
          const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: meses.map((m) {
                final isSelected = model.agregacion == AggregacionFecha.mes && model.desde != null && model.desde!.month == m.month && model.desde!.year == m.year;
                return InkWell(
                  onTap: () => model.seleccionarMes(m),
                  child: Container(
                    width: 70,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blueGrey.shade700 : Colors.blueGrey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _nombreMes(m.month).substring(0,3),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      );
    }
    // Vista mensual (días)
    final first = model.currentMonth;
    final nextMonth = DateTime(first.year, first.month + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;
    final firstWeekday = first.weekday;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: model.prevMonth,
              tooltip: 'Mes anterior',
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_nombreMes(model.currentMonth.month)} ${model.currentMonth.year}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: model.nextMonth,
              tooltip: 'Mes siguiente',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: const [
            _CalHeader(label: 'Lu'),
            _CalHeader(label: 'Ma'),
            _CalHeader(label: 'Mi'),
            _CalHeader(label: 'Ju'),
            _CalHeader(label: 'Vi'),
            _CalHeader(label: 'Sa'),
            _CalHeader(label: 'Do'),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (int i = 1; i < firstWeekday; i++) const SizedBox(width: 40, height: 40),
            for (int d = 1; d <= daysInMonth; d++) _calDay(d),
          ],
        ),
        const SizedBox(height: 6),
        _leyendaDisciplinas(),
      ],
    );
  }

  Widget _calDay(int day) {
    final date = DateTime(model.currentMonth.year, model.currentMonth.month, day);
    final disciplinas = model.disciplinasPorFecha[date];
    final has = disciplinas != null && disciplinas.isNotEmpty;
    final isSelectedDia = model.desde != null && model.agregacion == AggregacionFecha.dia && _sameDay(model.desde!, date);
    final isSelectedMes = model.desde != null && model.agregacion == AggregacionFecha.mes && model.desde!.month == date.month && model.desde!.year == date.year;
    final isSelected = isSelectedDia || isSelectedMes;
    return InkWell(
      onTap: () {
        if (model.agregacion == AggregacionFecha.mes) {
          if (has) model.seleccionarDia(date);
        } else if (model.agregacion == AggregacionFecha.dia) {
          if (has) model.seleccionarDia(date);
        }
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueGrey.shade700 : (has ? Colors.blueGrey.shade100 : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blueGrey.shade300, width: 0.6),
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            // horizontal calendar not using cells var
            if (has)
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: disciplinas.take(3).map((disc) {
                  final col = model.disciplinaColor[disc] ?? Colors.grey;
                  return Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle));
                }).toList(),
              )
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _nombreMes(int m) {
    const nombres = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    return nombres[m - 1];
  }

  Widget _leyendaDisciplinas() {
    if (model.disciplinaColor.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: model.disciplinaColor.entries.map((e) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: e.value, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(e.key, style: const TextStyle(fontSize: 11)),
          ],
        );
      }).toList(),
    );
  }
  // (continúa dentro de la clase)

  Widget _kpis() {
    final k = model.kpis;
    if (k == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('KPIs', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _kpiTile('Total Ventas', _fmtMoney(k.totalVentas)),
                _kpiTile('Venta Promedio', _fmtMoney(k.ticketPromedio)),
                _kpiTile('Cant Ventas', k.cantidadVentas.toString()),
                _kpiTile('Entradas', k.totalEntradas.toString()),
                _kpiTile('Tickets Emitidos', k.ticketsEmitidos.toString()),
                _kpiTile('Tickets Anulados', k.ticketsAnulados.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiTile(String label, String value) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _fmtMoney(double v) => '\$${v.toStringAsFixed(0)}';
  String _fmtNumber(double v, {int decimals = 1}) => v.toStringAsFixed(decimals);

  Widget _ventasPorMetodo() {
    if (model.ventasPorMetodo.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ventas por Método de Pago', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...model.ventasPorMetodo.map((m) => ListTile(
                  dense: true,
                  title: Text(m.metodo),
                  trailing: Text(_fmtMoney(m.importe)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _rankingProductos() {
    if (model.rankingProductos.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Productos (promedio unidades por caja)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...model.rankingProductos.map((p) {
                  final cajas = model.cajasEnFiltro;
                  final promedio = cajas > 0 ? (p.unidades / cajas) : 0.0;
                  return ListTile(
                    dense: true,
                    title: Text('${p.nombre}: ${_fmtMoney(p.importe)}'),
                    subtitle: Text('Promedio unidades vendidas: ${_fmtNumber(promedio, decimals: 2)} (sobre ${cajas} caja/s filtradas) (Totales: ${p.unidades})'),
                  );
                }),
          ],
        ),
      ),
    );
  }
}

class _CalHeader extends StatelessWidget {
  final String label;
  const _CalHeader({required this.label, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}