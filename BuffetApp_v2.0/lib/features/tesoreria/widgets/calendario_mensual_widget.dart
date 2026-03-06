import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../data/dao/db.dart';
import '../../../features/shared/format.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../pages/detalle_compromiso_page.dart';

/// Vista de calendario mensual real con celdas coloreadas según estado.
///
/// Colores:
/// - 🔴 Rojo → vencido (ESPERADO + fecha < hoy)
/// - 🟡 Amarillo → vence pronto (ESPERADO + fecha <= hoy+7)
/// - 🟢 Verde → pagado (CONFIRMADO)
/// - 🔵 Azul → pendiente futuro (ESPERADO + fecha > hoy+7)
class CalendarioMensualWidget extends StatefulWidget {
  final int? unidadGestionId;

  const CalendarioMensualWidget({
    super.key,
    this.unidadGestionId,
  });

  @override
  State<CalendarioMensualWidget> createState() =>
      _CalendarioMensualWidgetState();
}

class _CalendarioMensualWidgetState extends State<CalendarioMensualWidget> {
  final _service = CompromisosService.instance;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Cuotas agrupadas por fecha YYYY-MM-DD
  Map<String, List<Map<String, dynamic>>> _cuotasPorDia = {};
  List<Map<String, dynamic>> _cuotasDiaSeleccionado = [];
  bool _isLoading = true;
  String? _error;

  // KPIs
  double _totalHoy = 0;
  double _totalSemana = 0;
  double _totalMes = 0;
  int _vencidosCount = 0;
  int _estaSemanaCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _cargarCuotasMes();
  }

  @override
  void didUpdateWidget(CalendarioMensualWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unidadGestionId != widget.unidadGestionId) {
      _cargarCuotasMes();
    }
  }

  Future<void> _cargarCuotasMes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Pedir un rango amplio: mes actual ± 2 meses
      final primerDia =
          DateTime(_focusedDay.year, _focusedDay.month - 2, 1);
      final ultimoDia =
          DateTime(_focusedDay.year, _focusedDay.month + 3, 0);

      final desde = DateFormat('yyyy-MM-dd').format(primerDia);
      final hasta = DateFormat('yyyy-MM-dd').format(ultimoDia);

      final cuotas = await _service.obtenerCuotasParaCalendario(
        unidadGestionId: widget.unidadGestionId,
        desde: desde,
        hasta: hasta,
      );

      // Agrupar por fecha
      final mapa = <String, List<Map<String, dynamic>>>{};
      for (final c in cuotas) {
        final fecha = c['fecha_programada'] as String? ?? '';
        if (fecha.isEmpty) continue;
        mapa.putIfAbsent(fecha, () => []).add(Map<String, dynamic>.from(c));
      }

      // Calcular KPIs
      final hoy = DateTime.now();
      final hoyStr = DateFormat('yyyy-MM-dd').format(hoy);
      final semanaStr =
          DateFormat('yyyy-MM-dd').format(hoy.add(const Duration(days: 7)));
      final mesInicio =
          DateFormat('yyyy-MM-dd').format(DateTime(hoy.year, hoy.month, 1));
      final mesFin = DateFormat('yyyy-MM-dd')
          .format(DateTime(hoy.year, hoy.month + 1, 0));

      double totalHoy = 0;
      double totalSemana = 0;
      double totalMes = 0;
      int vencidos = 0;
      int estaSemana = 0;

      for (final c in cuotas) {
        final estado = c['cuota_estado'] as String? ?? 'ESPERADO';
        if (estado == 'CONFIRMADO' || estado == 'CANCELADO') continue;

        final fecha = c['fecha_programada'] as String? ?? '';
        final monto = (c['monto_esperado'] as num?)?.toDouble() ?? 0;

        if (fecha == hoyStr) {
          totalHoy += monto;
        }

        if (fecha.compareTo(hoyStr) >= 0 &&
            fecha.compareTo(semanaStr) <= 0) {
          totalSemana += monto;
          estaSemana++;
        }

        if (fecha.compareTo(mesInicio) >= 0 &&
            fecha.compareTo(mesFin) <= 0) {
          totalMes += monto;
        }

        if (fecha.compareTo(hoyStr) < 0) {
          vencidos++;
        }
      }

      if (mounted) {
        setState(() {
          _cuotasPorDia = mapa;
          _totalHoy = totalHoy;
          _totalSemana = totalSemana;
          _totalMes = totalMes;
          _vencidosCount = vencidos;
          _estaSemanaCount = estaSemana;
          _isLoading = false;
        });

        // Cargar cuotas del día seleccionado
        _actualizarDiaSeleccionado();
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'calendario_mensual.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = 'Error al cargar el calendario';
          _isLoading = false;
        });
      }
    }
  }

  void _actualizarDiaSeleccionado() {
    if (_selectedDay == null) return;
    final key = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    setState(() {
      _cuotasDiaSeleccionado = _cuotasPorDia[key] ?? [];
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return _cuotasPorDia[key] ?? [];
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
              onPressed: _cargarCuotasMes,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width > 900;

    return RefreshIndicator(
      onRefresh: _cargarCuotasMes,
      child: isWide ? _buildLayoutDesktop() : _buildLayoutMobile(),
    );
  }

  /// Layout desktop: calendario + detalle del día lado a lado
  Widget _buildLayoutDesktop() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // KPIs arriba
          _buildKPIs(),
          const SizedBox(height: 16),

          // Alertas
          _buildAlertas(),
          const SizedBox(height: 16),

          // Calendario + Detalle del día
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Calendario
              Expanded(
                flex: 3,
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildCalendar(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Detalle del día
              Expanded(
                flex: 2,
                child: _buildDetalleDia(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Layout mobile: calendario + detalle del día apilados
  Widget _buildLayoutMobile() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // KPIs
        _buildKPIs(),
        const SizedBox(height: 12),

        // Alertas
        _buildAlertas(),
        const SizedBox(height: 12),

        // Calendario
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _buildCalendar(),
          ),
        ),
        const SizedBox(height: 12),

        // Detalle del día seleccionado
        _buildDetalleDia(),
      ],
    );
  }

  /// Panel de KPIs: Hoy, Esta semana, Este mes
  Widget _buildKPIs() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildKPIItem(
                'Hoy',
                Format.money(_totalHoy),
                Icons.today,
                Colors.orange,
              ),
            ),
            _dividerVertical(),
            Expanded(
              child: _buildKPIItem(
                'Esta semana',
                Format.money(_totalSemana),
                Icons.date_range,
                Colors.blue,
              ),
            ),
            _dividerVertical(),
            Expanded(
              child: _buildKPIItem(
                'Este mes',
                Format.money(_totalMes),
                Icons.calendar_month,
                Colors.teal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _dividerVertical() {
    return Container(
      width: 1,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.grey.shade300,
    );
  }

  /// Alertas: compromisos vencidos / esta semana
  Widget _buildAlertas() {
    if (_vencidosCount == 0 && _estaSemanaCount == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      color: _vencidosCount > 0 ? Colors.red.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (_vencidosCount > 0) ...[
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_vencidosCount compromiso${_vencidosCount > 1 ? 's' : ''} vencido${_vencidosCount > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (_vencidosCount > 0 && _estaSemanaCount > 0)
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.grey.shade400,
              ),
            if (_estaSemanaCount > 0) ...[
              Icon(Icons.schedule,
                  color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_estaSemanaCount compromiso${_estaSemanaCount > 1 ? 's' : ''} esta semana',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Calendario con table_calendar
  Widget _buildCalendar() {
    final hoy = DateTime.now();
    final hoyStr = DateFormat('yyyy-MM-dd').format(hoy);
    final semanaStr =
        DateFormat('yyyy-MM-dd').format(hoy.add(const Duration(days: 7)));

    return TableCalendar<Map<String, dynamic>>(
      locale: 'es_ES',
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime(2030, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      eventLoader: _getEventsForDay,
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: HeaderStyle(
        formatButtonVisible: true,
        titleCentered: true,
        formatButtonShowsNext: false,
        formatButtonDecoration: BoxDecoration(
          border: Border.all(color: Colors.teal),
          borderRadius: BorderRadius.circular(16),
        ),
        formatButtonTextStyle: const TextStyle(color: Colors.teal),
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: Colors.teal,
          shape: BoxShape.circle,
        ),
        markerDecoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        markersMaxCount: 0,
      ),
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;

          // Determinar color predominante del día
          final color = _colorDia(events, hoyStr, semanaStr);

          return Positioned(
            bottom: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador de color
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (events.length > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    '${events.length}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        defaultBuilder: (context, day, focusedDay) {
          final events = _getEventsForDay(day);
          if (events.isEmpty) return null;

          final color = _colorDia(events, hoyStr, semanaStr);
          final total = _totalDia(events);

          return Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (total > 0)
                  Text(
                    Format.moneyShort(total),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          );
        },
      ),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        _actualizarDiaSeleccionado();
      },
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
        _cargarCuotasMes();
      },
    );
  }

  /// Color predominante de un día según estado de cuotas
  Color _colorDia(
      List<Map<String, dynamic>> cuotas, String hoyStr, String semanaStr) {
    bool tieneVencido = false;
    bool tieneEstaSemana = false;
    bool tieneConfirmado = false;
    bool tienePendiente = false;

    for (final c in cuotas) {
      final estado = c['cuota_estado'] as String? ?? 'ESPERADO';
      final fecha = c['fecha_programada'] as String? ?? '';

      if (estado == 'CONFIRMADO') {
        tieneConfirmado = true;
      } else if (estado == 'CANCELADO') {
        // Ignorar
      } else if (fecha.compareTo(hoyStr) < 0) {
        tieneVencido = true;
      } else if (fecha.compareTo(semanaStr) <= 0) {
        tieneEstaSemana = true;
      } else {
        tienePendiente = true;
      }
    }

    // Prioridad: vencido > esta semana > pendiente > confirmado
    if (tieneVencido) return Colors.red;
    if (tieneEstaSemana) return Colors.orange;
    if (tienePendiente) return Colors.blue;
    if (tieneConfirmado) return Colors.green;
    return Colors.grey;
  }

  double _totalDia(List<Map<String, dynamic>> cuotas) {
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

  /// Detalle del día seleccionado
  Widget _buildDetalleDia() {
    final fechaStr = _selectedDay != null
        ? DateFormat('EEEE d MMMM yyyy', 'es_ES').format(_selectedDay!)
        : '';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header del día
            Row(
              children: [
                Icon(Icons.event, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fechaStr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_cuotasDiaSeleccionado.isNotEmpty)
                  Text(
                    'Total: ${Format.money(_totalDia(_cuotasDiaSeleccionado))}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700,
                    ),
                  ),
              ],
            ),
            const Divider(),

            if (_cuotasDiaSeleccionado.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Sin compromisos este día',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            else
              ..._cuotasDiaSeleccionado.map(_buildCuotaDetalle),
          ],
        ),
      ),
    );
  }

  Widget _buildCuotaDetalle(Map<String, dynamic> cuota) {
    final nombre = cuota['compromiso_nombre'] as String? ?? 'Sin nombre';
    final entidad = cuota['entidad_nombre'] as String?;
    final tipo = cuota['compromiso_tipo'] as String? ?? '';
    final estado = cuota['cuota_estado'] as String? ?? 'ESPERADO';
    final montoEsperado =
        (cuota['monto_esperado'] as num?)?.toDouble() ?? 0;
    final montoReal = (cuota['monto_real'] as num?)?.toDouble();
    final numeroCuota = cuota['numero_cuota'] as int? ?? 0;
    final compromisoId = cuota['compromiso_id'] as int;
    final fecha = cuota['fecha_programada'] as String? ?? '';

    final hoyStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final semanaStr = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().add(const Duration(days: 7)));

    // Color según estado
    Color color;
    IconData icon;
    String estadoLabel;

    if (estado == 'CONFIRMADO') {
      color = Colors.green;
      icon = Icons.check_circle;
      estadoLabel = 'Pagado';
    } else if (estado == 'CANCELADO') {
      color = Colors.grey;
      icon = Icons.cancel;
      estadoLabel = 'Cancelado';
    } else if (fecha.compareTo(hoyStr) < 0) {
      color = Colors.red;
      icon = Icons.error;
      estadoLabel = 'Vencido';
    } else if (fecha.compareTo(semanaStr) <= 0) {
      color = Colors.orange;
      icon = Icons.schedule;
      estadoLabel = 'Vence pronto';
    } else {
      color = Colors.blue;
      icon = Icons.pending;
      estadoLabel = 'Pendiente';
    }

    final esIngreso = tipo == 'INGRESO';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      color: color.withValues(alpha: 0.05),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DetalleCompromisoPage(compromisoId: compromisoId),
            ),
          ).then((result) {
            if (result == true) _cargarCuotasMes();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icono estado
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            estadoLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: (esIngreso ? Colors.green : Colors.red)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            esIngreso ? 'ING' : 'EGR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: esIngreso ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                        if (entidad != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entidad,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (numeroCuota > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Cuota #$numeroCuota',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Monto
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Format.money(montoReal ?? montoEsperado),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: esIngreso ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(Icons.chevron_right,
                      size: 18, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
