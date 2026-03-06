import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/format.dart';
import '../../../data/dao/db.dart';
import '../pages/detalle_compromiso_page.dart';

/// Widget que muestra un timeline/calendario de cuotas próximas y vencidas.
///
/// Agrupa las cuotas por sección:
/// - 🔴 Vencidas (fecha < hoy, estado ESPERADO)
/// - 🟡 Esta semana (hoy <= fecha <= hoy+7)
/// - 🔵 Próximas (hoy+8 <= fecha <= +60 días)
/// - ✅ Confirmadas recientes (últimos 30 días, estado CONFIRMADO)
class CalendarioPagosWidget extends StatefulWidget {
  final int? unidadGestionId;

  const CalendarioPagosWidget({
    super.key,
    this.unidadGestionId,
  });

  @override
  State<CalendarioPagosWidget> createState() => _CalendarioPagosWidgetState();
}

class _CalendarioPagosWidgetState extends State<CalendarioPagosWidget> {
  final _service = CompromisosService.instance;
  List<Map<String, dynamic>> _cuotas = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCuotas();
  }

  @override
  void didUpdateWidget(CalendarioPagosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unidadGestionId != widget.unidadGestionId) {
      _cargarCuotas();
    }
  }

  Future<void> _cargarCuotas() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cuotas = await _service.obtenerCuotasParaCalendario(
        unidadGestionId: widget.unidadGestionId,
      );

      if (mounted) {
        setState(() {
          _cuotas = cuotas;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'calendario_pagos.cargar',
        error: e.toString(),
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _error = 'Error al cargar el calendario de pagos';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
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
              onPressed: _cargarCuotas,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_cuotas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No hay cuotas en el periodo',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Se muestran cuotas de los últimos 30 días y próximos 60 días',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hoy = DateTime.now();
    final hoyStr = DateFormat('yyyy-MM-dd').format(hoy);
    final semanaStr =
        DateFormat('yyyy-MM-dd').format(hoy.add(const Duration(days: 7)));

    // Clasificar cuotas
    final vencidas = <Map<String, dynamic>>[];
    final estaSemana = <Map<String, dynamic>>[];
    final proximas = <Map<String, dynamic>>[];
    final confirmadas = <Map<String, dynamic>>[];

    for (final cuota in _cuotas) {
      final estado = cuota['cuota_estado'] as String? ?? 'ESPERADO';
      final fecha = cuota['fecha_programada'] as String? ?? '';

      if (estado == 'CONFIRMADO') {
        confirmadas.add(cuota);
      } else if (estado == 'CANCELADO') {
        // Ignorar canceladas
      } else if (fecha.compareTo(hoyStr) < 0) {
        vencidas.add(cuota);
      } else if (fecha.compareTo(semanaStr) <= 0) {
        estaSemana.add(cuota);
      } else {
        proximas.add(cuota);
      }
    }

    return RefreshIndicator(
      onRefresh: _cargarCuotas,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Resumen rápido
          _buildResumen(vencidas, estaSemana, proximas, confirmadas),
          const SizedBox(height: 16),

          // Vencidas
          if (vencidas.isNotEmpty) ...[
            _buildSeccionHeader(
              'Vencidas',
              Icons.warning_amber_rounded,
              Colors.red,
              vencidas.length,
              _calcularTotal(vencidas),
            ),
            ...vencidas
                .map((c) => _buildCuotaCard(c, _CuotaEstadoVisual.vencida)),
            const SizedBox(height: 16),
          ],

          // Esta semana
          if (estaSemana.isNotEmpty) ...[
            _buildSeccionHeader(
              'Esta semana',
              Icons.schedule,
              Colors.orange,
              estaSemana.length,
              _calcularTotal(estaSemana),
            ),
            ...estaSemana
                .map((c) => _buildCuotaCard(c, _CuotaEstadoVisual.estaSemana)),
            const SizedBox(height: 16),
          ],

          // Próximas
          if (proximas.isNotEmpty) ...[
            _buildSeccionHeader(
              'Próximas',
              Icons.event_note,
              Colors.blue,
              proximas.length,
              _calcularTotal(proximas),
            ),
            ...proximas
                .map((c) => _buildCuotaCard(c, _CuotaEstadoVisual.proxima)),
            const SizedBox(height: 16),
          ],

          // Confirmadas recientes
          if (confirmadas.isNotEmpty) ...[
            _buildSeccionHeader(
              'Confirmadas recientemente',
              Icons.check_circle,
              Colors.green,
              confirmadas.length,
              _calcularTotalConfirmado(confirmadas),
            ),
            ...confirmadas
                .map((c) => _buildCuotaCard(c, _CuotaEstadoVisual.confirmada)),
          ],
        ],
      ),
    );
  }

  double _calcularTotal(List<Map<String, dynamic>> cuotas) {
    return cuotas.fold(0.0,
        (sum, c) => sum + ((c['monto_esperado'] as num?)?.toDouble() ?? 0));
  }

  double _calcularTotalConfirmado(List<Map<String, dynamic>> cuotas) {
    return cuotas.fold(0.0, (sum, c) {
      final real = (c['monto_real'] as num?)?.toDouble();
      final esperado = (c['monto_esperado'] as num?)?.toDouble() ?? 0;
      return sum + (real ?? esperado);
    });
  }

  Widget _buildResumen(
    List<Map<String, dynamic>> vencidas,
    List<Map<String, dynamic>> estaSemana,
    List<Map<String, dynamic>> proximas,
    List<Map<String, dynamic>> confirmadas,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Resumen de pagos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (vencidas.isNotEmpty)
                  _buildResumenChip(
                    '${vencidas.length} vencida${vencidas.length > 1 ? 's' : ''}',
                    Colors.red,
                    Format.money(_calcularTotal(vencidas)),
                  ),
                if (estaSemana.isNotEmpty)
                  _buildResumenChip(
                    '${estaSemana.length} esta semana',
                    Colors.orange,
                    Format.money(_calcularTotal(estaSemana)),
                  ),
                _buildResumenChip(
                  '${proximas.length} próxima${proximas.length != 1 ? 's' : ''}',
                  Colors.blue,
                  Format.money(_calcularTotal(proximas)),
                ),
                if (confirmadas.isNotEmpty)
                  _buildResumenChip(
                    '${confirmadas.length} pagada${confirmadas.length > 1 ? 's' : ''}',
                    Colors.green,
                    Format.money(_calcularTotalConfirmado(confirmadas)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenChip(String label, Color color, String monto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            monto,
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

  Widget _buildSeccionHeader(
      String titulo, IconData icon, Color color, int count, double total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const Spacer(),
          Text(
            Format.money(total),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuotaCard(
      Map<String, dynamic> cuota, _CuotaEstadoVisual visual) {
    final nombre = cuota['compromiso_nombre'] as String? ?? 'Sin nombre';
    final entidad = cuota['entidad_nombre'] as String?;
    final tipo = cuota['compromiso_tipo'] as String? ?? '';
    final fecha = cuota['fecha_programada'] as String? ?? '';
    final montoEsperado = (cuota['monto_esperado'] as num?)?.toDouble() ?? 0;
    final montoReal = (cuota['monto_real'] as num?)?.toDouble();
    final numeroCuota = cuota['numero_cuota'] as int? ?? 0;
    final estado = cuota['cuota_estado'] as String? ?? 'ESPERADO';
    final acuerdoId = cuota['acuerdo_id'];
    final compromisoId = cuota['compromiso_id'] as int;

    final esIngreso = tipo == 'INGRESO';
    final colorTipo = esIngreso ? Colors.green : Colors.red;

    // Calcular días de diferencia con hoy
    DateTime? fechaDt;
    String diasLabel = '';
    try {
      fechaDt = DateTime.parse(fecha);
      final diff = fechaDt.difference(DateTime.now()).inDays;
      if (estado == 'CONFIRMADO') {
        diasLabel = 'Pagado';
      } else if (diff < 0) {
        diasLabel = '${-diff} día${diff == -1 ? '' : 's'} de atraso';
      } else if (diff == 0) {
        diasLabel = 'HOY';
      } else if (diff == 1) {
        diasLabel = 'Mañana';
      } else {
        diasLabel = 'En $diff días';
      }
    } catch (_) {}

    Color borderColor;
    Color bgColor;
    switch (visual) {
      case _CuotaEstadoVisual.vencida:
        borderColor = Colors.red.shade300;
        bgColor = Colors.red.shade50;
      case _CuotaEstadoVisual.estaSemana:
        borderColor = Colors.orange.shade300;
        bgColor = Colors.orange.shade50;
      case _CuotaEstadoVisual.proxima:
        borderColor = Colors.blue.shade200;
        bgColor = Colors.blue.shade50;
      case _CuotaEstadoVisual.confirmada:
        borderColor = Colors.green.shade200;
        bgColor = Colors.green.shade50;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      color: bgColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _navegarADetalle(compromisoId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Timeline dot
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: borderColor.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '#$numeroCuota',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: borderColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Contenido
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (acuerdoId != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.handshake,
                                size: 14, color: Colors.purple.shade400),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Fecha
                        Text(
                          fechaDt != null
                              ? DateFormat('dd/MM/yyyy').format(fechaDt)
                              : fecha,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Días
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: borderColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            diasLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: borderColor,
                            ),
                          ),
                        ),
                        if (entidad != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entidad,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Monto
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Format.money(montoReal ?? montoEsperado),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: colorTipo,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorTipo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      esIngreso ? 'ING' : 'EGR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorTipo,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navegarADetalle(int compromisoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleCompromisoPage(compromisoId: compromisoId),
      ),
    ).then((result) {
      if (result == true) _cargarCuotas();
    });
  }
}

enum _CuotaEstadoVisual { vencida, estaSemana, proxima, confirmada }
