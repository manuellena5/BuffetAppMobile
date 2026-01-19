// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../../../data/dao/db.dart';
import '../../buffet/services/caja_service.dart';
import '../../shared/services/supabase_sync_service.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
    switch (_modo) {
      case _EventosModo.delDia:
        return 'Eventos del día';
      case _EventosModo.historicos:
        return 'Eventos históricos';
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

  Future<String?> _pickFechaParaSync() async {
    if (_modo == _EventosModo.delDia) {
      return _yyyyMmDd(DateTime.now());
    }

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Seleccionar fecha a descargar',
    );
    if (picked == null) return null;
    return _yyyyMmDd(picked);
  }

  Future<DateTimeRange?> _pickRangoParaSync() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _historicosRango ?? _mesActualRange(),
      helpText: 'Seleccionar rango a descargar',
    );
    return picked;
  }

  String _cajaLabelRemote(Map<String, dynamic> caja) {
    final codigo = (caja['codigo_caja'] ?? '').toString().trim();
    final fecha = (caja['fecha'] ?? '').toString().trim();
    final disciplina = (caja['disciplina'] ?? '').toString().trim();
    final parts = <String>[];
    if (fecha.isNotEmpty) parts.add(fecha);
    if (disciplina.isNotEmpty) parts.add(disciplina);
    return '${codigo.isEmpty ? '(sin código)' : codigo} — ${parts.join(' · ')}';
  }

  Future<void> _showNoCajasHoyModal() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sin cajas para descargar'),
        content: const Text(
          'No existen cajas en la nube para descargar, pruebe desde la pantalla de históricos filtrando por fechas.\n Si quiere sincronizar y subir la caja actual, ingrese a la pantalla de detalle del evento.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>?> _seleccionarCajasParaDescarga({
    required String titulo,
    required List<Map<String, dynamic>> cajas,
  }) async {
    if (cajas.isEmpty) return null;

    final theme = Theme.of(context);
    final seleccion = <String, bool>{
      for (final c in cajas) (c['codigo_caja'] ?? '').toString().trim(): true,
    };
    // Limpiar claves inválidas (sin código)
    seleccion.removeWhere((k, _) => k.trim().isEmpty);

    final codigosSeleccionados = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final codigos = cajas
              .map((c) => (c['codigo_caja'] ?? '').toString().trim())
              .where((c) => c.isNotEmpty)
              .toList(growable: false);

          final selectedCount = seleccion.values.where((v) => v).length;

          return AlertDialog(
            title: Text(titulo),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Se encontraron ${codigos.length} caja(s). Seleccioná cuáles descargar.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: cajas.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = cajas[i];
                        final codigo =
                            (c['codigo_caja'] ?? '').toString().trim();
                        if (codigo.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final fecha = (c['fecha'] ?? '').toString().trim();
                        final disciplina =
                            (c['disciplina'] ?? '').toString().trim();
                        final checked = seleccion[codigo] ?? true;

                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setLocal(() {
                              seleccion[codigo] = v ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            codigo,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            [
                              if (fecha.isNotEmpty) fecha,
                              if (disciplina.isNotEmpty) disciplina,
                            ].join(' · '),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedCount == 0
                    ? null
                    : () {
                        Navigator.pop(
                          ctx,
                          seleccion.entries
                              .where((e) => e.value)
                              .map((e) => e.key)
                              .toSet(),
                        );
                      },
                child: Text('Descargar ($selectedCount)'),
              ),
            ],
          );
        },
      ),
    );

    if (codigosSeleccionados == null) return null;

    final selected = cajas.where((c) {
      final codigo = (c['codigo_caja'] ?? '').toString().trim();
      return codigo.isNotEmpty && codigosSeleccionados.contains(codigo);
    }).toList(growable: false);

    return selected;
  }

  Future<void> _syncEventosDesdeSupabase() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final supa = SupaSyncService.I;

    String? fecha;
    DateTimeRange? rango;
    if (_modo == _EventosModo.delDia) {
      fecha = _yyyyMmDd(DateTime.now());
    } else {
      rango = await _pickRangoParaSync();
      if (rango == null) return;
    }

    final online = await supa.hasInternet();
    if (!online) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Sin conectividad. Intentá más tarde.')));
      return;
    }

    List<Map<String, dynamic>> cajas;
    try {
      if (_modo == _EventosModo.delDia) {
        cajas = await supa.fetchCajasByFecha(fecha!);
      } else {
        final desde = _yyyyMmDd(rango!.start);
        final hasta = _yyyyMmDd(rango.end);
        cajas = await supa.fetchCajasByRango(desde: desde, hasta: hasta);
      }
    } catch (e, st) {
      String userMessage =
          'No se pudo descargar datos desde la nube. Revisá “Logs de errores”.';
      final em = e.toString().toLowerCase();
      if (em.contains('could not find the table') ||
          em.contains('does not exist') ||
          em.contains('schema cache') ||
          em.contains('pgrst')) {
        userMessage =
            'No se pudo descargar desde la Nube (tabla no disponible). Revisá “Logs de errores”.';
      }

      await AppDatabase.logLocalError(
        scope: 'eventos_page.supabase_fetch_cajas_por_fecha',
        error: e,
        stackTrace: st,
        payload: {
          'modo': _modo.name,
          'fecha': fecha,
          'desde': rango == null ? null : _yyyyMmDd(rango.start),
          'hasta': rango == null ? null : _yyyyMmDd(rango.end),
          'exception_type': e.runtimeType.toString(),
          'exception_message': e.toString(),
        },
      );
      await supa.tryInsertRemoteSyncErrorLog(
        scope: 'eventos_page.supabase_fetch_cajas_por_fecha',
        error: e,
        stackTrace: st,
        payload: {
          'modo': _modo.name,
          'fecha': fecha,
          'desde': rango == null ? null : _yyyyMmDd(rango.start),
          'hasta': rango == null ? null : _yyyyMmDd(rango.end),
        },
      );
      messenger.showSnackBar(SnackBar(content: Text(userMessage)));
      return;
    }

    if (cajas.isEmpty) {
      if (_modo == _EventosModo.delDia) {
        await _showNoCajasHoyModal();
      } else {
        final d = _yyyyMmDd(rango!.start);
        final h = _yyyyMmDd(rango.end);
        messenger.showSnackBar(
          SnackBar(content: Text('No hay cajas en la Nube para $d a $h')),
        );
      }
      return;
    }

    // Dedupe por codigo_caja (por si el backend devuelve duplicados)
    final byCodigo = <String, Map<String, dynamic>>{};
    for (final c in cajas) {
      final codigo = (c['codigo_caja'] ?? '').toString().trim();
      if (codigo.isEmpty) continue;
      byCodigo[codigo] = c;
    }
    final cajasUnicas = byCodigo.isEmpty ? cajas : byCodigo.values.toList();
    cajasUnicas
        .sort((a, b) => _cajaLabelRemote(a).compareTo(_cajaLabelRemote(b)));

    // Solo trabajamos con cajas que tienen codigo_caja válido.
    final cajasConCodigo = cajasUnicas
        .where((c) => (c['codigo_caja'] ?? '').toString().trim().isNotEmpty)
        .toList(growable: false);
    if (cajasConCodigo.isEmpty) {
      if (_modo == _EventosModo.delDia) {
        await _showNoCajasHoyModal();
      } else {
        final d = _yyyyMmDd(rango!.start);
        final h = _yyyyMmDd(rango.end);
        messenger.showSnackBar(
          SnackBar(content: Text('No hay cajas en la Nube para $d a $h')),
        );
      }
      return;
    }

    final titulo = _modo == _EventosModo.delDia
        ? 'Descargar desde la Nube (Hoy)'
        : 'Descargar desde la Nube (Rango)';
    final seleccionadas = await _seleccionarCajasParaDescarga(
      titulo: titulo,
      cajas: cajasConCodigo,
    );
    if (seleccionadas == null || seleccionadas.isEmpty) return;

    int importadas = 0;
    int existentes = 0;
    int errores = 0;

    // Modal de progreso simple
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Descargando…'),
        content: SizedBox(
          height: 64,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    try {
      final db = await AppDatabase.instance();

      for (final caja in seleccionadas) {
        final codigo = (caja['codigo_caja'] ?? '').toString().trim();
        if (codigo.isEmpty) continue;

        final exists = await db.query(
          'caja_diaria',
          columns: ['id'],
          where: 'codigo_caja=?',
          whereArgs: [codigo],
          limit: 1,
        );
        if (exists.isNotEmpty) {
          existentes++;
          continue;
        }

        try {
          await supa.importRemoteCajaDiariaFullToLocal(cajaRemote: caja);
          importadas++;
        } catch (e, st) {
          errores++;
          await AppDatabase.logLocalError(
            scope: 'eventos_page.import_remote_caja',
            error: e,
            stackTrace: st,
            payload: {
              'codigo_caja': codigo,
              'fecha': (caja['fecha'] ?? fecha)?.toString(),
              'exception_type': e.runtimeType.toString(),
              'exception_message': e.toString(),
            },
          );
          await supa.tryInsertRemoteSyncErrorLog(
            scope: 'eventos_page.import_remote_caja',
            error: e,
            stackTrace: st,
            payload: {
              'codigo_caja': codigo,
              'fecha': (caja['fecha'] ?? fecha)?.toString(),
            },
          );
        }
      }
    } finally {
      if (mounted) nav.pop(); // cerrar modal
    }

    if (!mounted) return;
    await _load();

    if (errores > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Descarga con errores. Nuevas: $importadas · Ya estaban: $existentes · Errores: $errores. Revisá “Logs de errores”.',
        ),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Descarga OK. Nuevas: $importadas · Ya estaban: $existentes · Errores: $errores'),
      ));
    }
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                          'Abrí una caja para que aparezca el evento. \nO prueba descargando desde la Nube.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _eventos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final e = _eventos[i];
                        final sync = _syncEstadoGeneral(e);
                        final chip = _chipFor(sync, theme);
                        final icon = _iconForDisciplina(e.disciplina);

                        return Card(
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
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _syncEventosDesdeSupabase,
        child: const Icon(Icons.cloud_download_rounded),
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
