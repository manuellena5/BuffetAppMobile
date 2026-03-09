import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/dao/db.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/format.dart';
import '../../../widgets/status_badge.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../../layout/erp_layout.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../widgets/ayuda_tesoreria_dialog.dart';
import '../widgets/calendario_mensual_widget.dart';
import '../widgets/flujo_caja_widget.dart';
import 'confirmar_movimiento_page.dart';
import 'crear_compromiso_page.dart';
import 'detalle_compromiso_page.dart';

/// Página principal de gestión de compromisos financieros.
/// Muestra lista de compromisos con filtros y acciones.
class CompromisosPage extends StatefulWidget {
  const CompromisosPage({super.key});

  @override
  State<CompromisosPage> createState() => _CompromisosPageState();
}

class _CompromisosPageState extends State<CompromisosPage>
    with SingleTickerProviderStateMixin {
  final _compromisosService = CompromisosService.instance;

  List<Map<String, dynamic>> _compromisos = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _entidades = []; // Para dropdown de entidades

  // FASE 22.5: Filtros visibles (no modal)
  int? _unidadGestionId;
  int? _entidadPlantelId; // Filtro por jugador/DT
  String? _rolFiltro; // 'DT', 'JUGADOR', 'OTRO', null = todos
  String? _tipoFiltro; // 'INGRESO', 'EGRESO', null = todos
  bool?
      _origenAcuerdoFiltro; // true = solo acuerdos, false = solo manuales, null = todos
  bool? _activoFiltro; // true = activos, false = pausados, null = todos

  // Vista
  bool _vistaTabla = true; // false = tarjetas, true = tabla (por defecto)

  // Selector de mes para la vista lista
  DateTime _mesActualLista = DateTime(DateTime.now().year, DateTime.now().month);

  // Tabs: lista, calendario, flujo de caja
  late final TabController _tabController;
  final _calendarioMensualKey = GlobalKey<State>();
  final _flujoCajaKey = GlobalKey<State>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarEntidades();
    _cargarCompromisos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          _entidades =
              entidades.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      // Error silencioso, los filtros son opcionales
    }
  }

  Future<void> _cargarCompromisos() async {
    setState(() => _isLoading = true);

    try {
      // FASE 22.5: Usar vista completa con JOINs en lugar de enriquecer manualmente
      final db = await AppDatabase.instance();

      // Construir query dinámico con filtros
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      if (_unidadGestionId != null) {
        whereConditions.add('unidad_gestion_id = ?');
        whereArgs.add(_unidadGestionId);
      }

      if (_tipoFiltro != null) {
        whereConditions.add('tipo = ?');
        whereArgs.add(_tipoFiltro);
      }

      if (_activoFiltro != null) {
        whereConditions.add('activo = ?');
        whereArgs.add(_activoFiltro! ? 1 : 0);
      }

      if (_entidadPlantelId != null) {
        whereConditions.add('entidad_plantel_id = ?');
        whereArgs.add(_entidadPlantelId);
      }

      if (_rolFiltro != null) {
        whereConditions.add('entidad_rol = ?');
        whereArgs.add(_rolFiltro);
      }

      final whereClause =
          whereConditions.isEmpty ? null : whereConditions.join(' AND ');

      final compromisosRaw = await db.query(
        'v_compromisos_completo',
        where: whereClause,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'fecha_inicio DESC',
      );

      var compromisos =
          compromisosRaw.map((c) => Map<String, dynamic>.from(c)).toList();

      // Enriquecer con información de origen (si viene de acuerdo)
      for (final comp in compromisos) {
        final acuerdoId = comp['acuerdo_id'];
        if (acuerdoId != null) {
          final esDeAcuerdo = await _compromisosService
              .esCompromisoPorAcuerdo(comp['id'] as int);
          comp['es_de_acuerdo'] = esDeAcuerdo;
        } else {
          comp['es_de_acuerdo'] = false;
        }
      }

      // Filtrar por origen de acuerdo
      if (_origenAcuerdoFiltro != null) {
        compromisos = compromisos
            .where((c) => c['es_de_acuerdo'] == _origenAcuerdoFiltro)
            .toList();
      }

      setState(() {
        _compromisos = compromisos;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'compromisos_page.cargar_compromisos',
        error: e.toString(),
        stackTrace: stack,
      );
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Error al cargar compromisos. Intente nuevamente.')),
        );
      }
    }
  }

  void _aplicarFiltros() {
    _cargarCompromisos();
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

  Future<void> _pausarReactivar(int id, bool activo) async {
    try {
      if (activo) {
        await _compromisosService.pausarCompromiso(id);
      } else {
        await _compromisosService.reactivarCompromiso(id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(activo ? 'Compromiso pausado' : 'Compromiso reactivado'),
          ),
        );
      }

      _cargarCompromisos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error al procesar. Intente nuevamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpLayout(
      title: 'Acuerdos y Compromisos',
      currentRoute: '/compromisos',
      actions: [
        // Toggle vista tabla/tarjetas (solo en pestaña lista)
        if (_tabController.index == 0)
          IconButton(
            icon: Icon(_vistaTabla ? Icons.view_list : Icons.table_chart),
            onPressed: () {
              setState(() => _vistaTabla = !_vistaTabla);
            },
            tooltip: _vistaTabla ? 'Vista de tarjetas' : 'Vista de tabla',
          ),
        // Botón de ayuda
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: '¿Qué es cada concepto?',
          onPressed: () => AyudaTesoreriaDialog.show(context),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearCompromiso,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Compromiso'),
      ),
      body: Column(
        children: [
          // Tabs: Lista, Calendario y Flujo de caja
          Material(
            color: Theme.of(context).colorScheme.surface,
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

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // --- Pestaña 1: Lista ---
                Column(
                  children: [
                    // Selector de mes (carrusel)
                    _buildSelectorMesLista(),

                    // FASE 22.5: Filtros visibles
                    _buildFiltrosVisibles(),
                    const Divider(height: 1),

                    // Contenido principal
                    Expanded(
                      child: _isLoading
                          ? SkeletonLoader.table(rows: 6, columns: 5)
                          : _compromisosMesFiltrado.isEmpty
                              ? const EmptyState(
                                  icon: Icons.event_note,
                                  title: 'No hay compromisos registrados',
                                  subtitle: 'Creá un compromiso para empezar',
                                )
                              : RefreshIndicator(
                                  onRefresh: _cargarCompromisos,
                                  child: _vistaTabla
                                      ? _buildTabla()
                                      : Align(
                                          alignment: Alignment.topCenter,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 1000),
                                            child: _buildTarjetas(),
                                          ),
                                        ),
                                ),
                    ),
                  ],
                ),

                // --- Pestaña 2: Calendario mensual ---
                CalendarioMensualWidget(
                  key: _calendarioMensualKey,
                  unidadGestionId: _unidadGestionId,
                ),

                // --- Pestaña 3: Flujo de caja ---
                FlujoCajaWidget(
                  key: _flujoCajaKey,
                  unidadGestionId: _unidadGestionId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _cambiarMesLista(int delta) {
    setState(() {
      _mesActualLista = DateTime(_mesActualLista.year, _mesActualLista.month + delta);
    });
  }

  Widget _buildSelectorMesLista() {
    return Container(
      color: context.appColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _cambiarMesLista(-1),
          ),
          Text(
            DateFormat('MMMM yyyy', 'es_ES').format(_mesActualLista),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _cambiarMesLista(1),
          ),
        ],
      ),
    );
  }

  /// Filtra compromisos por el mes seleccionado en la vista lista.
  /// Un compromiso se muestra si su período (fecha_inicio → fecha_fin | hoy)
  /// intersecta el mes seleccionado.
  List<Map<String, dynamic>> get _compromisosMesFiltrado {
    final mesInicio = DateTime(_mesActualLista.year, _mesActualLista.month, 1);
    final mesFin = DateTime(_mesActualLista.year, _mesActualLista.month + 1, 0);
    final mesInicioStr = DateFormat('yyyy-MM-dd').format(mesInicio);
    final mesFinStr = DateFormat('yyyy-MM-dd').format(mesFin);

    return _compromisos.where((c) {
      final inicio = c['fecha_inicio'] as String? ?? '';
      final fin = c['fecha_fin'] as String?;
      // Si no hay fecha de inicio, incluir siempre
      if (inicio.isEmpty) return true;
      // Compromiso empieza después del mes → no incluir
      if (inicio.compareTo(mesFinStr) > 0) return false;
      // Si tiene fecha_fin y terminó antes del mes → no incluir
      if (fin != null && fin.isNotEmpty && fin.compareTo(mesInicioStr) < 0) return false;
      return true;
    }).toList();
  }

  /// FASE 22.5: Sección de filtros visibles (dropdowns en lugar de modal)
  Widget _buildFiltrosVisibles() {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      color: colors.bgElevated,
      child: ResponsiveContainer(
        maxWidth: 1400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila de dropdowns
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Entidad
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _entidadPlantelId,
                    decoration: InputDecoration(
                      labelText: 'Entidad',
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: colors.bgSurface,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Todos')),
                      ..._entidades.map((e) => DropdownMenuItem<int?>(
                            value: e['id'] as int,
                            child: Text(e['nombre'] as String),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _entidadPlantelId = val);
                    },
                  ),
                ),

                // Rol
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _rolFiltro,
                    decoration: InputDecoration(
                      labelText: 'Rol',
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: colors.bgSurface,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: 'DT', child: Text('DT')),
                      DropdownMenuItem(
                          value: 'JUGADOR', child: Text('Jugador')),
                      DropdownMenuItem(value: 'OTRO', child: Text('Otro')),
                    ],
                    onChanged: (val) {
                      setState(() => _rolFiltro = val);
                    },
                  ),
                ),

                // Tipo
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _tipoFiltro,
                    decoration: InputDecoration(
                      labelText: 'Tipo',
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: colors.bgSurface,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(
                          value: 'INGRESO', child: Text('Ingreso')),
                      DropdownMenuItem(value: 'EGRESO', child: Text('Egreso')),
                    ],
                    onChanged: (val) {
                      setState(() => _tipoFiltro = val);
                    },
                  ),
                ),

                // Estado (activo/pausado)
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<bool?>(
                    initialValue: _activoFiltro,
                    decoration: InputDecoration(
                      labelText: 'Estado',
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: colors.bgSurface,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: true, child: Text('Activo')),
                      DropdownMenuItem(value: false, child: Text('Pausado')),
                    ],
                    onChanged: (val) {
                      setState(() => _activoFiltro = val);
                    },
                  ),
                ),

                // Origen acuerdo
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<bool?>(
                    initialValue: _origenAcuerdoFiltro,
                    decoration: InputDecoration(
                      labelText: 'Origen',
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: colors.bgSurface,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(
                          value: true, child: Text('Solo acuerdos')),
                      DropdownMenuItem(
                          value: false, child: Text('Solo manuales')),
                    ],
                    onChanged: (val) {
                      setState(() => _origenAcuerdoFiltro = val);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Botones de acción
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _aplicarFiltros,
                  icon: const Icon(Icons.filter_list),
                  label: const Text('Filtrar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ingreso,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpiar'),
                ),
                const Spacer(),
                Text(
                  '${_compromisosMesFiltrado.length} resultado${_compromisosMesFiltrado.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── STYLED TABLE ──────────────────────────────────────────────────────────
  Widget _buildTabla() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
          decoration: AppDecorations.cardOf(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: context.appColors.border)),
                ),
                child: Row(
                  children: [
                    _tableHeader('NOMBRE', flex: 3),
                    _tableHeader('TIPO', flex: 1),
                    _tableHeader('ENTIDAD', flex: 2),
                    _tableHeader('MONTO', flex: 2),
                    _tableHeader('FRECUENCIA', flex: 1),
                    _tableHeader('PRÓX. VTO', flex: 2),
                    _tableHeader('CUOTAS', flex: 1),
                    _tableHeader('ORIGEN', flex: 1),
                    _tableHeader('ESTADO', flex: 1),
                    _tableHeader('', flex: 2), // acciones
                  ],
                ),
              ),
              // Rows
              ..._compromisosMesFiltrado.asMap().entries.map((entry) {
                try {
                  return _buildStyledRow(entry.value, entry.key);
                } catch (e, stack) {
                  AppDatabase.logLocalError(
                    scope: 'compromisos_page.render_fila_tabla',
                    error: e.toString(),
                    stackTrace: stack,
                    payload: {'compromiso_id': entry.value['id']},
                  );
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: AppColors.advertencia, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Error al mostrar compromiso', style: AppText.bodyMd),
                      ],
                    ),
                  );
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(label, style: AppText.label),
    );
  }

  Widget _buildStyledRow(Map<String, dynamic> c, int index) {
    final id = c['id'] as int;
    final nombre = c['nombre']?.toString() ?? 'Sin nombre';
    final activo = c['activo'] == 1;
    final tipo = (c['tipo'] as String?) ?? 'EGRESO';
    final cuotas = c['cuotas'];
    final cuotasConfirmadas = c['cuotas_confirmadas'] ?? 0;
    final esDeAcuerdo = c['es_de_acuerdo'] == true;
    final entidadNombre = c['entidad_nombre'] as String? ?? '—';
    final esIngreso = tipo == 'INGRESO';
    final tipoColor = esIngreso ? AppColors.ingreso : AppColors.egreso;

    // Iniciales para avatar
    final iniciales = nombre.length >= 2
        ? nombre.substring(0, 2).toUpperCase()
        : nombre.toUpperCase();

    return InkWell(
      onTap: () => _verDetalle(id),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: context.appColors.border.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            // Nombre con avatar
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: esIngreso
                          ? context.appColors.ingresoDim
                          : context.appColors.infoDim,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      iniciales,
                      style: AppText.label.copyWith(
                        color: esIngreso
                            ? AppColors.ingresoLight
                            : AppColors.infoLight,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      nombre,
                      style: AppText.titleSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Tipo
            Expanded(
              flex: 1,
              child: StatusBadge(
                label: tipo,
                type: esIngreso ? StatusType.success : StatusType.danger,
              ),
            ),

            // Entidad
            Expanded(
              flex: 2,
              child: Text(
                entidadNombre,
                style: AppText.bodyMd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Monto
            Expanded(
              flex: 2,
              child: Text(
                Format.money(c['monto'] ?? 0),
                style: AppText.monoBold.copyWith(color: tipoColor),
              ),
            ),

            // Frecuencia
            Expanded(
              flex: 1,
              child: Text(c['frecuencia']?.toString() ?? '—', style: AppText.bodyMd),
            ),

            // Próximo vencimiento
            Expanded(
              flex: 2,
              child: _buildProximoVencimiento(id),
            ),

            // Cuotas
            Expanded(
              flex: 1,
              child: Text(
                cuotas != null ? '$cuotasConfirmadas/$cuotas' : '—',
                style: AppText.monoSm,
              ),
            ),

            // Origen
            Expanded(
              flex: 1,
              child: StatusBadge(
                label: esDeAcuerdo ? 'Acuerdo' : 'Manual',
                type: esDeAcuerdo ? StatusType.info : StatusType.neutral,
              ),
            ),

            // Estado
            Expanded(
              flex: 1,
              child: StatusBadge(
                label: activo ? 'Activo' : 'Pausado',
                type: activo ? StatusType.success : StatusType.neutral,
              ),
            ),

            // Acciones
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (activo)
                    _ghostButton(
                      esIngreso ? 'Cobrar' : 'Pagar',
                      () => _registrarMovimiento(c),
                      color: tipoColor,
                    ),
                  _ghostButton(
                    activo ? 'Pausar' : 'Reactivar',
                    () => _pausarReactivar(id, activo),
                    color: AppColors.advertencia,
                  ),
                  _ghostButton('Ver', () => _verDetalle(id)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostButton(String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Text(
          label,
          style: AppText.labelMd.copyWith(color: c),
        ),
      ),
    );
  }

  Widget _buildTarjetas() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _compromisosMesFiltrado.length,
      itemBuilder: (context, index) {
        final c = _compromisosMesFiltrado[index];
        return _buildTarjeta(c);
      },
    );
  }

  Widget _buildTarjeta(Map<String, dynamic> c) {
    final activo = c['activo'] == 1;
    final tipo = c['tipo'] as String;
    final cuotas = c['cuotas'];
    final cuotasConfirmadas = c['cuotas_confirmadas'] ?? 0;
    final esDeAcuerdo = c['es_de_acuerdo'] == true;
    final esIngreso = tipo == 'INGRESO';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: AppDecorations.cardOf(context).copyWith(
        boxShadow: AppShadows.cardFor(context),
      ),
      child: InkWell(
        onTap: () => _verDetalle(c['id'] as int),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: nombre, tipo y estado
              Row(
                children: [
                  Expanded(
                    child: Text(c['nombre'] ?? '', style: AppText.titleSm),
                  ),
                  _buildTipoBadge(tipo),
                  const SizedBox(width: 8),
                  _buildEstadoBadge(activo),
                ],
              ),

              // Indicador de origen
              if (esDeAcuerdo) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.handshake,
                        size: 16, color: AppColors.accentLight),
                    const SizedBox(width: 4),
                    Text(
                      'Generado desde Acuerdo',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accentLight,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Monto y frecuencia
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Monto', style: AppText.caption),
                        Text(
                          Format.money(c['monto'] ?? 0),
                          style: AppText.monoBold,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Frecuencia', style: AppText.caption),
                        Text(c['frecuencia'] ?? '', style: AppText.bodyMd),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Próximo vencimiento
              _buildProximoVencimiento(c['id'] as int),

              if (cuotas != null) ...[
                const SizedBox(height: 12),
                // Barra de progreso de cuotas
                LinearProgressIndicator(
                  value: cuotasConfirmadas / cuotas,
                  backgroundColor: AppColors.border,
                  color: esIngreso ? AppColors.ingreso : AppColors.info,
                ),
                const SizedBox(height: 4),
                Text(
                  '$cuotasConfirmadas de $cuotas cuotas confirmadas',
                  style: AppText.caption,
                ),
                const SizedBox(height: 8),
                // Estado financiero (pagado/remanente)
                _buildEstadoFinanciero(c['id'] as int),
              ],

              const SizedBox(height: 12),

              // Acciones
              Row(
                children: [
                  // Botón registrar cobro/pago
                  if (activo)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _registrarMovimiento(c),
                        icon: Icon(
                          esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 18,
                        ),
                        label: Text(esIngreso ? 'Cobrar' : 'Pagar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: esIngreso ? AppColors.ingreso : AppColors.egreso,
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  if (activo) const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _pausarReactivar(c['id'] as int, activo),
                    icon: Icon(activo ? Icons.pause : Icons.play_arrow, size: 18),
                    label: Text(activo ? 'Pausar' : 'Reactivar'),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _verDetalle(c['id'] as int),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Ver detalle',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoBadge(String tipo) {
    final esIngreso = tipo == 'INGRESO';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: esIngreso ? AppColors.ingresoDim : AppColors.egresoDim,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tipo,
        style: TextStyle(
          color: esIngreso ? AppColors.ingreso : AppColors.egreso,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEstadoBadge(bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activo ? AppColors.infoDim : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        activo ? 'ACTIVO' : 'PAUSADO',
        style: TextStyle(
          color: activo ? AppColors.info : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildProximoVencimiento(int compromisoId) {
    return FutureBuilder<DateTime?>(
      future: _compromisosService.calcularProximoVencimiento(compromisoId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const Text(
            'Sin próximo vencimiento',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          );
        }

        final fecha = snapshot.data!;
        final formato = DateFormat('dd/MM/yyyy');
        final hoy = DateTime.now();
        final diferencia = fecha.difference(hoy).inDays;

        Color color = AppColors.textSecondary;
        String prefijo = '';

        if (diferencia < 0) {
          color = AppColors.egreso;
          prefijo = 'Vencido: ';
        } else if (diferencia <= 7) {
          color = AppColors.advertencia;
          prefijo = 'Próximo: ';
        } else {
          prefijo = 'Próximo: ';
        }

        return Text(
          '$prefijo${formato.format(fecha)}',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: diferencia <= 7 ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      },
    );
  }

  Widget _buildEstadoFinanciero(int compromisoId) {
    return FutureBuilder<Map<String, double>>(
      future: _calcularEstadoFinanciero(compromisoId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        final pagado = snapshot.data!['pagado'] ?? 0.0;
        final remanente = snapshot.data!['remanente'] ?? 0.0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.infoDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pagado',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Format.money(pagado),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ingreso,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: AppColors.border,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remanente',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Format.money(remanente),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.advertencia,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, double>> _calcularEstadoFinanciero(
      int compromisoId) async {
    final pagado = await _compromisosService.calcularMontoPagado(compromisoId);
    final remanente =
        await _compromisosService.calcularMontoRemanente(compromisoId);
    return {'pagado': pagado, 'remanente': remanente};
  }

  Future<void> _registrarMovimiento(Map<String, dynamic> c) async {
    final compromisoId = c['id'] as int;
    final tipo = c['tipo'] as String;
    final monto = (c['monto'] as num?)?.toDouble() ?? 0.0;
    final categoria = c['categoria'] as String? ?? '';

    // Calcular próximo vencimiento
    final proximoVenc = await _compromisosService.calcularProximoVencimiento(compromisoId);
    final fecha = proximoVenc ?? DateTime.now();

    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmarMovimientoPage(
          compromisoId: compromisoId,
          fechaVencimiento: fecha,
          montoSugerido: monto,
          tipo: tipo,
          categoria: categoria,
        ),
      ),
    );

    if (result == true) {
      _cargarCompromisos();
    }
  }

  Future<void> _crearCompromiso() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CrearCompromisoPage()),
    );

    if (resultado == true) {
      _cargarCompromisos();
    }
  }

  Future<void> _verDetalle(int compromisoId) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleCompromisoPage(compromisoId: compromisoId),
      ),
    );

    if (resultado == true) {
      _cargarCompromisos();
    }
  }
}
