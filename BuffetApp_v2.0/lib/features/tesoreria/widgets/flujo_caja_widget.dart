import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/dao/db.dart';
import '../../../features/shared/format.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../pages/detalle_compromiso_page.dart';

/// Vista de flujo de caja: totales por semana + vista semanal detallada.
///
/// Muestra:
/// 1. Resumen por semana del mes (barras horizontales)
/// 2. Vista semanal detallada: cada día de la semana actual con sus compromisos
class FlujoCajaWidget extends StatefulWidget {
  final int? unidadGestionId;

  const FlujoCajaWidget({
    super.key,
    this.unidadGestionId,
  });

  @override
  State<FlujoCajaWidget> createState() => _FlujoCajaWidgetState();
}

class _FlujoCajaWidgetState extends State<FlujoCajaWidget> {
  final _service = CompromisosService.instance;

  bool _isLoading = true;
  String? _error;

  // Mes actual para el resumen mensual
  DateTime _mesActual = DateTime.now();

  // Datos agrupados
  List<_SemanaData> _semanas = [];
  _SemanaData? _semanaSeleccionada;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void didUpdateWidget(FlujoCajaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unidadGestionId != widget.unidadGestionId) {
      _cargarDatos();
    }
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Rango: primer y último día del mes
      final primerDia = DateTime(_mesActual.year, _mesActual.month, 1);
      final ultimoDia = DateTime(_mesActual.year, _mesActual.month + 1, 0);

      final desde = DateFormat('yyyy-MM-dd').format(primerDia);
      final hasta = DateFormat('yyyy-MM-dd').format(ultimoDia);

      final cuotas = await _service.obtenerCuotasParaCalendario(
        unidadGestionId: widget.unidadGestionId,
        desde: desde,
        hasta: hasta,
      );

      // Agrupar por semana del mes
      final semanas = _agruparPorSemana(cuotas, primerDia, ultimoDia);

      // Seleccionar la semana que contiene hoy (si el mes es el actual)
      _SemanaData? seleccionada;
      final hoy = DateTime.now();
      for (final s in semanas) {
        if (!hoy.isBefore(s.inicio) && !hoy.isAfter(s.fin)) {
          seleccionada = s;
          break;
        }
      }
      seleccionada ??= semanas.isNotEmpty ? semanas.first : null;

      if (mounted) {
        setState(() {
          _semanas = semanas;
          _semanaSeleccionada = seleccionada;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'flujo_caja.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = 'Error al cargar el flujo de caja';
          _isLoading = false;
        });
      }
    }
  }

  List<_SemanaData> _agruparPorSemana(
    List<Map<String, dynamic>> cuotas,
    DateTime primerDia,
    DateTime ultimoDia,
  ) {
    final semanas = <_SemanaData>[];

    // Calcular semanas del mes (Lun-Dom)
    // Encontrar primer lunes
    var cursor = primerDia;
    // Retroceder al lunes de la semana del primer día del mes
    while (cursor.weekday != DateTime.monday) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    int semanaNum = 1;
    while (cursor.isBefore(ultimoDia.add(const Duration(days: 1)))) {
      final inicioSemana = cursor;
      final finSemana = cursor.add(const Duration(days: 6));

      final cuotasSemana = <Map<String, dynamic>>[];
      double totalEgresos = 0;
      double totalIngresos = 0;

      for (final c in cuotas) {
        final fechaStr = c['fecha_programada'] as String? ?? '';
        if (fechaStr.isEmpty) continue;

        final fecha = DateTime.tryParse(fechaStr);
        if (fecha == null) continue;

        if (!fecha.isBefore(inicioSemana) && !fecha.isAfter(finSemana)) {
          cuotasSemana.add(c);
          final estado = c['cuota_estado'] as String? ?? 'ESPERADO';
          if (estado == 'CANCELADO') continue;

          final monto = estado == 'CONFIRMADO'
              ? ((c['monto_real'] as num?)?.toDouble() ??
                  (c['monto_esperado'] as num?)?.toDouble() ??
                  0)
              : ((c['monto_esperado'] as num?)?.toDouble() ?? 0);
          final tipo = c['compromiso_tipo'] as String? ?? '';

          if (tipo == 'EGRESO') {
            totalEgresos += monto;
          } else {
            totalIngresos += monto;
          }
        }
      }

      semanas.add(_SemanaData(
        numero: semanaNum,
        inicio: inicioSemana,
        fin: finSemana,
        cuotas: cuotasSemana,
        totalEgresos: totalEgresos,
        totalIngresos: totalIngresos,
      ));

      cursor = cursor.add(const Duration(days: 7));
      semanaNum++;
    }

    return semanas;
  }

  void _cambiarMes(int delta) {
    setState(() {
      _mesActual = DateTime(_mesActual.year, _mesActual.month + delta, 1);
    });
    _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _cargarDatos,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarDatos,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Selector de mes
          _buildSelectorMes(),
          const SizedBox(height: 16),

          // Resumen mensual por semanas (barras)
          _buildResumenSemanal(),
          const SizedBox(height: 16),

          // Detalle de semana seleccionada
          if (_semanaSeleccionada != null) _buildDetalleSemana(),
        ],
      ),
    );
  }

  Widget _buildSelectorMes() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _cambiarMes(-1),
            ),
            Text(
              DateFormat('MMMM yyyy', 'es_ES').format(_mesActual),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _cambiarMes(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenSemanal() {
    if (_semanas.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Sin compromisos este mes',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
        ),
      );
    }

    // Calcular el máximo para las barras proporcionales
    double maxTotal = 0;
    for (final s in _semanas) {
      final total = s.totalEgresos + s.totalIngresos;
      if (total > maxTotal) maxTotal = total;
    }
    if (maxTotal == 0) maxTotal = 1;

    // Totales del mes
    final totalIngMes =
        _semanas.fold(0.0, (sum, s) => sum + s.totalIngresos);
    final totalEgrMes =
        _semanas.fold(0.0, (sum, s) => sum + s.totalEgresos);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Flujo de pagos',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Totales del mes
            Row(
              children: [
                _buildTotalChip('Ingresos', totalIngMes, Colors.green),
                const SizedBox(width: 12),
                _buildTotalChip('Egresos', totalEgrMes, Colors.red),
                const SizedBox(width: 12),
                _buildTotalChip(
                    'Neto', totalIngMes - totalEgrMes,
                    totalIngMes >= totalEgrMes ? Colors.green : Colors.red),
              ],
            ),
            const SizedBox(height: 16),

            // Barras por semana
            ...List.generate(_semanas.length, (i) {
              final s = _semanas[i];
              final total = s.totalEgresos + s.totalIngresos;
              final esSeleccionada = _semanaSeleccionada?.numero == s.numero;

              return InkWell(
                onTap: () => setState(() => _semanaSeleccionada = s),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: esSeleccionada
                        ? Colors.teal.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: esSeleccionada
                        ? Border.all(color: Colors.teal, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Semana ${s.numero}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: esSeleccionada
                                  ? Colors.teal.shade800
                                  : Colors.grey.shade800,
                            ),
                          ),
                          Text(
                            '${DateFormat('dd/MM').format(s.inicio)} - ${DateFormat('dd/MM').format(s.fin)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            Format.money(total),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: esSeleccionada
                                  ? Colors.teal.shade800
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Barra doble: ingresos + egresos
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 12,
                          child: Row(
                            children: [
                              if (s.totalIngresos > 0)
                                Flexible(
                                  flex: (s.totalIngresos / maxTotal * 100)
                                      .round()
                                      .clamp(1, 100),
                                  child: Container(
                                    color: Colors.green.shade400,
                                  ),
                                ),
                              if (s.totalEgresos > 0)
                                Flexible(
                                  flex: (s.totalEgresos / maxTotal * 100)
                                      .round()
                                      .clamp(1, 100),
                                  child: Container(
                                    color: Colors.red.shade400,
                                  ),
                                ),
                              // Relleno
                              if (total < maxTotal)
                                Flexible(
                                  flex:
                                      ((maxTotal - total) / maxTotal * 100)
                                          .round()
                                          .clamp(1, 100),
                                  child: Container(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),
                      // Leyenda ing/egr
                      Row(
                        children: [
                          if (s.totalIngresos > 0) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              Format.moneyShort(s.totalIngresos),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (s.totalEgresos > 0) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              Format.moneyShort(s.totalEgresos),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            '${s.cuotas.length} compromiso${s.cuotas.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalChip(String label, double monto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
          ),
          Text(
            Format.moneyShort(monto),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Detalle de la semana seleccionada: vista día por día
  Widget _buildDetalleSemana() {
    final semana = _semanaSeleccionada!;

    // Agrupar cuotas por día de la semana
    final cuotasPorDia = <int, List<Map<String, dynamic>>>{};
    for (int d = 0; d < 7; d++) {
      cuotasPorDia[d] = [];
    }

    for (final c in semana.cuotas) {
      final fechaStr = c['fecha_programada'] as String? ?? '';
      if (fechaStr.isEmpty) continue;
      final fecha = DateTime.tryParse(fechaStr);
      if (fecha == null) continue;

      final diff = fecha.difference(semana.inicio).inDays;
      if (diff >= 0 && diff < 7) {
        cuotasPorDia[diff]!.add(c);
      }
    }

    final hoy = DateTime.now();
    final hoyStr = DateFormat('yyyy-MM-dd').format(hoy);
    final diasNombre = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.view_week, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Text(
                  'Semana ${semana.numero}: '
                  '${DateFormat('dd/MM').format(semana.inicio)} – '
                  '${DateFormat('dd/MM').format(semana.fin)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ...List.generate(7, (d) {
              final dia = semana.inicio.add(Duration(days: d));
              final diaStr = DateFormat('yyyy-MM-dd').format(dia);
              final esHoy = diaStr == hoyStr;
              final cuotasDia = cuotasPorDia[d] ?? [];

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: esHoy
                      ? Colors.teal.withValues(alpha: 0.06)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: esHoy
                      ? Border.all(color: Colors.teal, width: 1)
                      : Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          diasNombre[d],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: esHoy
                                ? Colors.teal.shade800
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('dd/MM').format(dia),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if (esHoy) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'HOY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (cuotasDia.isNotEmpty)
                          Text(
                            Format.money(_totalCuotas(cuotasDia)),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.teal.shade700,
                            ),
                          ),
                      ],
                    ),

                    if (cuotasDia.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '—',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      ...cuotasDia.map((c) => _buildCuotaMini(c)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCuotaMini(Map<String, dynamic> cuota) {
    final nombre = cuota['compromiso_nombre'] as String? ?? '';
    final tipo = cuota['compromiso_tipo'] as String? ?? '';
    final estado = cuota['cuota_estado'] as String? ?? 'ESPERADO';
    final montoEsperado =
        (cuota['monto_esperado'] as num?)?.toDouble() ?? 0;
    final montoReal = (cuota['monto_real'] as num?)?.toDouble();
    final compromisoId = cuota['compromiso_id'] as int;
    final fecha = cuota['fecha_programada'] as String? ?? '';

    final hoyStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final esIngreso = tipo == 'INGRESO';

    // Determinar color
    Color color;
    if (estado == 'CONFIRMADO') {
      color = Colors.green;
    } else if (fecha.compareTo(hoyStr) < 0) {
      color = Colors.red;
    } else {
      color = Colors.blue;
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DetalleCompromisoPage(compromisoId: compromisoId),
          ),
        ).then((result) {
          if (result == true) _cargarDatos();
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                nombre,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Format.money(montoReal ?? montoEsperado),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: esIngreso ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _totalCuotas(List<Map<String, dynamic>> cuotas) {
    return cuotas.fold(0.0, (sum, c) {
      final estado = c['cuota_estado'] as String? ?? 'ESPERADO';
      if (estado == 'CANCELADO') return sum;
      final monto = estado == 'CONFIRMADO'
          ? ((c['monto_real'] as num?)?.toDouble() ??
              (c['monto_esperado'] as num?)?.toDouble() ??
              0)
          : ((c['monto_esperado'] as num?)?.toDouble() ?? 0);
      return sum + monto;
    });
  }
}

class _SemanaData {
  final int numero;
  final DateTime inicio;
  final DateTime fin;
  final List<Map<String, dynamic>> cuotas;
  final double totalEgresos;
  final double totalIngresos;

  _SemanaData({
    required this.numero,
    required this.inicio,
    required this.fin,
    required this.cuotas,
    required this.totalEgresos,
    required this.totalIngresos,
  });
}
