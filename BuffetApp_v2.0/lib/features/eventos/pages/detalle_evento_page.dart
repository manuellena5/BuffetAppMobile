// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../../../data/dao/db.dart';
import '../../buffet/services/caja_service.dart';
import '../../shared/services/supabase_sync_service.dart';
import '../../shared/format.dart';
import '../../buffet/pages/caja_page.dart';

class DetalleEventoPage extends StatefulWidget {
  const DetalleEventoPage({
    super.key,
    required this.fecha,
    required this.disciplina,
  });

  final String fecha; // YYYY-MM-DD
  final String disciplina;

  @override
  State<DetalleEventoPage> createState() => _DetalleEventoPageState();
}

enum _SyncEstado { pendiente, sincronizada, error }

enum _EventoSync { pendiente, parcial, sincronizada, error }

class _DetalleEventoPageState extends State<DetalleEventoPage> {
  final _cajaSvc = CajaService();

  bool _loading = true;
  bool _syncing = false;
  List<_CajaRow> _cajas = const [];

  double _totalGlobal = 0;
  double _totalEfectivo = 0;
  double _totalTransfer = 0;
  double _totalIngresos = 0;
  double _totalRetiros = 0;
  int _ticketsEmitidos = 0;
  double _diferenciaGlobal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _showInfoDialog(
      {required String title, required String message}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final cajasRaw = await _cajaSvc.listarCajasPorEvento(
        fecha: widget.fecha,
        disciplina: widget.disciplina,
      );

      final cajas = cajasRaw.map((e) => _CajaRow.fromDb(e)).toList();
      final cajaIds = cajas.map((e) => e.id).toList();

      final resumen = await _cajaSvc.resumenCajas(cajaIds);

      final total = (resumen['total'] as num?)?.toDouble() ?? 0.0;
      final porMp = (resumen['por_mp'] as List?)?.cast<Map>() ?? const [];
      final tickets = (resumen['tickets'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final emitidos = (tickets['emitidos'] as num?)?.toInt() ?? 0;

      double efectivo = 0.0;
      double transfer = 0.0;
      for (final row in porMp) {
        final desc = (row['mp_desc'] ?? '').toString().toLowerCase().trim();
        final value = (row['total'] as num?)?.toDouble() ?? 0.0;
        if (desc == 'efectivo') {
          efectivo += value;
        } else if (desc == 'transferencia' || desc.contains('transf')) {
          transfer += value;
        }
      }

      final extra = await _loadPerCajaStats(cajaIds);

      for (final c in cajas) {
        c.total = extra.totalesPorCaja[c.id] ?? 0.0;
        c.totalEfectivo = extra.efectivoPorCaja[c.id] ?? 0.0;
        c.totalTransfer = extra.transferenciaPorCaja[c.id] ?? 0.0;
        c.ingresos = extra.ingresosPorCaja[c.id] ?? 0.0;
        c.retiros = extra.retirosPorCaja[c.id] ?? 0.0;
        c.diferencia = extra.diferenciaPorCaja[c.id] ?? 0.0;
        c.fondo = extra.fondoPorCaja[c.id] ?? 0.0;
      }

      final difGlobal =
          extra.diferenciaPorCaja.values.fold<double>(0.0, (a, b) => a + b);

      final ingGlobal =
          extra.ingresosPorCaja.values.fold<double>(0.0, (a, b) => a + b);
      final retGlobal =
          extra.retirosPorCaja.values.fold<double>(0.0, (a, b) => a + b);

      if (!mounted) return;
      setState(() {
        _cajas = cajas;
        _totalGlobal = total;
        _totalEfectivo = efectivo;
        _totalTransfer = transfer;
        _totalIngresos = ingGlobal;
        _totalRetiros = retGlobal;
        _ticketsEmitidos = emitidos;
        _diferenciaGlobal = difGlobal;
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_evento_page.load',
        error: e,
        stackTrace: st,
        payload: {'fecha': widget.fecha, 'disciplina': widget.disciplina},
      );
      if (!mounted) return;
      setState(() {
        _cajas = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo cargar el detalle del evento')));
    }
  }

  Future<void> _syncEvento() async {
    if (_syncing) return;

    // Re-chequear estado real en SQLite para evitar mensajes confusos.
    // Si todas las cajas cerradas ya están sincronizadas, no se hace nada.
    try {
      final cajasRaw = await _cajaSvc.listarCajasPorEvento(
        fecha: widget.fecha,
        disciplina: widget.disciplina,
      );
      final cajas = cajasRaw.map((e) => _CajaRow.fromDb(e)).toList();

      final cerradas = cajas.where((c) => c.cerrada).toList();
      final totalCerradas = cerradas.length;
      final sincronizadas = cerradas
          .where((c) => c.syncEstado == _SyncEstado.sincronizada)
          .length;
      final pendientes = cerradas
          .where((c) =>
              c.syncEstado == _SyncEstado.pendiente ||
              c.syncEstado == _SyncEstado.error)
          .length;

      if (totalCerradas == 0) {
        await _showInfoDialog(
          title: 'Nada para sincronizar',
          message:
              'Este evento no tiene cajas cerradas.\nSolo se sincronizan cajas cerradas.',
        );
        return;
      }

      if (pendientes == 0 && sincronizadas >= totalCerradas) {
        await _showInfoDialog(
          title: 'Evento ya sincronizado',
          message:
              'No hay nada nuevo para sincronizar.\nCajas sincronizadas: $sincronizadas/$totalCerradas.',
        );
        return;
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_evento_page.syncEvento.precheck',
        error: e,
        stackTrace: st,
        payload: {'fecha': widget.fecha, 'disciplina': widget.disciplina},
      );
      // Si el precheck falla, seguimos igual con el sync para no bloquear el flujo.
    }

    setState(() => _syncing = true);
    Object? syncError;
    StackTrace? syncStack;

    final future = SupaSyncService.I
        .syncEventoCompleto(fecha: widget.fecha, disciplina: widget.disciplina)
        .catchError((e, st) {
      syncError = e;
      syncStack = st is StackTrace ? st : null;
      throw e;
    });

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SyncEventoDialog(
          progress$: SupaSyncService.I.progress$,
          future: future,
        ),
      );
    } catch (_) {
      // el dialogo maneja el estado; no hacemos nada acá
    } finally {
      if (syncError != null) {
        await AppDatabase.logLocalError(
          scope: 'detalle_evento_page.syncEvento',
          error: syncError!,
          stackTrace: syncStack ?? StackTrace.current,
          payload: {'fecha': widget.fecha, 'disciplina': widget.disciplina},
        );
      }
      if (mounted) {
        await _load();
        setState(() => _syncing = false);
      }
    }
  }

  Future<_PerCajaStats> _loadPerCajaStats(List<int> cajaIds) async {
    if (cajaIds.isEmpty) {
      return _PerCajaStats.empty();
    }

    final db = await AppDatabase.instance();
    final placeholders = List.filled(cajaIds.length, '?').join(',');

    final totales = await db.rawQuery('''
      SELECT v.caja_id as caja_id, COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id IN ($placeholders) AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY v.caja_id
    ''', cajaIds);

    final totalesMp = await db.rawQuery('''
      SELECT v.caja_id as caja_id,
             LOWER(COALESCE(mp.descripcion,'')) as mp_desc,
             COALESCE(SUM(t.total_ticket),0) as total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      WHERE v.caja_id IN ($placeholders) AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY v.caja_id, mp_desc
    ''', cajaIds);

    final mov = await db.rawQuery('''
      SELECT caja_id,
        COALESCE(SUM(CASE WHEN tipo='INGRESO' THEN monto END),0) as ingresos,
        COALESCE(SUM(CASE WHEN tipo='RETIRO' THEN monto END),0) as retiros
      FROM caja_movimiento
      WHERE caja_id IN ($placeholders)
      GROUP BY caja_id
    ''', cajaIds);

    // diferencia y fondo_inicial de caja_diaria
    final dif = await db.rawQuery('''
      SELECT id as caja_id, COALESCE(diferencia,0) as diferencia,
             COALESCE(fondo_inicial,0) as fondo_inicial
      FROM caja_diaria
      WHERE id IN ($placeholders)
    ''', cajaIds);

    final totMap = <int, double>{};
    for (final r in totales) {
      final id = (r['caja_id'] as num?)?.toInt();
      if (id == null) continue;
      totMap[id] = (r['total'] as num?)?.toDouble() ?? 0.0;
    }

    final efMap = <int, double>{};
    final trMap = <int, double>{};
    for (final r in totalesMp) {
      final id = (r['caja_id'] as num?)?.toInt();
      if (id == null) continue;
      final desc = (r['mp_desc'] ?? '').toString().toLowerCase().trim();
      final value = (r['total'] as num?)?.toDouble() ?? 0.0;
      if (desc == 'efectivo') {
        efMap[id] = (efMap[id] ?? 0.0) + value;
      } else if (desc == 'transferencia' || desc.contains('transf')) {
        trMap[id] = (trMap[id] ?? 0.0) + value;
      }
    }

    final ingMap = <int, double>{};
    final retMap = <int, double>{};
    for (final r in mov) {
      final id = (r['caja_id'] as num?)?.toInt();
      if (id == null) continue;
      ingMap[id] = (r['ingresos'] as num?)?.toDouble() ?? 0.0;
      retMap[id] = (r['retiros'] as num?)?.toDouble() ?? 0.0;
    }

    final difMap = <int, double>{};
    final fondoMap = <int, double>{};
    for (final r in dif) {
      final id = (r['caja_id'] as num?)?.toInt();
      if (id == null) continue;
      difMap[id] = (r['diferencia'] as num?)?.toDouble() ?? 0.0;
      fondoMap[id] = (r['fondo_inicial'] as num?)?.toDouble() ?? 0.0;
    }

    return _PerCajaStats(
      totalesPorCaja: totMap,
      ingresosPorCaja: ingMap,
      retirosPorCaja: retMap,
      diferenciaPorCaja: difMap,
      efectivoPorCaja: efMap,
      transferenciaPorCaja: trMap,
      fondoPorCaja: fondoMap,
    );
  }

  String _fechaHuman(String fecha) {
    DateTime? d;
    try {
      final parts = fecha.split('-');
      if (parts.length >= 3) {
        d = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    } catch (_) {
      d = null;
    }

    if (d == null) return fecha;

    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];

    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  IconData _iconForDisciplina(String disciplina) {
    final d = disciplina.toLowerCase();
    if (d.contains('fut')) return Icons.sports_soccer;
    if (d.contains('hock')) return Icons.sports_hockey;
    if (d.contains('vol') || d.contains('voley') || d.contains('volley')) {
      return Icons.sports_volleyball;
    }
    if (d.contains('bask')) return Icons.sports_basketball;
    return Icons.emoji_events;
  }

  _EventoSync _eventoSyncEstado() {
    if (_cajas.isEmpty) return _EventoSync.pendiente;

    int cerradas = 0;
    int ok = 0;
    int err = 0;

    for (final c in _cajas) {
      if (!c.cerrada) continue;
      cerradas++;
      final s = c.syncEstado;
      if (s == _SyncEstado.sincronizada) ok++;
      if (s == _SyncEstado.error) err++;
    }

    if (err > 0) return _EventoSync.error;
    if (cerradas == 0) return _EventoSync.pendiente;
    if (ok == 0) return _EventoSync.pendiente;
    if (ok >= cerradas) return _EventoSync.sincronizada;
    return _EventoSync.parcial;
  }

  ({String label, Color fg, Color bg}) _eventoChip(
      _EventoSync s, ThemeData theme) {
    switch (s) {
      case _EventoSync.sincronizada:
        return (
          label: 'Completamente sincronizado',
          fg: Colors.green.shade700,
          bg: Colors.green.withValues(alpha: 0.10)
        );
      case _EventoSync.parcial:
        return (
          label: 'Parcialmente sincronizado',
          fg: Colors.amber.shade800,
          bg: Colors.amber.withValues(alpha: 0.12)
        );
      case _EventoSync.error:
        return (
          label: 'Con errores',
          fg: Colors.red.shade700,
          bg: Colors.red.withValues(alpha: 0.10)
        );
      case _EventoSync.pendiente:
        return (
          label: 'Pendiente',
          fg: theme.colorScheme.outline,
          bg: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
        );
    }
  }

  ({String label, Color fg, Color bg, IconData icon}) _cajaChip(
      _CajaRow c, ThemeData theme) {
    if (!c.cerrada) {
      return (
        label: 'No disponible',
        fg: theme.colorScheme.outline,
        bg: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        icon: Icons.sync_disabled
      );
    }

    switch (c.syncEstado) {
      case _SyncEstado.sincronizada:
        return (
          label: 'Sincronizada',
          fg: Colors.green.shade700,
          bg: Colors.green.withValues(alpha: 0.10),
          icon: Icons.cloud_done
        );
      case _SyncEstado.error:
        return (
          label: 'Error',
          fg: Colors.red.shade700,
          bg: Colors.red.withValues(alpha: 0.10),
          icon: Icons.error
        );
      case _SyncEstado.pendiente:
        return (
          label: 'Pendiente',
          fg: Colors.amber.shade800,
          bg: Colors.amber.withValues(alpha: 0.12),
          icon: Icons.cloud_upload
        );
    }
  }

  int _cajasPendientes() {
    int p = 0;
    for (final c in _cajas) {
      if (!c.cerrada) continue;
      if (c.syncEstado == _SyncEstado.pendiente ||
          c.syncEstado == _SyncEstado.error) {
        p++;
      }
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final eventoSync = _eventoSyncEstado();
    final chip = _eventoChip(eventoSync, theme);

    final pendientes = _cajasPendientes();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Evento'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape = constraints.maxWidth > 600;
                  final maxContentWidth =
                      isLandscape ? 600.0 : constraints.maxWidth;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: maxContentWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header "profile" del evento
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          theme.colorScheme.primary
                                              .withValues(alpha: 0.90),
                                          theme.colorScheme.primaryContainer,
                                        ],
                                      ),
                                    ),
                                    child: Icon(
                                      _iconForDisciplina(widget.disciplina),
                                      color: theme.colorScheme.onPrimary,
                                      size: 40,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: chip.bg,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: chip.fg
                                                    .withValues(alpha: 0.25)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (eventoSync ==
                                                  _EventoSync.parcial) ...[
                                                Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                        color: chip.fg,
                                                        shape:
                                                            BoxShape.circle)),
                                                const SizedBox(width: 8),
                                              ],
                                              Text(
                                                chip.label,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                        color: chip.fg,
                                                        fontWeight:
                                                            FontWeight.w800),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          widget.disciplina,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.calendar_today,
                                                size: 18,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                            const SizedBox(width: 8),
                                            Text(
                                              _fechaHuman(widget.fecha),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color: theme.colorScheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // ───────────────────────────────────────
                              // 1️⃣ BLOQUE PRINCIPAL – RESULTADO DEL EVENTO
                              // ───────────────────────────────────────
                              () {
                                final resultadoNeto = _totalEfectivo + _totalTransfer + _totalIngresos - _totalRetiros;
                                final isPositive = resultadoNeto >= 0;
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isPositive
                                          ? [Colors.green.shade700, Colors.green.shade500]
                                          : [Colors.red.shade700, Colors.red.shade400],
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isPositive ? Icons.trending_up : Icons.trending_down,
                                            color: Colors.white.withValues(alpha: 0.85),
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Resultado Neto del Evento',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: Colors.white.withValues(alpha: 0.90),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          formatCurrency(resultadoNeto),
                                          style: theme.textTheme.headlineMedium?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 32,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Ingresos totales – Retiros',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: Colors.white.withValues(alpha: 0.70),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }(),

                              const SizedBox(height: 12),

                              // Sub-cards: Total Vendido | Otros Ingresos | Retiros
                              Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Total Vendido',
                                      icon: Icons.shopping_bag,
                                      iconColor: theme.colorScheme.primary,
                                      value: formatCurrencyNoDecimals(_totalGlobal),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Otros Ing.',
                                      icon: Icons.add_circle_outline,
                                      iconColor: Colors.teal,
                                      value: formatCurrencyNoDecimals(_totalIngresos),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Retiros',
                                      icon: Icons.remove_circle_outline,
                                      iconColor: Colors.red.shade400,
                                      value: formatCurrencyNoDecimals(_totalRetiros),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // ───────────────────────────────────────
                              // 2️⃣ BLOQUE FINANCIERO – Distribución del Dinero
                              // ───────────────────────────────────────
                              Text(
                                'Distribución del Dinero',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 10),
                              () {
                                final varEfectivo = _totalEfectivo + _totalIngresos - _totalRetiros;
                                final varTransfer = _totalTransfer;
                                final totalVar = varEfectivo + varTransfer;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Var. Efectivo',
                                        icon: Icons.payments,
                                        iconColor: Colors.green,
                                        value: '${varEfectivo >= 0 ? '+' : ''}${formatCurrencyNoDecimals(varEfectivo)}',
                                        valueColor: varEfectivo >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Var. Transf.',
                                        icon: Icons.account_balance,
                                        iconColor: Colors.purple,
                                        value: '${varTransfer >= 0 ? '+' : ''}${formatCurrencyNoDecimals(varTransfer)}',
                                        valueColor: varTransfer >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Total Var.',
                                        icon: Icons.account_balance_wallet,
                                        iconColor: Colors.indigo,
                                        value: '${totalVar >= 0 ? '+' : ''}${formatCurrencyNoDecimals(totalVar)}',
                                        valueColor: totalVar >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                );
                              }(),

                              const SizedBox(height: 20),

                              // ───────────────────────────────────────
                              // 3️⃣ BLOQUE OPERATIVO – Control
                              // ───────────────────────────────────────
                              Text(
                                'Control Operativo',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Tickets',
                                      icon: Icons.confirmation_number,
                                      iconColor: Colors.orange,
                                      value: '$_ticketsEmitidos',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Cajas',
                                      icon: Icons.point_of_sale,
                                      iconColor: Colors.blueGrey,
                                      value: '${_cajas.length}',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Diferencia',
                                      icon: Icons.balance,
                                      iconColor: _diferenciaGlobal == 0
                                          ? Colors.green
                                          : (_diferenciaGlobal > 0 ? Colors.blue : Colors.red),
                                      value: _diferenciaGlobal >= 0
                                          ? '+${formatCurrencyNoDecimals(_diferenciaGlobal)}'
                                          : formatCurrencyNoDecimals(_diferenciaGlobal),
                                      valueColor: _diferenciaGlobal == 0
                                          ? Colors.green.shade700
                                          : (_diferenciaGlobal > 0 ? Colors.blue : Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Cajas del evento
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Cajas del Evento',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_cajas.length} Cajas',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w800),
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 10),

                              if (_cajas.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'No hay cajas para este evento.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                  ),
                                )
                              else
                                ..._cajas.map((c) {
                                  final cajaChip = _cajaChip(c, theme);
                                  final alias = c.aliasCaja?.trim() ?? '';
                                  final title = alias.isNotEmpty
                                      ? '${c.codigoCaja} • $alias'
                                      : (c.puntoVentaCodigo ?? c.codigoCaja);

                                  final sub = c.cerrada
                                      ? 'Cerrada ${c.horaCierre ?? ''}'.trim()
                                      : 'En curso • Abierta ${c.horaApertura ?? ''}'
                                          .trim();

                                  final cajaEsp = c.fondo + c.totalEfectivo + c.ingresos - c.retiros;

                                  Widget _cajaDetailRow(String label, String value, {Color? valueColor, bool bold = false}) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(label, style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                                          )),
                                          Text(value, style: theme.textTheme.bodySmall?.copyWith(
                                            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                                            color: valueColor ?? theme.colorScheme.onSurface,
                                          )),
                                        ],
                                      ),
                                    );
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Card(
                                      elevation: 1,
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CajaPage(cajaId: c.id),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Header: título + estado + chevron
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 36,
                                                    height: 36,
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme
                                                          .surfaceContainerHighest
                                                          .withValues(alpha: 0.35),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: const Icon(Icons.point_of_sale, size: 20),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                                                        Text(sub, style: theme.textTheme.bodySmall?.copyWith(
                                                          color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 11)),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: cajaChip.bg,
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(cajaChip.icon, size: 12, color: cajaChip.fg),
                                                        const SizedBox(width: 4),
                                                        Text(cajaChip.label, style: theme.textTheme.labelSmall?.copyWith(
                                                          color: cajaChip.fg, fontWeight: FontWeight.w800, fontSize: 10)),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 20),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
                                              const SizedBox(height: 8),
                                              // Detalle de control
                                              _cajaDetailRow('Ventas', formatCurrencyNoDecimals(c.total)),
                                              _cajaDetailRow('Efectivo', formatCurrencyNoDecimals(c.totalEfectivo)),
                                              _cajaDetailRow('Transferencia', formatCurrencyNoDecimals(c.totalTransfer)),
                                              _cajaDetailRow('Ingresos extra', formatCurrencyNoDecimals(c.ingresos)),
                                              _cajaDetailRow('Retiros', formatCurrencyNoDecimals(c.retiros)),
                                              if (c.cerrada) ...[  
                                                const SizedBox(height: 4),
                                                Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
                                                const SizedBox(height: 4),
                                                _cajaDetailRow('Caja esperada', formatCurrencyNoDecimals(cajaEsp), bold: true, valueColor: theme.colorScheme.primary),
                                                _cajaDetailRow('Diferencia', '${c.diferencia >= 0 ? '+' : ''}${formatCurrencyNoDecimals(c.diferencia)}',
                                                  bold: true,
                                                  valueColor: c.diferencia == 0
                                                      ? Colors.green.shade700
                                                      : (c.diferencia > 0 ? Colors.blue : Colors.red.shade700),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                    top: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.8))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pendientes > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info,
                              size: 16, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Text(
                            '$pendientes caja${pendientes == 1 ? '' : 's'} pendiente${pendientes == 1 ? '' : 's'} de sincronización',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.amber.shade800,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Sincronizar Evento (próximamente)'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}

class _SyncEventoDialog extends StatelessWidget {
  const _SyncEventoDialog({
    required this.progress$,
    required this.future,
  });

  final Stream<SyncProgress> progress$;
  final Future<EventoSyncReport> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EventoSyncReport>(
      future: future,
      builder: (ctx, snap) {
        final done = snap.connectionState == ConnectionState.done;

        final title = !done
            ? 'Sincronizando…'
            : (snap.hasError
                ? 'Error al sincronizar'
                : ((snap.data?.ok ?? false)
                    ? 'Sincronización completada'
                    : 'Sincronización incompleta'));

        return AlertDialog(
          title: Text(title),
          content: StreamBuilder<SyncProgress>(
            stream: progress$,
            initialData: SyncProgress(processed: 0, total: 1, stage: 'inicio'),
            builder: (ctx, progSnap) {
              final p = progSnap.data ??
                  SyncProgress(processed: 0, total: 1, stage: 'inicio');
              final total = p.total <= 0 ? 1 : p.total;
              final frac = (p.processed / total).clamp(0.0, 1.0);
              final percent = (frac * 100).round();
              final stage = p.stage;

              final message = done
                  ? (snap.hasError
                      ? 'No se pudo completar la sincronización.\n${snap.error}'
                      : (snap.data?.ok ?? false)
                          ? (snap.data?.userMessage ?? 'Listo.')
                          : '${snap.data?.userMessage ?? 'Sincronización con errores.'}\nRevisá el log de errores si persiste.')
                  : 'Progreso: $percent%';

              return SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: done ? 1.0 : frac),
                    const SizedBox(height: 12),
                    Text(message),
                    if (!done) ...[
                      const SizedBox(height: 8),
                      Text(
                        stage.isEmpty ? '—' : 'Etapa: $stage',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: done ? () => Navigator.of(context).pop() : null,
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}

class _PerCajaStats {
  const _PerCajaStats({
    required this.totalesPorCaja,
    required this.ingresosPorCaja,
    required this.retirosPorCaja,
    required this.diferenciaPorCaja,
    required this.efectivoPorCaja,
    required this.transferenciaPorCaja,
    required this.fondoPorCaja,
  });

  final Map<int, double> totalesPorCaja;
  final Map<int, double> ingresosPorCaja;
  final Map<int, double> retirosPorCaja;
  final Map<int, double> diferenciaPorCaja;
  final Map<int, double> efectivoPorCaja;
  final Map<int, double> transferenciaPorCaja;
  final Map<int, double> fondoPorCaja;

  factory _PerCajaStats.empty() => const _PerCajaStats(
        totalesPorCaja: {},
        ingresosPorCaja: {},
        retirosPorCaja: {},
        diferenciaPorCaja: {},
        efectivoPorCaja: {},
        transferenciaPorCaja: {},
        fondoPorCaja: {},
      );
}

class _CajaRow {
  _CajaRow({
    required this.id,
    required this.codigoCaja,
    required this.estado,
    required this.aperturaDt,
    required this.horaApertura,
    required this.horaCierre,
    required this.syncEstado,
    required this.aliasCaja,
  });

  final int id;
  final String codigoCaja;
  final String estado;
  final String? aperturaDt;
  final String? horaApertura;
  final String? horaCierre;

  final _SyncEstado syncEstado;
  final String? aliasCaja;

  double total = 0;
  double totalEfectivo = 0;
  double totalTransfer = 0;
  double ingresos = 0;
  double retiros = 0;
  double diferencia = 0;
  double fondo = 0;

  bool get cerrada => estado.toUpperCase() == 'CERRADA';

  String? get puntoVentaCodigo =>
      CajaService.puntoVentaFromCodigoCaja(codigoCaja);

  static _CajaRow fromDb(Map<String, dynamic> e) {
    final estado = (e['estado'] ?? '').toString();
    final syncRaw = (e['sync_estado'] ?? '').toString().toUpperCase().trim();
    final sync = switch (syncRaw) {
      'SINCRONIZADA' => _SyncEstado.sincronizada,
      'ERROR' => _SyncEstado.error,
      _ => _SyncEstado.pendiente,
    };

    return _CajaRow(
      id: (e['id'] as num).toInt(),
      codigoCaja: (e['codigo_caja'] ?? '').toString(),
      estado: estado,
      aperturaDt: e['apertura_dt']?.toString(),
      horaApertura: e['hora_apertura']?.toString(),
      horaCierre: e['hora_cierre']?.toString(),
      syncEstado: sync,
      aliasCaja: e['alias_caja']?.toString(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.value,
    this.valueColor,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
