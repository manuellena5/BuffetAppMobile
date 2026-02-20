// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/dao/db.dart';
import '../../buffet/services/caja_service.dart';
import '../../buffet/pages/caja_page.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/format.dart';
import '../../tesoreria/pages/unidad_gestion_selector_page.dart';
import 'detalle_evento_page.dart';

// ── Enums ───────────────────────────────────────────────────────────
enum _EventosModo { delDia, historicos }

enum _EventoSyncEstado { pendiente, parcial, sincronizada, error }

enum _HistoricosFiltro { fecha, mesActual, rango }

enum _VistaContenido { porCaja, porEvento }

enum _VistaPresentacion { tarjeta, tabla }

enum _SyncEstadoCaja { pendiente, sincronizada, error }

// ── Widget ──────────────────────────────────────────────────────────

class EventosPage extends StatefulWidget {
  const EventosPage({super.key});

  @override
  State<EventosPage> createState() => _EventosPageState();
}

class _EventosPageState extends State<EventosPage> {
  final _svc = CajaService();

  // Modo temporal / históricos
  _EventosModo _modo = _EventosModo.delDia;
  _HistoricosFiltro _historicosFiltro = _HistoricosFiltro.mesActual;
  DateTime? _historicosFecha;
  DateTimeRange? _historicosRango;

  // Vista (defaults según requisito: caja + tarjeta)
  _VistaContenido _vistaContenido = _VistaContenido.porCaja;
  _VistaPresentacion _vistaPresentacion = _VistaPresentacion.tarjeta;

  bool _loading = true;
  List<_EventoRow> _eventos = const [];
  List<_CajaViewRow> _cajasView = const [];

  // Unidad de Gestión activa
  int? _unidadGestionId;
  String? _unidadGestionNombre;

  // ── Lifecycle ─────────────────────────────────────────────────────

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

  // ── UG selection ──────────────────────────────────────────────────

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
  }

  // ── Data loading ──────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final rawCajas = await _svc.listarCajas();
      final range = _modo == _EventosModo.historicos
          ? _historicosDateRangeOrNull()
          : null;

      // 1) Filtrar cajas según modo/fecha/UG
      final filtered = _filterCajas(
        rawCajas,
        modo: _modo,
        desde: range == null ? null : _yyyyMmDd(range.start),
        hasta: range == null ? null : _yyyyMmDd(range.end),
        disciplinaFiltro: _unidadGestionNombre,
      );

      // 2) Agrupar en eventos
      final eventos = _buildEventosFromFiltered(filtered);

      // 3) Cargar estadísticas financieras por caja
      final cajaIds =
          filtered.map((c) => (c['id'] as num).toInt()).toList();
      final stats = cajaIds.isNotEmpty
          ? await _loadCajaStats(cajaIds)
          : _PerCajaStats.empty();

      // 4) Construir filas de caja enriquecidas
      final cajasView = filtered.map((c) {
        final row = _CajaViewRow.fromDb(c);
        row.total = stats.totalesPorCaja[row.id] ?? 0.0;
        row.totalEfectivo = stats.efectivoPorCaja[row.id] ?? 0.0;
        row.totalTransfer = stats.transferenciaPorCaja[row.id] ?? 0.0;
        row.ingresos = stats.ingresosPorCaja[row.id] ?? 0.0;
        row.retiros = stats.retirosPorCaja[row.id] ?? 0.0;
        row.diferencia = stats.diferenciaPorCaja[row.id] ?? 0.0;
        row.fondo = stats.fondoPorCaja[row.id] ?? 0.0;
        return row;
      }).toList();

      // Ordenar cajas: más recientes primero
      cajasView.sort((a, b) {
        final f = b.fecha.compareTo(a.fecha);
        if (f != 0) return f;
        return b.id.compareTo(a.id);
      });

      // 5) Enriquecer eventos con totales financieros
      for (final ev in eventos) {
        final evCajas = cajasView.where((c) =>
            c.fecha == ev.fecha &&
            c.disciplina.toLowerCase() == ev.disciplina.toLowerCase());
        ev.totalVentas = evCajas.fold(0.0, (s, c) => s + c.total);
        ev.totalIngresos = evCajas.fold(0.0, (s, c) => s + c.ingresos);
        ev.totalRetiros = evCajas.fold(0.0, (s, c) => s + c.retiros);
        ev.totalDiferencia = evCajas.fold(0.0, (s, c) => s + c.diferencia);
      }

      if (!mounted) return;
      setState(() {
        _eventos = eventos;
        _cajasView = cajasView;
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'eventos_page.load',
        error: e,
        stackTrace: st,
        payload: {'modo': _modo.name},
      );
      if (!mounted) return;
      setState(() {
        _eventos = const [];
        _cajasView = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los datos')),
      );
    }
  }

  // ── Filtrado de cajas ─────────────────────────────────────────────

  List<Map<String, dynamic>> _filterCajas(
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
      // Incluir cajas del día Y cajas abiertas (pueden ser de la noche anterior)
      filtered = cajas.where((c) {
        final f = (c['fecha'] ?? '').toString();
        final estado = (c['estado'] ?? '').toString().toUpperCase().trim();
        return f == hoy || estado == 'ABIERTA';
      }).toList();
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

    if (disciplinaFiltro != null && disciplinaFiltro.isNotEmpty) {
      final filtroLower = disciplinaFiltro.toLowerCase();
      filtered = filtered
          .where((c) =>
              (c['disciplina'] ?? '').toString().toLowerCase() == filtroLower)
          .toList();
    }

    return filtered;
  }

  List<_EventoRow> _buildEventosFromFiltered(
      List<Map<String, dynamic>> filtered) {
    final byKey = <String, _EventoRow>{};
    for (final c in filtered) {
      final fecha = (c['fecha'] ?? '').toString();
      final disciplina = (c['disciplina'] ?? '').toString();
      if (fecha.trim().isEmpty || disciplina.trim().isEmpty) continue;
      final key = '$fecha|$disciplina';

      final row = byKey.putIfAbsent(
        key,
        () => _EventoRow(fecha: fecha, disciplina: disciplina),
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
      final f = b.fecha.compareTo(a.fecha);
      if (f != 0) return f;
      return a.disciplina.compareTo(b.disciplina);
    });

    if (_modo == _EventosModo.delDia) {
      eventos.sort((a, b) => a.disciplina.compareTo(b.disciplina));
    }

    return eventos;
  }

  // ── Carga de stats financieras por caja ───────────────────────────

  Future<_PerCajaStats> _loadCajaStats(List<int> cajaIds) async {
    if (cajaIds.isEmpty) return _PerCajaStats.empty();

    final db = await AppDatabase.instance();
    final placeholders = List.filled(cajaIds.length, '?').join(',');

    final totales = await db.rawQuery('''
      SELECT v.caja_id AS caja_id, COALESCE(SUM(t.total_ticket),0) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id IN ($placeholders) AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY v.caja_id
    ''', cajaIds);

    final totalesMp = await db.rawQuery('''
      SELECT v.caja_id AS caja_id,
             LOWER(COALESCE(mp.descripcion,'')) AS mp_desc,
             COALESCE(SUM(t.total_ticket),0) AS total
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      WHERE v.caja_id IN ($placeholders) AND v.activo = 1 AND t.status <> 'Anulado'
      GROUP BY v.caja_id, mp_desc
    ''', cajaIds);

    final mov = await db.rawQuery('''
      SELECT caja_id,
        COALESCE(SUM(CASE WHEN tipo='INGRESO' THEN monto END),0) AS ingresos,
        COALESCE(SUM(CASE WHEN tipo='RETIRO'  THEN monto END),0) AS retiros
      FROM caja_movimiento
      WHERE caja_id IN ($placeholders)
      GROUP BY caja_id
    ''', cajaIds);

    final dif = await db.rawQuery('''
      SELECT id AS caja_id,
             COALESCE(diferencia,0) AS diferencia,
             COALESCE(fondo_inicial,0) AS fondo_inicial
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

  // ── Helpers de texto / formato ────────────────────────────────────

  String _subtitle() {
    final ug = _unidadGestionNombre ?? '';
    final vista =
        _vistaContenido == _VistaContenido.porCaja ? 'Cajas' : 'Eventos';
    switch (_modo) {
      case _EventosModo.delDia:
        return ug.isEmpty ? '$vista del día' : '$vista del día · $ug';
      case _EventosModo.historicos:
        return ug.isEmpty
            ? '$vista · Históricos'
            : '$vista · Históricos · $ug';
    }
  }

  String _yyyyMmDd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTimeRange _mesActualRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0),
    );
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
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
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
    if (d.contains('vol') || d.contains('voley') || d.contains('volley')) {
      return Icons.sports_volleyball;
    }
    if (d.contains('bask')) return Icons.sports_basketball;
    if (d.contains('pat')) return Icons.sports_gymnastics;
    return Icons.emoji_events;
  }

  // ── Chips de estado ───────────────────────────────────────────────

  _EventoSyncEstado _syncEstadoGeneral(_EventoRow e) {
    if (e.cajasDetectadas <= 0) return _EventoSyncEstado.pendiente;
    if (e.cajasError > 0) return _EventoSyncEstado.error;
    final ok = e.cajasSincronizadas;
    final total = e.cajasDetectadas;
    if (ok <= 0) return _EventoSyncEstado.pendiente;
    if (ok >= total) return _EventoSyncEstado.sincronizada;
    return _EventoSyncEstado.parcial;
  }

  ({String label, Color fg, Color bg, IconData? icon}) _eventoChipFor(
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
          bg: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
          icon: Icons.cloud_off,
        );
    }
  }

  ({String label, Color fg, Color bg, IconData icon}) _cajaChipFor(
      _CajaViewRow c, ThemeData theme) {
    if (!c.cerrada) {
      return (
        label: 'Abierta',
        fg: Colors.green.shade700,
        bg: Colors.green.withValues(alpha: 0.10),
        icon: Icons.lock_open,
      );
    }
    switch (c.syncEstado) {
      case _SyncEstadoCaja.sincronizada:
        return (
          label: 'Sync OK',
          fg: Colors.green.shade700,
          bg: Colors.green.withValues(alpha: 0.10),
          icon: Icons.cloud_done,
        );
      case _SyncEstadoCaja.error:
        return (
          label: 'Error',
          fg: Colors.red.shade700,
          bg: Colors.red.withValues(alpha: 0.10),
          icon: Icons.error,
        );
      case _SyncEstadoCaja.pendiente:
        return (
          label: 'Pendiente',
          fg: Colors.amber.shade800,
          bg: Colors.amber.withValues(alpha: 0.12),
          icon: Icons.cloud_upload,
        );
    }
  }

  String _eventoSyncDescripcion(_EventoSyncEstado s) {
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

  // ── Navigation ────────────────────────────────────────────────────

  Future<void> _openEvento(_EventoRow e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetalleEventoPage(
          fecha: e.fecha,
          disciplina: e.disciplina,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openCaja(_CajaViewRow c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CajaPage(cajaId: c.id)),
    );
    if (!mounted) return;
    await _load();
  }

  // ── Helpers de UI ─────────────────────────────────────────────────

  Widget _detailRow(ThemeData theme, String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              )),
          Text(value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                color: valueColor ?? theme.colorScheme.onSurface,
              )),
        ],
      ),
    );
  }

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

  Widget _emptyState(ThemeData theme) {
    final isCaja = _vistaContenido == _VistaContenido.porCaja;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 32),
        Icon(
          isCaja ? Icons.point_of_sale : Icons.event_busy,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          _modo == _EventosModo.delDia
              ? (isCaja
                  ? 'No hay cajas para hoy'
                  : 'No hay eventos para hoy')
              : (isCaja
                  ? 'No hay cajas para mostrar'
                  : 'No hay eventos para mostrar'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Abrí una caja para que aparezcan datos.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── Selector bar ──────────────────────────────────────────────────

  Widget _buildSelectorBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_VistaContenido>(
              segments: const [
                ButtonSegment(
                  value: _VistaContenido.porCaja,
                  label: Text('Por Caja'),
                  icon: Icon(Icons.point_of_sale),
                ),
                ButtonSegment(
                  value: _VistaContenido.porEvento,
                  label: Text('Por Evento'),
                  icon: Icon(Icons.event),
                ),
              ],
              selected: {_vistaContenido},
              onSelectionChanged: (v) =>
                  setState(() => _vistaContenido = v.first),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => setState(() {
              _vistaPresentacion =
                  _vistaPresentacion == _VistaPresentacion.tarjeta
                      ? _VistaPresentacion.tabla
                      : _VistaPresentacion.tarjeta;
            }),
            icon: Icon(
              _vistaPresentacion == _VistaPresentacion.tarjeta
                  ? Icons.table_rows_outlined
                  : Icons.grid_view,
            ),
            tooltip: _vistaPresentacion == _VistaPresentacion.tarjeta
                ? 'Cambiar a vista tabla'
                : 'Cambiar a vista tarjeta',
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  VISTAS POR CAJA
  // ══════════════════════════════════════════════════════════════════

  Widget _buildCajaCardView(ThemeData theme, double maxWidth) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _cajasView.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        try {
          final c = _cajasView[i];
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: _buildCajaCard(c, theme),
            ),
          );
        } catch (e, stack) {
          AppDatabase.logLocalError(
            scope: 'eventos_page.render_caja_card',
            error: e.toString(),
            stackTrace: stack,
            payload: {'index': i},
          );
          return Card(
            child: ListTile(
              leading: const Icon(Icons.warning),
              title: const Text('Error al mostrar caja'),
            ),
          );
        }
      },
    );
  }

  Widget _buildCajaCard(_CajaViewRow c, ThemeData theme) {
    final syncChip = _cajaChipFor(c, theme);
    final alias = c.aliasCaja?.trim() ?? '';
    final title = alias.isNotEmpty
        ? '${c.codigoCaja} · $alias'
        : (c.puntoVentaCodigo ?? c.codigoCaja);
    final resultadoNeto = c.total + c.ingresos - c.retiros;
    final resultadoConDif = resultadoNeto + c.diferencia;
    final sub = c.cerrada
        ? 'Cerrada ${c.horaCierre ?? ''}'.trim()
        : 'Abierta ${c.horaApertura ?? ''}'.trim();

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openCaja(c),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.cerrada
                          ? theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35)
                          : Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(Icons.point_of_sale,
                        size: 20,
                        color: c.cerrada
                            ? theme.colorScheme.onSurfaceVariant
                            : Colors.green.shade700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          '$sub · ${c.disciplina} · ${_fechaHuman(c.fecha)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: syncChip.bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: syncChip.fg.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(syncChip.icon, size: 12, color: syncChip.fg),
                        const SizedBox(width: 4),
                        Text(syncChip.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: syncChip.fg,
                                fontWeight: FontWeight.w800,
                                fontSize: 10)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.5)),
              const SizedBox(height: 8),

              // Datos financieros
              _detailRow(
                  theme, 'Total Ventas', formatCurrencyNoDecimals(c.total)),
              _detailRow(
                  theme, 'Ingresos', formatCurrencyNoDecimals(c.ingresos),
                  valueColor: Colors.teal),
              _detailRow(theme, 'Retiros', formatCurrencyNoDecimals(c.retiros),
                  valueColor: Colors.red.shade400),
              const SizedBox(height: 4),
              Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.4)),
              const SizedBox(height: 4),
              _detailRow(
                theme,
                'Resultado Neto',
                formatCurrencyNoDecimals(resultadoNeto),
                bold: true,
                valueColor: resultadoNeto >= 0
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
              _detailRow(
                theme,
                'Diferencia',
                '${c.diferencia >= 0 ? '+' : ''}${formatCurrencyNoDecimals(c.diferencia)}',
                valueColor: c.diferencia == 0
                    ? Colors.green.shade700
                    : (c.diferencia > 0
                        ? Colors.blue
                        : Colors.red.shade700),
              ),
              _detailRow(
                theme,
                'Neto + Diferencia',
                formatCurrencyNoDecimals(resultadoConDif),
                bold: true,
                valueColor: resultadoConDif >= 0
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCajaTableView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 48,
          headingTextStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant),
          columns: const [
            DataColumn(label: Text('Caja')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Ventas'), numeric: true),
            DataColumn(label: Text('Ingresos'), numeric: true),
            DataColumn(label: Text('Retiros'), numeric: true),
            DataColumn(label: Text('Res. Neto'), numeric: true),
            DataColumn(label: Text('Diferencia'), numeric: true),
            DataColumn(label: Text('Neto+Dif'), numeric: true),
            DataColumn(label: Text('Sync')),
          ],
          rows: _cajasView.map((c) {
            final rn = c.total + c.ingresos - c.retiros;
            final rnd = rn + c.diferencia;
            final sync = _cajaChipFor(c, theme);
            final alias = c.aliasCaja?.trim() ?? '';
            final cajaLabel = alias.isNotEmpty ? alias : c.codigoCaja;

            return DataRow(
              onSelectChanged: (_) => _openCaja(c),
              cells: [
                DataCell(Text(cajaLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700))),
                DataCell(Text(
                  c.cerrada ? 'Cerrada' : 'Abierta',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.cerrada
                        ? theme.colorScheme.onSurfaceVariant
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                )),
                DataCell(Text(_fechaHuman(c.fecha),
                    style: theme.textTheme.bodySmall)),
                DataCell(Text(formatCurrencyNoDecimals(c.total))),
                DataCell(Text(formatCurrencyNoDecimals(c.ingresos),
                    style: const TextStyle(color: Colors.teal))),
                DataCell(Text(formatCurrencyNoDecimals(c.retiros),
                    style: TextStyle(color: Colors.red.shade400))),
                DataCell(Text(
                  formatCurrencyNoDecimals(rn),
                  style: TextStyle(
                    color: rn >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                )),
                DataCell(Text(
                  c.cerrada
                      ? '${c.diferencia >= 0 ? '+' : ''}${formatCurrencyNoDecimals(c.diferencia)}'
                      : '—',
                  style: TextStyle(
                    color: c.diferencia == 0
                        ? Colors.green.shade700
                        : (c.diferencia > 0
                            ? Colors.blue
                            : Colors.red.shade700),
                  ),
                )),
                DataCell(Text(
                  c.cerrada ? formatCurrencyNoDecimals(rnd) : '—',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: sync.bg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(sync.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: sync.fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 10)),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  VISTAS POR EVENTO
  // ══════════════════════════════════════════════════════════════════

  Widget _buildEventoCardView(ThemeData theme, double maxWidth) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _eventos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        try {
          final e = _eventos[i];
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: _buildEventoCard(e, theme),
            ),
          );
        } catch (e, stack) {
          AppDatabase.logLocalError(
            scope: 'eventos_page.render_evento_card',
            error: e.toString(),
            stackTrace: stack,
            payload: {'index': i},
          );
          return Card(
            child: ListTile(
              leading: const Icon(Icons.warning),
              title: const Text('Error al mostrar evento'),
            ),
          );
        }
      },
    );
  }

  Widget _buildEventoCard(_EventoRow e, ThemeData theme) {
    final sync = _syncEstadoGeneral(e);
    final chip = _eventoChipFor(sync, theme);
    final icon = _iconForDisciplina(e.disciplina);
    final resultadoNeto = e.totalVentas + e.totalIngresos - e.totalRetiros;
    final resultadoConDif = resultadoNeto + e.totalDiferencia;

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
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Icon(icon, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.disciplina,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fechaHuman(e.fecha),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: chip.bg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: chip.fg.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chip.icon != null) ...[
                              Icon(chip.icon, size: 14, color: chip.fg),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              chip.label.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: chip.fg,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.6)),
                  const SizedBox(height: 10),

                  // Datos financieros enriquecidos
                  _detailRow(theme, 'Cajas', '${e.cajasDetectadas}'),
                  _detailRow(theme, 'Total Ventas',
                      formatCurrencyNoDecimals(e.totalVentas)),
                  _detailRow(theme, 'Ingresos',
                      formatCurrencyNoDecimals(e.totalIngresos),
                      valueColor: Colors.teal),
                  _detailRow(theme, 'Retiros',
                      formatCurrencyNoDecimals(e.totalRetiros),
                      valueColor: Colors.red.shade400),
                  const SizedBox(height: 4),
                  Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.4)),
                  const SizedBox(height: 4),
                  _detailRow(
                    theme,
                    'Resultado Neto',
                    formatCurrencyNoDecimals(resultadoNeto),
                    bold: true,
                    valueColor: resultadoNeto >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                  _detailRow(
                    theme,
                    'Diferencia',
                    '${e.totalDiferencia >= 0 ? '+' : ''}${formatCurrencyNoDecimals(e.totalDiferencia)}',
                    valueColor: e.totalDiferencia == 0
                        ? Colors.green.shade700
                        : (e.totalDiferencia > 0
                            ? Colors.blue
                            : Colors.red.shade700),
                  ),
                  _detailRow(
                    theme,
                    'Neto + Diferencia',
                    formatCurrencyNoDecimals(resultadoConDif),
                    bold: true,
                    valueColor: resultadoConDif >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),

                  const SizedBox(height: 8),
                  // Sync summary
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sync: ${_eventoSyncDescripcion(sync)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${e.cajasSincronizadas}/${e.cajasDetectadas}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Footer
            InkWell(
              onTap: () => _openEvento(e),
              child: Ink(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ver detalle del evento',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward,
                        color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventoTableView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 48,
          headingTextStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant),
          columns: const [
            DataColumn(label: Text('Disciplina')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Cajas'), numeric: true),
            DataColumn(label: Text('Ventas'), numeric: true),
            DataColumn(label: Text('Ingresos'), numeric: true),
            DataColumn(label: Text('Retiros'), numeric: true),
            DataColumn(label: Text('Res. Neto'), numeric: true),
            DataColumn(label: Text('Diferencia'), numeric: true),
            DataColumn(label: Text('Neto+Dif'), numeric: true),
            DataColumn(label: Text('Sync')),
          ],
          rows: _eventos.map((e) {
            final rn = e.totalVentas + e.totalIngresos - e.totalRetiros;
            final rnd = rn + e.totalDiferencia;
            final sync = _syncEstadoGeneral(e);
            final chip = _eventoChipFor(sync, theme);

            return DataRow(
              onSelectChanged: (_) => _openEvento(e),
              cells: [
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconForDisciplina(e.disciplina),
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(e.disciplina,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                )),
                DataCell(Text(_fechaHuman(e.fecha),
                    style: theme.textTheme.bodySmall)),
                DataCell(Text('${e.cajasDetectadas}')),
                DataCell(Text(formatCurrencyNoDecimals(e.totalVentas))),
                DataCell(Text(formatCurrencyNoDecimals(e.totalIngresos),
                    style: const TextStyle(color: Colors.teal))),
                DataCell(Text(formatCurrencyNoDecimals(e.totalRetiros),
                    style: TextStyle(color: Colors.red.shade400))),
                DataCell(Text(
                  formatCurrencyNoDecimals(rn),
                  style: TextStyle(
                    color: rn >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                )),
                DataCell(Text(
                  '${e.totalDiferencia >= 0 ? '+' : ''}${formatCurrencyNoDecimals(e.totalDiferencia)}',
                  style: TextStyle(
                    color: e.totalDiferencia == 0
                        ? Colors.green.shade700
                        : (e.totalDiferencia > 0
                            ? Colors.blue
                            : Colors.red.shade700),
                  ),
                )),
                DataCell(Text(
                  formatCurrencyNoDecimals(rnd),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                )),
                DataCell(Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: chip.bg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chip.icon != null) ...[
                        Icon(chip.icon, size: 10, color: chip.fg),
                        const SizedBox(width: 3),
                      ],
                      Text(chip.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: chip.fg,
                              fontWeight: FontWeight.w700,
                              fontSize: 10)),
                    ],
                  ),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isEmpty = _vistaContenido == _VistaContenido.porCaja
        ? _cajasView.isEmpty
        : _eventos.isEmpty;

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
              : Column(
                  children: [
                    // Barra de selectores
                    _buildSelectorBar(theme),

                    // Contenido
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: isEmpty
                            ? _emptyState(theme)
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final isLandscape =
                                      constraints.maxWidth > 600;
                                  final maxCardWidth = isLandscape
                                      ? 600.0
                                      : constraints.maxWidth;

                                  if (_vistaContenido ==
                                      _VistaContenido.porCaja) {
                                    return _vistaPresentacion ==
                                            _VistaPresentacion.tarjeta
                                        ? _buildCajaCardView(
                                            theme, maxCardWidth)
                                        : _buildCajaTableView(theme);
                                  } else {
                                    return _vistaPresentacion ==
                                            _VistaPresentacion.tarjeta
                                        ? _buildEventoCardView(
                                            theme, maxCardWidth)
                                        : _buildEventoTableView(theme);
                                  }
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  MODELOS
// ══════════════════════════════════════════════════════════════════════

class _EventoRow {
  _EventoRow({required this.fecha, required this.disciplina});

  final String fecha;
  final String disciplina;

  int cajasDetectadas = 0;
  int cajasSincronizadas = 0;
  int cajasError = 0;

  // Totales financieros (enriquecidos desde stats)
  double totalVentas = 0;
  double totalIngresos = 0;
  double totalRetiros = 0;
  double totalDiferencia = 0;
}

class _CajaViewRow {
  _CajaViewRow({
    required this.id,
    required this.codigoCaja,
    required this.estado,
    required this.fecha,
    required this.disciplina,
    required this.aperturaDt,
    required this.horaApertura,
    required this.horaCierre,
    required this.syncEstado,
    required this.aliasCaja,
  });

  final int id;
  final String codigoCaja;
  final String estado;
  final String fecha;
  final String disciplina;
  final String? aperturaDt;
  final String? horaApertura;
  final String? horaCierre;
  final _SyncEstadoCaja syncEstado;
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

  static _CajaViewRow fromDb(Map<String, dynamic> e) {
    final estado = (e['estado'] ?? '').toString();
    final syncRaw = (e['sync_estado'] ?? '').toString().toUpperCase().trim();
    final sync = switch (syncRaw) {
      'SINCRONIZADA' => _SyncEstadoCaja.sincronizada,
      'ERROR' => _SyncEstadoCaja.error,
      _ => _SyncEstadoCaja.pendiente,
    };

    // Extraer hora de apertura_dt si no viene hora_apertura aparte
    String? horaApertura = e['hora_apertura']?.toString();
    String? horaCierre = e['hora_cierre']?.toString();
    final aperturaDt = e['apertura_dt']?.toString();

    if ((horaApertura == null || horaApertura.isEmpty) &&
        aperturaDt != null &&
        aperturaDt.contains(' ')) {
      horaApertura = aperturaDt.split(' ').last;
      if (horaApertura.length >= 5) {
        horaApertura = horaApertura.substring(0, 5);
      }
    }

    return _CajaViewRow(
      id: (e['id'] as num).toInt(),
      codigoCaja: (e['codigo_caja'] ?? '').toString(),
      estado: estado,
      fecha: (e['fecha'] ?? '').toString(),
      disciplina: (e['disciplina'] ?? '').toString(),
      aperturaDt: aperturaDt,
      horaApertura: horaApertura,
      horaCierre: horaCierre,
      syncEstado: sync,
      aliasCaja: e['alias_caja']?.toString(),
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
