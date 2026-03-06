import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/dao/db.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/format.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/summary_card.dart';
import '../../../widgets/status_badge.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../widgets/calendario_mensual_widget.dart';
import '../widgets/flujo_caja_widget.dart';
import 'crear_compromiso_page.dart';
import 'detalle_compromiso_page.dart';

/// Pantalla de Compromisos con diseño ERP profesional.
///
/// Desktop (>=900px): Lista + Calendario side by side.
/// Mobile (<900px): Lista con calendario accesible por ícono.
class CompromisosErpScreen extends StatefulWidget {
  const CompromisosErpScreen({super.key});

  @override
  State<CompromisosErpScreen> createState() => _CompromisosErpScreenState();
}

class _CompromisosErpScreenState extends State<CompromisosErpScreen>
    with SingleTickerProviderStateMixin {
  final _service = CompromisosService.instance;

  // ─── Tabs ───
  late final TabController _tabController;

  // ─── Datos ───
  List<Map<String, dynamic>> _compromisos = [];
  List<Map<String, dynamic>> _entidades = [];
  bool _isLoading = true;

  // ─── Filtros ───
  int? _unidadGestionId;
  int? _entidadPlantelId;
  String? _rolFiltro;
  String? _tipoFiltro;
  bool? _origenAcuerdoFiltro;
  bool? _activoFiltro;

  // ─── Calendario ───
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, List<Map<String, dynamic>>> _cuotasPorDia = {};
  List<Map<String, dynamic>> _cuotasDiaSeleccionado = [];

  // ─── KPIs ───
  double _totalCompromisos = 0;
  double _totalPagado = 0;
  double _totalPendiente = 0;
  int _vencidosCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedDay = DateTime.now();
    _cargarEntidades();
    _cargarCompromisos();
    _cargarCalendario();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Carga de datos ───

  Future<void> _cargarEntidades() async {
    try {
      final db = await AppDatabase.instance();
      final entidades = await db.query(
        'entidades_plantel',
        where: 'eliminado = 0',
        orderBy: 'nombre ASC',
      );
      if (mounted) {
        setState(() {
          _entidades = entidades.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _cargarCompromisos() async {
    setState(() => _isLoading = true);

    try {
      final db = await AppDatabase.instance();

      final where = <String>[];
      final args = <dynamic>[];

      if (_unidadGestionId != null) {
        where.add('unidad_gestion_id = ?');
        args.add(_unidadGestionId);
      }
      if (_tipoFiltro != null) {
        where.add('tipo = ?');
        args.add(_tipoFiltro);
      }
      if (_activoFiltro != null) {
        where.add('activo = ?');
        args.add(_activoFiltro! ? 1 : 0);
      }
      if (_entidadPlantelId != null) {
        where.add('entidad_plantel_id = ?');
        args.add(_entidadPlantelId);
      }
      if (_rolFiltro != null) {
        where.add('entidad_rol = ?');
        args.add(_rolFiltro);
      }

      final raw = await db.query(
        'v_compromisos_completo',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'fecha_inicio DESC',
      );

      var compromisos = raw.map((c) => Map<String, dynamic>.from(c)).toList();

      // Enriquecer con info de acuerdo
      for (final c in compromisos) {
        final acuerdoId = c['acuerdo_id'];
        if (acuerdoId != null) {
          c['es_de_acuerdo'] = await _service.esCompromisoPorAcuerdo(c['id'] as int);
        } else {
          c['es_de_acuerdo'] = false;
        }
      }

      if (_origenAcuerdoFiltro != null) {
        compromisos = compromisos
            .where((c) => c['es_de_acuerdo'] == _origenAcuerdoFiltro)
            .toList();
      }

      // Calcular KPIs
      double total = 0, pagado = 0, pendiente = 0;
      for (final c in compromisos) {
        final monto = (c['monto'] as num?)?.toDouble() ?? 0;
        total += monto;
        final cuotasConf = (c['cuotas_confirmadas'] as num?)?.toInt() ?? 0;
        final cuotas = (c['cuotas'] as num?)?.toInt();
        if (cuotas != null && cuotas > 0) {
          pagado += monto * cuotasConf / cuotas;
          pendiente += monto * (cuotas - cuotasConf) / cuotas;
        } else {
          pendiente += monto;
        }
      }
      setState(() {
        _compromisos = compromisos;
        _totalCompromisos = total;
        _totalPagado = pagado;
        _totalPendiente = pendiente;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'compromisos_erp.cargar',
        error: e.toString(),
        stackTrace: stack,
      );
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar compromisos. Intente nuevamente.')),
        );
      }
    }
  }

  Future<void> _cargarCalendario() async {
    try {
      final primerDia = DateTime(_focusedDay.year, _focusedDay.month - 2, 1);
      final ultimoDia = DateTime(_focusedDay.year, _focusedDay.month + 3, 0);
      final desde = DateFormat('yyyy-MM-dd').format(primerDia);
      final hasta = DateFormat('yyyy-MM-dd').format(ultimoDia);

      final cuotas = await _service.obtenerCuotasParaCalendario(
        unidadGestionId: _unidadGestionId,
        desde: desde,
        hasta: hasta,
      );

      final mapa = <String, List<Map<String, dynamic>>>{};
      int vencidos = 0;
      final hoyStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      for (final c in cuotas) {
        final fecha = c['fecha_programada'] as String? ?? '';
        if (fecha.isEmpty) continue;
        mapa.putIfAbsent(fecha, () => []).add(Map<String, dynamic>.from(c));

        final estado = c['cuota_estado'] as String? ?? 'ESPERADO';
        if (estado != 'CONFIRMADO' && estado != 'CANCELADO' && fecha.compareTo(hoyStr) < 0) {
          vencidos++;
        }
      }

      if (mounted) {
        setState(() {
          _cuotasPorDia = mapa;
          _vencidosCount = vencidos;
        });
        _actualizarDiaSeleccionado();
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'compromisos_erp.calendario',
        error: e.toString(),
        stackTrace: stack,
      );
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

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return ErpLayout(
      currentRoute: '/compromisos',
      title: 'Compromisos',
      body: _buildContent(context),
      floatingActionButton: MediaQuery.of(context).size.width < AppSpacing.breakpointTablet
          ? FloatingActionButton.extended(
              onPressed: _crearCompromiso,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
    );
  }

  Widget _buildContent(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Header (solo desktop — mobile tiene AppBar del ErpLayout)
        if (isDesktop)
          AppHeader(
            title: 'Compromisos',
            subtitle: '${_compromisos.length} registro${_compromisos.length != 1 ? 's' : ''}',
            action: ElevatedButton.icon(
              onPressed: _crearCompromiso,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo Compromiso'),
            ),
          ),

        // Summary Cards
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildSummaryCards(),
        ),

        // Tabs: Lista, Calendario, Flujo de caja
        Material(
          color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
          child: TabBar(
            controller: _tabController,
            onTap: (_) => setState(() {}),
            isScrollable: false,
            tabs: const [
              Tab(icon: Icon(Icons.list_alt), text: 'Lista'),
              Tab(icon: Icon(Icons.calendar_month), text: 'Calendario'),
              Tab(icon: Icon(Icons.trending_up), text: 'Flujo de caja'),
            ],
          ),
        ),

        const Divider(height: 1),

        // Contenido según pestaña activa
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // --- Pestaña 1: Lista ---
              _buildListaTab(isDesktop, isDark),

              // --- Pestaña 2: Calendario completo ---
              CalendarioMensualWidget(
                unidadGestionId: _unidadGestionId,
              ),

              // --- Pestaña 3: Flujo de caja ---
              FlujoCajaWidget(
                unidadGestionId: _unidadGestionId,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Pestaña de lista con filtros y tabla/tarjetas
  Widget _buildListaTab(bool isDesktop, bool isDark) {
    return Column(
      children: [
        // Filtros
        _buildFiltros(isDark),

        const Divider(height: 1),

        // Contenido principal
        Expanded(
          child: _isLoading
              ? SkeletonLoader.table(rows: 6, columns: 5)
              : _compromisos.isEmpty
                  ? const EmptyState(
                      icon: Icons.event_note,
                      title: 'No hay compromisos registrados',
                      subtitle: 'Creá un compromiso para empezar',
                    )
                  : isDesktop
                      ? _buildDesktopContent()
                      : _buildMobileContent(),
        ),
      ],
    );
  }

  // ─── Summary Cards ───

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 800 ? 4 : 2;
        final cards = [
          SummaryCard(
            title: 'Total compromisos',
            value: Format.moneyNoDecimals(_totalCompromisos),
            icon: Icons.account_balance_wallet,
            color: AppColors.primary,
          ),
          SummaryCard(
            title: 'Pagado',
            value: Format.moneyNoDecimals(_totalPagado),
            icon: Icons.check_circle,
            color: AppColors.success,
          ),
          SummaryCard(
            title: 'Pendiente',
            value: Format.moneyNoDecimals(_totalPendiente),
            icon: Icons.schedule,
            color: AppColors.info,
          ),
          SummaryCard(
            title: 'Vencidos',
            value: '$_vencidosCount',
            icon: Icons.warning_amber,
            color: AppColors.danger,
          ),
        ];

        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: crossCount == 4 ? 3.2 : 2.8,
          children: cards,
        );
      },
    );
  }

  // ─── Filtros ───

  Widget _buildFiltros(bool isDark) {
    final bgColor = isDark ? AppColors.cardDark : AppColors.backgroundLight;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      color: bgColor,
      child: Column(
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _buildDropdown<int?>(
                label: 'Entidad',
                value: _entidadPlantelId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ..._entidades.map((e) => DropdownMenuItem(
                        value: e['id'] as int,
                        child: Text(e['nombre'] as String),
                      )),
                ],
                onChanged: (v) => setState(() => _entidadPlantelId = v),
              ),
              _buildDropdown<String?>(
                label: 'Tipo',
                value: _tipoFiltro,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'INGRESO', child: Text('Ingreso')),
                  DropdownMenuItem(value: 'EGRESO', child: Text('Egreso')),
                ],
                onChanged: (v) => setState(() => _tipoFiltro = v),
                width: 140,
              ),
              _buildDropdown<bool?>(
                label: 'Estado',
                value: _activoFiltro,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: true, child: Text('Activo')),
                  DropdownMenuItem(value: false, child: Text('Pausado')),
                ],
                onChanged: (v) => setState(() => _activoFiltro = v),
                width: 140,
              ),
              _buildDropdown<bool?>(
                label: 'Origen',
                value: _origenAcuerdoFiltro,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: true, child: Text('Acuerdos')),
                  DropdownMenuItem(value: false, child: Text('Manuales')),
                ],
                onChanged: (v) => setState(() => _origenAcuerdoFiltro = v),
                width: 150,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _cargarCompromisos,
                icon: const Icon(Icons.filter_list, size: 18),
                label: const Text('Filtrar'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _limpiarFiltros,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpiar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 180,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  void _limpiarFiltros() {
    setState(() {
      _unidadGestionId = null;
      _entidadPlantelId = null;
      _rolFiltro = null;
      _tipoFiltro = null;
      _origenAcuerdoFiltro = null;
      _activoFiltro = null;
    });
    _cargarCompromisos();
  }

  // ─── Desktop: Tabla + Calendario side by side ───

  Widget _buildDesktopContent() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 60% — Tabla
          Expanded(
            flex: 6,
            child: AppCard(
              padding: EdgeInsets.zero,
              child: _buildTabla(),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // 40% — Calendario + detalle día
          Expanded(
            flex: 4,
            child: Column(
              children: [
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _buildCalendario(),
                ),
                const SizedBox(height: AppSpacing.base),
                AppCard(
                  child: _buildDetalleDia(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mobile: Lista de cards ───

  Widget _buildMobileContent() {
    return RefreshIndicator(
      onRefresh: _cargarCompromisos,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.base),
        itemCount: _compromisos.length,
        itemBuilder: (context, index) {
          try {
            return _buildMobileCard(_compromisos[index]);
          } catch (e, stack) {
            AppDatabase.logLocalError(
              scope: 'compromisos_erp.render_item',
              error: e.toString(),
              stackTrace: stack,
              payload: {'index': index},
            );
            return const Card(
              child: ListTile(
                leading: Icon(Icons.warning, color: AppColors.danger),
                title: Text('Error al mostrar elemento'),
              ),
            );
          }
        },
      ),
    );
  }

  // ─── Tabla ERP ───

  Widget _buildTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Entidad')),
            DataColumn(label: Text('Monto'), numeric: true),
            DataColumn(label: Text('Frecuencia')),
            DataColumn(label: Text('Cuotas')),
            DataColumn(label: Text('Origen')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: _compromisos.map(_buildTablaRow).toList(),
        ),
      ),
    );
  }

  DataRow _buildTablaRow(Map<String, dynamic> c) {
    final activo = c['activo'] == 1;
    final tipo = c['tipo'] as String;
    final cuotas = c['cuotas'];
    final cuotasConf = c['cuotas_confirmadas'] ?? 0;
    final esDeAcuerdo = c['es_de_acuerdo'] == true;
    final entidad = c['entidad_nombre'] as String? ?? '—';

    return DataRow(
      onSelectChanged: (_) => _verDetalle(c['id'] as int),
      cells: [
        DataCell(Text(c['nombre'] ?? '', style: AppTextStyles.tableText())),
        DataCell(_tipoBadge(tipo)),
        DataCell(Text(entidad, style: AppTextStyles.tableText())),
        DataCell(Text(
          Format.money(c['monto'] ?? 0),
          style: AppTextStyles.tableText(),
          textAlign: TextAlign.right,
        )),
        DataCell(Text(c['frecuencia'] ?? '', style: AppTextStyles.tableText())),
        DataCell(Text(
          cuotas != null ? '$cuotasConf/$cuotas' : '—',
          style: AppTextStyles.tableText(),
        )),
        DataCell(_origenBadge(esDeAcuerdo)),
        DataCell(_estadoBadge(activo)),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              tooltip: 'Ver detalle',
              onPressed: () => _verDetalle(c['id'] as int),
            ),
            IconButton(
              icon: Icon(
                activo ? Icons.pause_outlined : Icons.play_arrow_outlined,
                size: 18,
              ),
              tooltip: activo ? 'Pausar' : 'Reactivar',
              onPressed: () => _pausarReactivar(c['id'] as int, activo),
            ),
          ],
        )),
      ],
    );
  }

  // ─── Mobile Card ───

  Widget _buildMobileCard(Map<String, dynamic> c) {
    final activo = c['activo'] == 1;
    final tipo = c['tipo'] as String;
    final cuotas = c['cuotas'];
    final cuotasConf = c['cuotas_confirmadas'] ?? 0;
    final esDeAcuerdo = c['es_de_acuerdo'] == true;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      onTap: () => _verDetalle(c['id'] as int),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c['nombre'] ?? '',
                  style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _tipoBadge(tipo),
              const SizedBox(width: AppSpacing.sm),
              _estadoBadge(activo),
            ],
          ),
          if (esDeAcuerdo) ...[
            const SizedBox(height: AppSpacing.sm),
            _origenBadge(true),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Monto', style: AppTextStyles.caption()),
                    Text(Format.money(c['monto'] ?? 0),
                        style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (cuotas != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cuotas', style: AppTextStyles.caption()),
                      Text('$cuotasConf/$cuotas', style: AppTextStyles.body()),
                    ],
                  ),
                ),
            ],
          ),
          if (cuotas != null) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: cuotasConf / cuotas,
              backgroundColor: AppColors.borderLight,
              color: tipo == 'INGRESO' ? AppColors.success : AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  // ─── Calendario ───

  Widget _buildCalendario() {
    return TableCalendar<Map<String, dynamic>>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: CalendarFormat.month,
      eventLoader: _getEventsForDay,
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        markerDecoration: const BoxDecoration(
          color: AppColors.info,
          shape: BoxShape.circle,
        ),
        markerSize: 6,
        markersMaxCount: 3,
      ),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        _actualizarDiaSeleccionado();
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
        _cargarCalendario();
      },
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return null;
          return Positioned(
            bottom: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: events.take(3).map((e) {
                final estado = e['cuota_estado'] as String? ?? 'ESPERADO';
                final fecha = e['fecha_programada'] as String? ?? '';
                final hoyStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                Color dotColor;
                if (estado == 'CONFIRMADO') {
                  dotColor = AppColors.success;
                } else if (fecha.compareTo(hoyStr) < 0) {
                  dotColor = AppColors.danger;
                } else if (fecha == hoyStr) {
                  dotColor = AppColors.warning;
                } else {
                  dotColor = AppColors.info;
                }
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  // ─── Panel detalle del día ───

  Widget _buildDetalleDia() {
    final fecha = _selectedDay ?? DateTime.now();
    final formato = DateFormat('d MMMM yyyy', 'es_AR');

    if (_cuotasDiaSeleccionado.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formato.format(fecha), style: AppTextStyles.sectionSubtitle()),
          const SizedBox(height: AppSpacing.md),
          Text('Sin compromisos para este día', style: AppTextStyles.caption()),
        ],
      );
    }

    double totalDia = 0;
    for (final c in _cuotasDiaSeleccionado) {
      totalDia += (c['monto_esperado'] as num?)?.toDouble() ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(formato.format(fecha), style: AppTextStyles.sectionSubtitle()),
            ),
            Text(
              Format.moneyNoDecimals(totalDia),
              style: AppTextStyles.bigNumber(color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...List.generate(_cuotasDiaSeleccionado.length, (i) {
          final cuota = _cuotasDiaSeleccionado[i];
          final nombre = cuota['compromiso_nombre'] as String? ?? cuota['nombre'] as String? ?? '—';
          final monto = (cuota['monto_esperado'] as num?)?.toDouble() ?? 0;
          final estado = cuota['cuota_estado'] as String? ?? 'ESPERADO';

          StatusBadge badge;
          if (estado == 'CONFIRMADO') {
            badge = const StatusBadge.pagado();
          } else {
            final fechaStr = cuota['fecha_programada'] as String? ?? '';
            final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
            if (fechaStr.compareTo(hoy) < 0) {
              badge = const StatusBadge.vencido();
            } else if (fechaStr == hoy) {
              badge = const StatusBadge.proximo();
            } else {
              badge = const StatusBadge.pendiente();
            }
          }

          return Padding(
            padding: EdgeInsets.only(top: i > 0 ? AppSpacing.sm : 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(nombre, style: AppTextStyles.body()),
                ),
                const SizedBox(width: AppSpacing.sm),
                badge,
                const SizedBox(width: AppSpacing.md),
                Text(
                  Format.moneyNoDecimals(monto),
                  style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─── Badges ───

  Widget _tipoBadge(String tipo) {
    return StatusBadge(
      label: tipo,
      type: tipo == 'INGRESO' ? StatusType.success : StatusType.danger,
    );
  }

  Widget _estadoBadge(bool activo) {
    return StatusBadge(
      label: activo ? 'ACTIVO' : 'PAUSADO',
      type: activo ? StatusType.info : StatusType.neutral,
    );
  }

  Widget _origenBadge(bool esDeAcuerdo) {
    return StatusBadge(
      label: esDeAcuerdo ? 'ACUERDO' : 'MANUAL',
      type: esDeAcuerdo ? StatusType.info : StatusType.neutral,
      icon: esDeAcuerdo ? Icons.handshake : Icons.edit,
    );
  }

  // ─── Acciones ───

  Future<void> _pausarReactivar(int id, bool activo) async {
    try {
      if (activo) {
        await _service.pausarCompromiso(id);
      } else {
        await _service.reactivarCompromiso(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(activo ? 'Compromiso pausado' : 'Compromiso reactivado')),
        );
      }
      _cargarCompromisos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al procesar. Intente nuevamente.')),
        );
      }
    }
  }

  Future<void> _crearCompromiso() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CrearCompromisoPage()),
    );
    if (resultado == true) {
      _cargarCompromisos();
      _cargarCalendario();
    }
  }

  Future<void> _verDetalle(int id) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DetalleCompromisoPage(compromisoId: id)),
    );
    if (resultado == true) {
      _cargarCompromisos();
      _cargarCalendario();
    }
  }
}
