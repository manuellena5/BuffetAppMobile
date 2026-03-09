import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/dao/evento_dao.dart';
import '../../../features/shared/services/movimiento_service.dart';
import '../../../layout/erp_layout.dart';
import '../../shared/format.dart';
import '../../shared/widgets/breadcrumb.dart';

/// Pantalla de asistencia de jugadores a un partido.
/// Para cada jugador con acuerdo POR_EVENTO en la unidad, permite registrar
/// si jugó de TITULAR, SUPLENTE o NO_JUGO, y genera los movimientos correspondientes.
class AsistenciaPartidoPage extends StatefulWidget {
  final Map<String, dynamic> evento;
  final int unidadGestionId;

  const AsistenciaPartidoPage({
    super.key,
    required this.evento,
    required this.unidadGestionId,
  });

  @override
  State<AsistenciaPartidoPage> createState() => _AsistenciaPartidoPageState();
}

class _AsistenciaPartidoPageState extends State<AsistenciaPartidoPage> {
  List<Map<String, dynamic>> _acuerdosJugadores = [];
  List<Map<String, dynamic>> _asistenciaActual = [];
  // condicion actual (puede ser editada por el usuario)
  final Map<int, String> _condiciones = {};
  // condicion que ya fue confirmada y tiene movimiento generado
  final Map<int, String> _condicionesConfirmadas = {};
  // id del movimiento existente por jugador (null = sin movimiento aún)
  final Map<int, int?> _movimientoIds = {};
  bool _cargando = true;
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarDatos());
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final eventoId = widget.evento['id'] as int;
      final acuerdos = await EventoDao.getAcuerdosPorPartido(widget.unidadGestionId);
      final asistencia = await EventoDao.getAsistenciaByEvento(eventoId);

      // Pre-cargar condiciones y estado confirmado desde asistencia existente
      final condicionesIniciales = <int, String>{};
      final condicionesConfirmadas = <int, String>{};
      final movimientoIds = <int, int?>{};
      for (final a in asistencia) {
        final entidadId = a['entidad_plantel_id'] as int?;
        final condicion = a['condicion'] as String?;
        final movId = a['movimiento_id'] as int?;
        if (entidadId != null) {
          if (condicion != null) {
            condicionesIniciales[entidadId] = condicion;
            // Solo se considera "confirmado" si tiene movimiento generado
            // (o condicion NO_JUGO que no genera movimiento pero sí fue registrada)
            condicionesConfirmadas[entidadId] = condicion;
          }
          movimientoIds[entidadId] = movId;
        }
      }

      if (!mounted) return;
      setState(() {
        _acuerdosJugadores = acuerdos;
        _asistenciaActual = asistencia;
        _condiciones.addAll(condicionesIniciales);
        _condicionesConfirmadas
          ..clear()
          ..addAll(condicionesConfirmadas);
        _movimientoIds
          ..clear()
          ..addAll(movimientoIds);
        _cargando = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'asistencia_partido.cargar',
        error: e.toString(),
        stackTrace: st,
        payload: {'evento_id': widget.evento['id']},
      );
      if (mounted) setState(() => _cargando = false);
    }
  }

  double _montoParaCondicion(Map<String, dynamic> acuerdo, String condicion) {
    switch (condicion) {
      case 'TITULAR':
        return (acuerdo['monto_titular'] as num?)?.toDouble() ?? 0.0;
      case 'SUPLENTE':
        return (acuerdo['monto_suplente'] as num?)?.toDouble() ?? 0.0;
      case 'NO_JUGO':
        return (acuerdo['monto_no_jugo'] as num?)?.toDouble() ?? 0.0;
      default:
        return 0.0;
    }
  }

  int get _jugadoresAsignados => _condiciones.values.where((c) => c != 'NO_JUGO').length;

  double get _totalEstimado => _acuerdosJugadores.fold(0.0, (s, a) {
        final entidadId = a['entidad_plantel_id'] as int?;
        if (entidadId == null) return s;
        final condicion = _condiciones[entidadId];
        if (condicion == null) return s;
        return s + _montoParaCondicion(a, condicion);
      });

  // Jugadores con condicion nueva o modificada respecto al estado confirmado
  List<MapEntry<int, String>> get _cambiosPendientes {
    return _condiciones.entries.where((e) {
      final entidadId = e.key;
      final condicion = e.value;
      final confirmada = _condicionesConfirmadas[entidadId];
      // Es un cambio si: nunca fue confirmado, o la condicion cambió
      return confirmada == null || condicion != confirmada;
    }).toList();
  }

  Future<void> _confirmarAsistencia() async {
    final cambios = _cambiosPendientes;

    if (cambios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios pendientes que guardar.')),
      );
      return;
    }

    // Jugadores con cambio que realmente generan/modifican movimiento
    final conMovimiento = cambios.where((e) {
      final acuerdo = _acuerdosJugadores
          .firstWhere((a) => a['entidad_plantel_id'] == e.key, orElse: () => {});
      return e.value != 'NO_JUGO' && _montoParaCondicion(acuerdo, e.value) > 0;
    }).toList();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar asistencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${cambios.length} jugador(es) con cambios a procesar.'),
            const SizedBox(height: 8),
            Text('Total estimado: ${Format.money(_totalEstimado)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Se crearán o modificarán movimientos según la condición seleccionada.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _confirmando = true);
    final eventoId = widget.evento['id'] as int;
    final errores = <String>[];

    try {
      for (final acuerdo in _acuerdosJugadores) {
        final entidadId = acuerdo['entidad_plantel_id'] as int?;
        if (entidadId == null) continue;
        final condicion = _condiciones[entidadId];
        if (condicion == null) continue;

        // Sin cambios → saltar
        final condicionConfirmada = _condicionesConfirmadas[entidadId];
        if (condicionConfirmada != null && condicion == condicionConfirmada) continue;

        final monto = _montoParaCondicion(acuerdo, condicion);
        final acuerdoId = acuerdo['id'] as int?;
        final movimientoIdExistente = _movimientoIds[entidadId];
        final nombreJugador = acuerdo['nombre'] as String? ?? '';
        final labelCondicion = condicion == 'TITULAR'
            ? 'Titular'
            : condicion == 'SUPLENTE'
                ? 'Suplente'
                : 'No jugó';
        final observacion = '$labelCondicion — $nombreJugador';

        try {
          // 1. Upsert asistencia
          await EventoDao.upsertAsistencia({
            'evento_id': eventoId,
            'entidad_plantel_id': entidadId,
            'condicion': condicion,
            'acuerdo_id': acuerdoId,
          });

          // 2. Manejo del movimiento según situación
          final svc = EventoMovimientoService();

          if (movimientoIdExistente != null) {
            // Ya tiene movimiento existente → actualizar o eliminar
            if (condicion == 'NO_JUGO' && monto == 0) {
              // Soft-delete: ya no corresponde un pago
              await svc.eliminar(movimientoIdExistente);
              await EventoDao.updateMovimientoIdAsistencia(
                eventoId: eventoId,
                entidadPlantelId: entidadId,
                movimientoId: null,
              );
            } else {
              // Actualizar monto, condicion y observacion
              await svc.actualizar(
                id: movimientoIdExistente,
                disciplinaId: widget.unidadGestionId,
                unidadGestionId: widget.unidadGestionId,
                cuentaId: acuerdo['cuenta_id'] as int? ?? 1,
                tipo: 'EGRESO',
                categoria: acuerdo['categoria'] as String? ?? 'SUELDO',
                monto: monto,
                medioPagoId: acuerdo['medio_pago_id'] as int? ?? 1,
                entidadPlantelId: entidadId,
                eventoCdmId: eventoId,
                condicion: condicion,
                acuerdoId: acuerdoId,
                observacion: observacion,
              );
            }
          } else if (condicion != 'NO_JUGO' && monto > 0) {
            // Sin movimiento previo → crear nuevo
            final movId = await svc.crear(
              disciplinaId: widget.unidadGestionId,
              unidadGestionId: widget.unidadGestionId,
              cuentaId: acuerdo['cuenta_id'] as int? ?? 1,
              tipo: 'EGRESO',
              categoria: acuerdo['categoria'] as String? ?? 'SUELDO',
              monto: monto,
              medioPagoId: acuerdo['medio_pago_id'] as int? ?? 1,
              entidadPlantelId: entidadId,
              eventoCdmId: eventoId,
              acuerdoId: acuerdoId,
              condicion: condicion,
              observacion: observacion,
            );
            await EventoDao.updateMovimientoIdAsistencia(
              eventoId: eventoId,
              entidadPlantelId: entidadId,
              movimientoId: movId,
            );
          }
          // Si condicion == 'NO_JUGO' y sin movimiento previo → solo el upsert alcanza
        } catch (e, st) {
          errores.add(nombreJugador.isNotEmpty ? nombreJugador : 'Jugador #$entidadId');
          await AppDatabase.logLocalError(
            scope: 'asistencia_partido.confirmar_jugador',
            error: e.toString(),
            stackTrace: st,
            payload: {'entidad_id': entidadId, 'condicion': condicion, 'evento_id': eventoId},
          );
        }
      }

      if (!mounted) return;

      final exitosos = cambios.length - errores.length;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(
              errores.isEmpty ? Icons.check_circle : Icons.warning,
              color: errores.isEmpty ? AppColors.ingreso : AppColors.advertencia,
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text('Asistencia guardada'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$exitosos jugador(es) procesados correctamente.'),
              if (errores.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Errores: ${errores.join(', ')}',
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 8),
              Text('Total: ${Format.money(_totalEstimado)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aceptar')),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'asistencia_partido.confirmar',
        error: e.toString(),
        stackTrace: st,
        payload: {'evento_id': eventoId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al confirmar asistencia. Revisá los logs e intentá nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.evento['titulo'] as String? ?? 'Partido';

    return ErpLayout(
      currentRoute: '/asistencia_partido',
      title: 'Asistencia — $titulo',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Breadcrumb(
              items: [
                BreadcrumbItem(
                  label: 'Eventos',
                  icon: Icons.event,
                  onTap: () => Navigator.of(context).popUntil(
                    (route) => route.settings.name == '/eventos_cdm' || route.isFirst,
                  ),
                ),
                BreadcrumbItem(
                  label: titulo,
                  icon: Icons.sports_soccer,
                  onTap: () => Navigator.of(context).pop(),
                ),
                BreadcrumbItem(label: 'Asistencia'),
              ],
            ),
          ),
          _buildResumenBar(),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_acuerdosJugadores.isEmpty)
            Expanded(child: _buildEstadoVacio())
          else
            Expanded(child: _buildListaJugadores()),
          _buildBotonConfirmar(),
        ],
      ),
    );
  }

  Widget _buildResumenBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Row(
        children: [
          Icon(Icons.people_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('${_acuerdosJugadores.length} jugadores con acuerdo POR PARTIDO',
              style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text('Total: ${Format.money(_totalEstimado)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildListaJugadores() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _acuerdosJugadores.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        try {
          final acuerdo = _acuerdosJugadores[index];
          final entidadId = acuerdo['entidad_plantel_id'] as int?;
          if (entidadId == null) return const SizedBox.shrink();
          return _JugadorAsistenciaCard(
            acuerdo: acuerdo,
            condicionSeleccionada: _condiciones[entidadId],
            condicionConfirmada: _condicionesConfirmadas[entidadId],
            onCondicionChanged: (condicion) {
              setState(() => _condiciones[entidadId] = condicion);
            },
          );
        } catch (e, st) {
          AppDatabase.logLocalError(
            scope: 'asistencia_partido.render_jugador',
            error: e.toString(),
            stackTrace: st,
            payload: {'index': index},
          );
          return const Card(
            child: ListTile(leading: Icon(Icons.warning), title: Text('Error al mostrar jugador')),
          );
        }
      },
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Sin acuerdos POR PARTIDO',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'No hay jugadores con acuerdos de tipo "Por Partido" para esta Unidad de Gestión.\n'
              'Creá un acuerdo POR PARTIDO desde la sección Acuerdos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonConfirmar() {
    final pendientes = _cambiosPendientes.length;
    final habilitado = pendientes > 0 && !_confirmando;
    final label = _confirmando
        ? 'Guardando...'
        : pendientes > 0
            ? 'Guardar cambios ($pendientes jugador${pendientes == 1 ? '' : 'es'})'
            : 'Sin cambios pendientes';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FilledButton.icon(
        onPressed: habilitado ? _confirmarAsistencia : null,
        icon: _confirmando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.all(16),
          backgroundColor: AppColors.ingreso,
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
    );
  }
}

// ─── Card de jugador ───

class _JugadorAsistenciaCard extends StatelessWidget {
  final Map<String, dynamic> acuerdo;
  final String? condicionSeleccionada;
  final String? condicionConfirmada;
  final ValueChanged<String> onCondicionChanged;

  const _JugadorAsistenciaCard({
    required this.acuerdo,
    required this.condicionSeleccionada,
    required this.condicionConfirmada,
    required this.onCondicionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = acuerdo['nombre'] as String? ?? '–';
    final rol = acuerdo['rol'] as String? ?? '–';
    final montoTitular = (acuerdo['monto_titular'] as num?)?.toDouble() ?? 0.0;
    final montoSuplente = (acuerdo['monto_suplente'] as num?)?.toDouble() ?? 0.0;
    final montoNoJugo = (acuerdo['monto_no_jugo'] as num?)?.toDouble() ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(rol, style: AppText.caption),
                    ],
                  ),
                ),
                if (condicionSeleccionada != null)
                  Text(
                    Format.money(_montoParaCondicion(condicionSeleccionada!)),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: condicionSeleccionada == 'NO_JUGO' ? Colors.grey : AppColors.egreso,
                    ),
                  ),
                if (condicionConfirmada != null) ...[
                  const SizedBox(width: 6),
                  _buildEstadoBadge(),
                ],
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final btnWidth = (constraints.maxWidth - 16) / 3;
                return Row(
                  children: [
                    _buildCondicionBtn('TITULAR', '🟢 Titular\n${Format.money(montoTitular)}',
                        btnWidth, AppColors.ingreso),
                    const SizedBox(width: 8),
                    _buildCondicionBtn('SUPLENTE', '🟡 Suplente\n${Format.money(montoSuplente)}',
                        btnWidth, AppColors.advertencia),
                    const SizedBox(width: 8),
                    _buildCondicionBtn('NO_JUGO', '⚫ No jugó\n${Format.money(montoNoJugo)}',
                        btnWidth, Colors.grey),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoBadge() {
    final hayModificacion =
        condicionSeleccionada != null && condicionSeleccionada != condicionConfirmada;
    final color = hayModificacion ? AppColors.advertencia : AppColors.ingreso;
    final icon = hayModificacion ? Icons.edit : Icons.check_circle_outline;
    final label = hayModificacion ? 'Modificar' : 'Confirmado';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  double _montoParaCondicion(String condicion) {
    switch (condicion) {
      case 'TITULAR':
        return (acuerdo['monto_titular'] as num?)?.toDouble() ?? 0.0;
      case 'SUPLENTE':
        return (acuerdo['monto_suplente'] as num?)?.toDouble() ?? 0.0;
      case 'NO_JUGO':
        return (acuerdo['monto_no_jugo'] as num?)?.toDouble() ?? 0.0;
      default:
        return 0.0;
    }
  }

  Widget _buildCondicionBtn(String condicion, String label, double width, Color color) {
    final sel = condicionSeleccionada == condicion;
    return SizedBox(
      width: width,
      child: OutlinedButton(
        onPressed: () => onCondicionChanged(condicion),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          backgroundColor: sel ? color.withOpacity(0.15) : null,
          side: BorderSide(color: sel ? color : Colors.grey.shade300, width: sel ? 2 : 1),
          foregroundColor: sel ? color : Colors.grey,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }
}
