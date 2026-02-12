// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/dao/db.dart';
import '../../buffet/services/caja_service.dart';
import '../../shared/state/app_settings.dart';
import '../../tesoreria/pages/unidad_gestion_selector_page.dart';
import 'detalle_evento_page.dart';

enum _EventosModo { delDia, historicos }

enum _EventoSyncEstado { pendiente, parcial, sincronizada, error }

enum _HistoricosFiltro { fecha, mesActual, rango }

class EventosPage extends StatefulWidget {
  const EventosPage({super.key});

  @override
  State<EventosPage> createState() => _EventosPageState();
}

class _EventosPageState extends State<EventosPage> {
  final _svc = CajaService();

  _EventosModo _modo = _EventosModo.delDia;
  _HistoricosFiltro _historicosFiltro = _HistoricosFiltro.mesActual;
  DateTime? _historicosFecha;
  DateTimeRange? _historicosRango;
  bool _loading = true;
  List<_EventoRow> _eventos = const [];

  // Unidad de Gestión activa
  // ignore: unused_field
  int? _unidadGestionId;
  String? _unidadGestionNombre;

  @override
  void initState() {
    super.initState();
    _initUgAndLoad();
  }

  Future<void> _initUgAndLoad() async {
    final settings = context.read<AppSettings>();
    await settings.ensureLoaded();

    if (settings.isUnidadGestionConfigured) {
      _unidadGestionId = settings.unidadGestionActivaId;
      // Cargar el nombre de la UG desde la DB
      try {
        final db = await AppDatabase.instance();
        final rows = await db.query(
          'unidades_gestion',
          columns: ['nombre'],
          where: 'id = ?',
          whereArgs: [settings.unidadGestionActivaId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          _unidadGestionNombre = rows.first['nombre']?.toString();
        }
      } catch (e, stack) {
        await AppDatabase.logLocalError(
          scope: 'eventos_page.init_ug',
          error: e,
          stackTrace: stack,
        );
      }
      await _load();
    } else {
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _promptSeleccionarUg();
      });
    }
  }

  Future<void> _promptSeleccionarUg() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.business, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Unidad de Gestión')),
          ],
        ),
        content: const Text(
          'Para ver los eventos registrados, necesitás seleccionar una Unidad de Gestión.\n\n¿Querés seleccionar una ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Seleccionar'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await _abrirSelectorUg();
    }
    // Si cancela, se queda en la página sin UG (estado vacío)
  }

  Future<void> _abrirSelectorUg() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const UnidadGestionSelectorPage(),
      ),
    );

    if (changed == true && mounted) {
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();
      if (settings.isUnidadGestionConfigured) {
        _unidadGestionId = settings.unidadGestionActivaId;
        try {
          final db = await AppDatabase.instance();
          final rows = await db.query(
            'unidades_gestion',
            columns: ['nombre'],
            where: 'id = ?',
            whereArgs: [settings.unidadGestionActivaId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            _unidadGestionNombre = rows.first['nombre']?.toString();
          }
        } catch (e, stack) {
          await AppDatabase.logLocalError(
            scope: 'eventos_page.abrir_selector_ug',
            error: e,
            stackTrace: stack,
          );
        }
        await _load();
      }
    }
    // Si no cambió, se queda en la página con el estado actual
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final cajas = await _svc.listarCajas();
      final range = _modo == _EventosModo.historicos
          ? _historicosDateRangeOrNull()
          : null;
      final eventos = _buildEventosFromCajas(
        cajas,
        modo: _modo,
        desde: range == null ? null : _yyyyMmDd(range.start),
        hasta: range == null ? null : _yyyyMmDd(range.end),
        disciplinaFiltro: _unidadGestionNombre,
      );
      if (!mounted) return;
      setState(() {
        _eventos = eventos;
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'eventos_page.load',
          error: e,
          stackTrace: st,
          payload: {'modo': _modo.name});
      if (!mounted) return;
      setState(() {
        _eventos = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron cargar los eventos')));
    }
  }

  List<_EventoRow> _buildEventosFromCajas(
    List<Map<String, dynamic>> cajas, {
    required _EventosModo modo,
    String? desde,
    String? hasta,
    String? disciplinaFiltro,
  }) {
    final now = DateTime.now();
    final hoy =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    List<Map<String, dynamic>> filtered;
    if (modo == _EventosModo.delDia) {
      filtered =
          cajas.where((c) => (c['fecha'] ?? '').toString() == hoy).toList();
    } else {
      final d = (desde ?? '').trim();
      final h = (hasta ?? '').trim();
      if (d.isNotEmpty && h.isNotEmpty) {
        filtered = cajas.where((c) {
          final f = (c['fecha'] ?? '').toString().trim();
          if (f.length != 10) return false;
          return f.compareTo(d) >= 0 && f.compareTo(h) <= 0;
        }).toList();
      } else {
        filtered = cajas;
      }
    }

    // Filtrar por Unidad de Gestión (disciplina) si está definida
    if (disciplinaFiltro != null && disciplinaFiltro.isNotEmpty) {
      final filtroLower = disciplinaFiltro.toLowerCase();
      filtered = filtered
          .where((c) =>
              (c['disciplina'] ?? '').toString().toLowerCase() == filtroLower)
          .toList();
    }

    final byKey = <String, _EventoRow>{};
    for (final c in filtered) {
      final fecha = (c['fecha'] ?? '').toString();
      final disciplina = (c['disciplina'] ?? '').toString();
      if (fecha.trim().isEmpty || disciplina.trim().isEmpty) continue;
      final key = '$fecha|$disciplina';

      final row = byKey.putIfAbsent(
        key,
        () => _EventoRow(
          fecha: fecha,
          disciplina: disciplina,
        ),
      );

      row.cajasDetectadas++;

      final syncEstado =
          (c['sync_estado'] ?? '').toString().toUpperCase().trim();
      if (syncEstado == 'SINCRONIZADA') {
        row.cajasSincronizadas++;
      } else if (syncEstado == 'ERROR') {
        row.cajasError++;
      }
    }

    final eventos = byKey.values.toList();
    eventos.sort((a, b) {
      // fecha desc, disciplina asc
      final f = b.fecha.compareTo(a.fecha);
      if (f != 0) return f;
      return a.disciplina.compareTo(b.disciplina);
    });

    // “Eventos del día” suele verse mejor ordenado por disciplina
    if (modo == _EventosModo.delDia) {
      eventos.sort((a, b) => a.disciplina.compareTo(b.disciplina));
    }

    return eventos;
  }

  String _subtitle() {
    final ug = _unidadGestionNombre ?? '';
    switch (_modo) {
      case _EventosModo.delDia:
        return ug.isEmpty ? 'Eventos del día' : 'Eventos del día · $ug';
      case _EventosModo.historicos:
        return ug.isEmpty ? 'Históricos' : 'Históricos · $ug';
    }
  }

  String _yyyyMmDd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTimeRange _mesActualRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    return DateTimeRange(start: start, end: end);
  }

  DateTimeRange? _historicosDateRangeOrNull() {
    switch (_historicosFiltro) {
      case _HistoricosFiltro.mesActual:
        return _mesActualRange();
      case _HistoricosFiltro.fecha:
        final f = _historicosFecha;
        if (f == null) return null;
        final day = DateTime(f.year, f.month, f.day);
        return DateTimeRange(start: day, end: day);
      case _HistoricosFiltro.rango:
        return _historicosRango;
    }
  }

  String _historicosFiltroLabel() {
    switch (_historicosFiltro) {
      case _HistoricosFiltro.mesActual:
        return 'Mes actual';
      case _HistoricosFiltro.fecha:
        final f = _historicosFecha;
        return f == null ? 'Fecha' : _yyyyMmDd(f);
      case _HistoricosFiltro.rango:
        final r = _historicosRango;
        return r == null
            ? 'Rango'
            : '${_yyyyMmDd(r.start)} a ${_yyyyMmDd(r.end)}';
    }
  }

  Future<void> _configurarFiltroHistoricos() async {
    final theme = Theme.of(context);
    final selected = await showDialog<_HistoricosFiltro>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filtro de históricos'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _HistoricosFiltro.fecha),
            child: Row(
              children: [
                Icon(Icons.event, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Elegir una fecha')),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _HistoricosFiltro.mesActual),
            child: Row(
              children: [
                Icon(Icons.calendar_month, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Mes actual')),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _HistoricosFiltro.rango),
            child: Row(
              children: [
                Icon(Icons.date_range, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Rango personalizado')),
              ],
            ),
          ),
        ],
      ),
    );

    if (selected == null) return;

    if (selected == _HistoricosFiltro.mesActual) {
      setState(() {
        _historicosFiltro = _HistoricosFiltro.mesActual;
        _historicosFecha = null;
        _historicosRango = null;
      });
      await _load();
      return;
    }

    if (selected == _HistoricosFiltro.fecha) {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: _historicosFecha ?? now,
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime(now.year + 1, 12, 31),
        helpText: 'Seleccionar fecha',
      );
      if (picked == null) return;
      setState(() {
        _historicosFiltro = _HistoricosFiltro.fecha;
        _historicosFecha = picked;
        _historicosRango = null;
      });
      await _load();
      return;
    }

    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _historicosRango ?? _mesActualRange(),
      helpText: 'Seleccionar rango',
    );
    if (picked == null) return;
    setState(() {
      _historicosFiltro = _HistoricosFiltro.rango;
      _historicosRango = picked;
      _historicosFecha = null;
    });
    await _load();
  }

  String _fechaHuman(String fecha) {
    // fecha viene como YYYY-MM-DD
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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;

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

    final label = '${d.day} ${months[d.month - 1]}';
    if (diff == 0) return 'Hoy, $label';
    if (diff == 1) return 'Ayer, $label';
    return label;
  }

  IconData _iconForDisciplina(String disciplina) {
    final d = disciplina.toLowerCase();
    if (d.contains('fut')) return Icons.sports_soccer;
    if (d.contains('hock')) return Icons.sports_hockey;
    if (d.contains('tenis')) return Icons.sports_tennis;
    if (d.contains('vol') || d.contains('voley') || d.contains('volley'))
      return Icons.sports_volleyball;
    if (d.contains('bask')) return Icons.sports_basketball;
    if (d.contains('pat')) return Icons.sports_gymnastics;
    return Icons.emoji_events;
  }

  _EventoSyncEstado _syncEstadoGeneral(_EventoRow e) {
    if (e.cajasDetectadas <= 0) return _EventoSyncEstado.pendiente;

    if (e.cajasError > 0) return _EventoSyncEstado.error;

    final ok = e.cajasSincronizadas;
    final total = e.cajasDetectadas;

    if (ok <= 0) return _EventoSyncEstado.pendiente;
    if (ok >= total) return _EventoSyncEstado.sincronizada;
    return _EventoSyncEstado.parcial;
  }

  ({String label, Color fg, Color bg, IconData? icon}) _chipFor(
      _EventoSyncEstado s, ThemeData theme) {
    switch (s) {
      case _EventoSyncEstado.sincronizada:
        return (
          label: 'Sync OK',
          fg: Colors.green.shade700,
          bg: Colors.green.withValues(alpha: 0.12),
          icon: Icons.check_circle,
        );
      case _EventoSyncEstado.parcial:
        return (
          label: 'Parcial',
          fg: Colors.amber.shade800,
          bg: Colors.amber.withValues(alpha: 0.12),
          icon: null,
        );
      case _EventoSyncEstado.error:
        return (
          label: 'Error',
          fg: Colors.red.shade700,
          bg: Colors.red.withValues(alpha: 0.10),
          icon: Icons.error,
        );
      case _EventoSyncEstado.pendiente:
        return (
          label: 'Pendiente',
          fg: theme.colorScheme.outline,
          bg: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          icon: Icons.cloud_off,
        );
    }
  }

  String _estadoDescripcion(_EventoSyncEstado s) {
    switch (s) {
      case _EventoSyncEstado.sincronizada:
        return 'Completamente sincronizado';
      case _EventoSyncEstado.parcial:
        return 'Parcialmente sincronizado';
      case _EventoSyncEstado.error:
        return 'Sincronización con errores';
      case _EventoSyncEstado.pendiente:
        return 'Pendiente de sincronizar';
    }
  }

  Future<void> _openEvento(_EventoRow e) async {
    final nav = Navigator.of(context);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => DetalleEventoPage(
          fecha: e.fecha,
          disciplina: e.disciplina,
        ),
      ),
    );

    // Al volver del detalle, refrescar para reflejar posibles cambios de sync.
    if (!mounted) return;
    await _load();
  }

  // --- Métodos de Supabase deshabilitados ---
  // _syncEventosDesdeSupabase, _pickFechaParaSync, _pickRangoParaSync,
  // _cajaLabelRemote, _showNoCajasHoyModal, _seleccionarCajasParaDescarga
  // fueron removidos. Solo se manejan eventos locales.

  Widget _buildSinUgBody(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_outlined,
                size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Sin Unidad de Gestión',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seleccioná una Unidad de Gestión para ver los eventos registrados.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _abrirSelectorUg,
              icon: const Icon(Icons.search),
              label: const Text('Seleccionar Unidad de Gestión'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        toolbarHeight: 84,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Eventos',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              _subtitle(),
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          if (_modo == _EventosModo.historicos)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: _configurarFiltroHistoricos,
                icon: const Icon(Icons.filter_alt),
                label: Text(_historicosFiltroLabel()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () async {
                setState(() {
                  _modo = _modo == _EventosModo.delDia
                      ? _EventosModo.historicos
                      : _EventosModo.delDia;
                });
                await _load();
              },
              icon: Icon(
                  _modo == _EventosModo.delDia ? Icons.history : Icons.today),
              label: Text(_modo == _EventosModo.delDia ? 'Históricos' : 'Hoy'),
            ),
          ),
          IconButton(
            onPressed: _abrirSelectorUg,
            icon: const Icon(Icons.business),
            tooltip: 'Cambiar Unidad de Gestión',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _unidadGestionId == null
              ? _buildSinUgBody(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _eventos.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                  children: [
                        const SizedBox(height: 32),
                        Icon(Icons.event_busy,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          _modo == _EventosModo.delDia
                              ? 'No hay eventos para hoy'
                              : 'No hay eventos para mostrar',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Abrí una caja para que aparezca el evento.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isLandscape = constraints.maxWidth > 600;
                        final maxCardWidth = isLandscape ? 600.0 : constraints.maxWidth;
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: _eventos.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, i) {
                            final e = _eventos[i];
                            final sync = _syncEstadoGeneral(e);
                            final chip = _chipFor(sync, theme);
                            final icon = _iconForDisciplina(e.disciplina);

                            return Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxCardWidth),
                                child: Card(
                          elevation: 1,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openEvento(e),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Icon(icon,
                                                color:
                                                    theme.colorScheme.primary),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.disciplina,
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _fechaHuman(e.fecha),
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                          fontWeight:
                                                              FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
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
                                                if (chip.icon != null) ...[
                                                  Icon(chip.icon,
                                                      size: 14, color: chip.fg),
                                                  const SizedBox(width: 6),
                                                ],
                                                Text(
                                                  chip.label.toUpperCase(),
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                          color: chip.fg,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          letterSpacing: 0.6),
                                                ),
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Divider(
                                          height: 1,
                                          color: theme.dividerColor
                                              .withValues(alpha: 0.6)),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Estado de sincronización',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                          Text(
                                            _estadoDescripcion(sync),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.35),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Cajas detectadas',
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.point_of_sale,
                                                          size: 18,
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '${e.cajasDetectadas}',
                                                        style: theme.textTheme
                                                            .titleLarge
                                                            ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.35),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Sincronizadas',
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.cloud_upload,
                                                          size: 18,
                                                          color: chip.fg),
                                                      const SizedBox(width: 8),
                                                      RichText(
                                                        text: TextSpan(
                                                          style: theme.textTheme
                                                              .titleLarge
                                                              ?.copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  color: theme
                                                                      .colorScheme
                                                                      .onSurface),
                                                          children: [
                                                            TextSpan(
                                                                text:
                                                                    '${e.cajasSincronizadas}'),
                                                            TextSpan(
                                                              text:
                                                                  '/${e.cajasDetectadas}',
                                                              style: theme
                                                                  .textTheme
                                                                  .titleSmall
                                                                  ?.copyWith(
                                                                      color: theme
                                                                          .colorScheme
                                                                          .onSurfaceVariant,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (sync ==
                                                          _EventoSyncEstado
                                                              .error &&
                                                      e.cajasError > 0) ...[
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'Errores: ${e.cajasError}',
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                              color: Colors
                                                                  .red.shade700,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800),
                                                    ),
                                                  ]
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _openEvento(e),
                                  child: Ink(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.35),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Ver detalle del evento',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                    color: theme
                                                        .colorScheme.primary,
                                                    fontWeight:
                                                        FontWeight.w800),
                                          ),
                                        ),
                                        Icon(Icons.arrow_forward,
                                            color: theme.colorScheme.primary),
                                      ],
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                ),
    );
  }
}

class _EventoRow {
  _EventoRow({required this.fecha, required this.disciplina});

  final String fecha;
  final String disciplina;

  int cajasDetectadas = 0;
  int cajasSincronizadas = 0;
  int cajasError = 0;
}
