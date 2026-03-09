import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/dao/db.dart';
import '../../../domain/models.dart';
import '../../shared/state/app_settings.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/summary_card.dart';
import '../../../widgets/status_badge.dart';
import '../../shared/format.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../tesoreria/services/cuenta_service.dart';
import 'crear_cuenta_page.dart';
import 'detalle_cuenta_page.dart';

/// Pantalla de listado de cuentas de fondos
class CuentasPage extends StatefulWidget {
  const CuentasPage({super.key});

  @override
  State<CuentasPage> createState() => _CuentasPageState();
}

class _CuentasPageState extends State<CuentasPage> {
  final _cuentaService = CuentaService();
  
  List<CuentaFondos> _cuentas = [];
  Map<int, double> _saldos = {};
  bool _cargando = true;
  bool _mostrarInactivas = false;
  bool _showAdvanced = false;
  String? _filtroTipo;

  @override
  void initState() {
    super.initState();
    _loadShowAdvanced();
    _cargarCuentas();
  }
  
  /// Carga el estado de las opciones avanzadas desde SharedPreferences
  Future<void> _loadShowAdvanced() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showAdvanced = prefs.getBool('show_advanced_options') ?? false;
      });
    }
  }

  Future<void> _cargarCuentas() async {
    try {
      setState(() => _cargando = true);
      
      final settings = context.read<AppSettings>();
      final unidadId = settings.disciplinaActivaId;
      
      if (unidadId == null) {
        if (mounted) {
          setState(() {
            _cuentas = [];
            _saldos = {};
            _cargando = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seleccione una unidad de gestión')),
          );
        }
        return;
      }

      // Cargar cuentas
      var cuentas = await _cuentaService.listarPorUnidad(
        unidadId,
        soloActivas: !_mostrarInactivas,
      );

      // Filtrar por tipo si se seleccionó
      if (_filtroTipo != null) {
        cuentas = cuentas.where((c) => c.tipo == _filtroTipo).toList();
      }

      // Cargar saldos
      final saldos = await _cuentaService.obtenerSaldosPorUnidad(unidadId);

      if (mounted) {
        setState(() {
          _cuentas = cuentas;
          _saldos = saldos;
          _cargando = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuentas_page.cargar',
        error: e,
        stackTrace: st,
      );
      
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar cuentas. Intentá nuevamente.'),
            backgroundColor: AppColors.egreso,
          ),
        );
      }
    }
  }

  void _navegarACrear() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CrearCuentaPage(),
      ),
    );
    
    if (resultado == true) {
      _cargarCuentas();
    }
  }

  void _navegarADetalle(CuentaFondos cuenta) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleCuentaPage(cuenta: cuenta),
      ),
    );
    
    if (resultado == true) {
      _cargarCuentas();
    }
  }

  void _toggleEstadoCuenta(CuentaFondos cuenta) async {
    try {
      if (cuenta.estadoCuenta == 'ACTIVA') {
        await _cuentaService.desactivar(cuenta.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cuenta desactivada')),
          );
        }
      } else if (cuenta.estadoCuenta == 'INACTIVA') {
        await _cuentaService.reactivar(cuenta.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cuenta reactivada')),
          );
        }
      }
      _cargarCuentas();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuentas_page.toggle_estado',
        error: e,
        stackTrace: st,
        payload: {'cuenta_id': cuenta.id},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cambiar el estado. Intentá nuevamente.'),
            backgroundColor: AppColors.egreso,
          ),
        );
      }
    }
  }

  IconData _iconoPorTipo(String tipo) {
    switch (tipo) {
      case 'BANCO':
        return Icons.account_balance;
      case 'BILLETERA':
        return Icons.account_balance_wallet;
      case 'CAJA':
        return Icons.money;
      case 'INVERSION':
        return Icons.trending_up;
      default:
        return Icons.attach_money;
    }
  }

  Color _colorPorTipo(String tipo) {
    switch (tipo) {
      case 'BANCO':
        return AppColors.info;
      case 'BILLETERA':
        return AppColors.accentLight;
      case 'CAJA':
        return AppColors.ingreso;
      case 'INVERSION':
        return AppColors.advertencia;
      default:
        return AppColors.textMuted;
    }
  }

  // ─── KPIs derivados ────────────────────────────────────────────────────
  double get _totalDisponible {
    double sum = 0;
    for (final c in _cuentas) {
      if (c.estadoCuenta == 'ACTIVA') sum += _saldos[c.id] ?? 0;
    }
    return sum;
  }

  int get _countActivas => _cuentas.where((c) => c.estadoCuenta == 'ACTIVA').length;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;

    return ErpLayout(
      currentRoute: '/cuentas',
      title: 'Cuentas / Fondos',
      showAdvanced: _showAdvanced,
      actions: [
        // Filtro por tipo
        PopupMenuButton<String?>(
          icon: const Icon(Icons.filter_list),
          tooltip: 'Filtrar por tipo',
          onSelected: (tipo) {
            setState(() => _filtroTipo = tipo);
            _cargarCuentas();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: null, child: Text('Todas')),
            const PopupMenuItem(value: 'BANCO', child: Text('Banco')),
            const PopupMenuItem(value: 'BILLETERA', child: Text('Billetera')),
            const PopupMenuItem(value: 'CAJA', child: Text('Caja')),
            const PopupMenuItem(value: 'INVERSION', child: Text('Inversión')),
          ],
        ),
        
        // Mostrar/ocultar inactivas
        IconButton(
          icon: Icon(
            _mostrarInactivas ? Icons.visibility : Icons.visibility_off,
            color: _mostrarInactivas ? AppColors.advertencia : null,
          ),
          tooltip: _mostrarInactivas ? 'Ocultar inactivas/liquidadas' : 'Mostrar inactivas/liquidadas',
          onPressed: () {
            setState(() => _mostrarInactivas = !_mostrarInactivas);
            _cargarCuentas();
          },
        ),
        
        // Refrescar
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _cargarCuentas,
        ),
      ],
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: _navegarACrear,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Nueva Cuenta'),
            ),
      body: _cargando
          ? SkeletonLoader.cards(count: 3)
          : RefreshIndicator(
              onRefresh: _cargarCuentas,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.contentPadding),
                children: [
                  if (isDesktop)
                    AppHeader(
                      title: 'Cuentas / Fondos',
                      subtitle: '${_cuentas.length} cuentas',
                      action: FilledButton.icon(
                        onPressed: _navegarACrear,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva Cuenta'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildKpis(isDesktop),
                  const SizedBox(height: AppSpacing.md),
                  _buildFiltroEstado(),
                  const SizedBox(height: AppSpacing.md),
                  _cuentas.isEmpty
                      ? EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          title: _filtroTipo != null
                              ? 'No hay cuentas de tipo $_filtroTipo'
                              : 'No hay cuentas registradas',
                          subtitle: _filtroTipo == null
                              ? 'Creá tu primera cuenta para comenzar'
                              : null,
                        )
                      : _buildListado(),
                ],
              ),
            ),
    );
  }

  Widget _buildFiltroEstado() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('Solo activas'),
            selected: !_mostrarInactivas,
            onSelected: (_) {
              if (_mostrarInactivas) {
                setState(() => _mostrarInactivas = false);
                _cargarCuentas();
              }
            },
            avatar: const Icon(Icons.check_circle_outline, size: 16),
            selectedColor: AppColors.ingreso.withValues(alpha: 0.15),
            checkmarkColor: AppColors.ingreso,
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Mostrar inactivas y liquidadas'),
            selected: _mostrarInactivas,
            onSelected: (_) {
              if (!_mostrarInactivas) {
                setState(() => _mostrarInactivas = true);
                _cargarCuentas();
              }
            },
            avatar: const Icon(Icons.visibility_outlined, size: 16),
            selectedColor: AppColors.advertencia.withValues(alpha: 0.15),
            checkmarkColor: AppColors.advertencia,
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(bool isDesktop) {
    final totalColor =
        _totalDisponible >= 0 ? AppColors.ingreso : AppColors.egreso;

    final cards = [
      SummaryCard(
        title: 'TOTAL DISPONIBLE',
        value: Format.moneyNoDecimals(_totalDisponible),
        icon: Icons.account_balance_wallet,
        color: totalColor,
      ),
      SummaryCard(
        title: 'CUENTAS ACTIVAS',
        value: '$_countActivas',
        icon: Icons.credit_card,
        color: AppColors.info,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map((c) => Expanded(
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: c)))
            .toList(),
      );
    }
    return Column(
      children: cards
          .map((c) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: c))
          .toList(),
    );
  }

  Widget _buildListado() {
    return Column(
      children: _cuentas.map((cuenta) {
        final saldo = _saldos[cuenta.id] ?? 0.0;
        final color = _colorPorTipo(cuenta.tipo);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: InkWell(
            onTap: () => _navegarADetalle(cuenta),
            onLongPress: () => _mostrarOpciones(cuenta),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppDecorations.cardOf(context).copyWith(
                boxShadow: AppShadows.cardFor(context),
              ),
              child: Row(
                children: [
                  // Icono tipo
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    child: Icon(_iconoPorTipo(cuenta.tipo),
                        color: color, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Nombre + tipo + comisión + plazo fijo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cuenta.nombre,
                          style: AppText.titleSm.copyWith(
                            decoration: cuenta.estadoCuenta == 'ACTIVA'
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(cuenta.tipo, style: AppText.caption),
                            if (cuenta.tieneComision &&
                                cuenta.comisionPorcentaje != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Comisión: ${cuenta.comisionPorcentaje}%',
                                style: AppText.caption.copyWith(
                                    color: AppColors.advertencia),
                              ),
                            ],
                          ],
                        ),
                        // Vencimiento de plazo fijo
                        if (cuenta.tipo == 'INVERSION' && cuenta.fechaFinPlazo != null) ...[
                          const SizedBox(height: 4),
                          Builder(builder: (context) {
                            final fechaVenc = DateTime.tryParse(cuenta.fechaFinPlazo!);
                            if (fechaVenc == null) return const SizedBox.shrink();
                            final hoy = DateTime.now();
                            final diasRestantes = fechaVenc.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
                            final vencido = diasRestantes < 0;
                            final proximo = !vencido && diasRestantes <= 7;
                            final colorVenc = vencido
                                ? AppColors.egreso
                                : proximo
                                    ? AppColors.advertencia
                                    : AppColors.ingreso;
                            final textoVenc = vencido
                                ? 'Vencido el ${DateFormat('dd/MM/yyyy').format(fechaVenc)}'
                                : 'Vence: ${DateFormat('dd/MM/yyyy').format(fechaVenc)} ($diasRestantes días)';
                            return Row(
                              children: [
                                Icon(
                                  vencido ? Icons.warning_amber : Icons.event,
                                  size: 14,
                                  color: colorVenc,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    textoVenc,
                                    style: AppText.caption.copyWith(color: colorVenc),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                              ],
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  // Saldo + estado
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Format.money(saldo),
                        style: AppText.monoBold.copyWith(
                          color: saldo >= 0
                              ? AppColors.ingreso
                              : AppColors.egreso,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StatusBadge(
                        label: cuenta.estadoCuenta == 'ACTIVA'
                            ? 'Activa'
                            : cuenta.estadoCuenta == 'LIQUIDADA'
                                ? 'Liquidada'
                                : 'Inactiva',
                        type: cuenta.estadoCuenta == 'ACTIVA'
                            ? StatusType.success
                            : cuenta.estadoCuenta == 'LIQUIDADA'
                                ? StatusType.warning
                                : StatusType.neutral,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _mostrarOpciones(CuentaFondos cuenta) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility,
                  color: AppColors.textSecondary),
              title: Text('Ver detalle',
                  style: AppText.bodyLg
                      .copyWith(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _navegarADetalle(cuenta);
              },
            ),
            if (cuenta.estadoCuenta == 'ACTIVA' || cuenta.estadoCuenta == 'INACTIVA')
            ListTile(
              leading: Icon(
                cuenta.estadoCuenta == 'ACTIVA' ? Icons.block : Icons.check_circle,
                color: cuenta.estadoCuenta == 'ACTIVA'
                    ? AppColors.advertencia
                    : AppColors.ingreso,
              ),
              title: Text(
                cuenta.estadoCuenta == 'ACTIVA' ? 'Desactivar' : 'Reactivar',
                style: AppText.bodyLg
                    .copyWith(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleEstadoCuenta(cuenta);
              },
            ),
          ],
        ),
      ),
    );
  }
}
