import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/state/app_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../layout/erp_layout.dart';
import '../../../widgets/app_header.dart';
import '../../../data/dao/db.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/skeleton_loader.dart';
import 'crear_movimiento_page.dart';
import 'movimientos_list_page.dart';
import 'unidad_gestion_selector_page.dart';
import 'compromisos_erp_screen.dart';
import 'acuerdos_page.dart';
import 'plantel_page.dart';
import 'categorias_movimiento_page.dart';
import 'reportes_index_page.dart';
import 'dashboard_page.dart';
import 'saldos_iniciales_list_page.dart';
import '../../cuentas/pages/cuentas_page.dart';
import '../../shared/services/compromisos_service.dart';

/// Pantalla principal del módulo de Tesorería
/// Permite gestionar movimientos financieros independientes del buffet
class TesoreriaHomePage extends StatefulWidget {
  const TesoreriaHomePage({super.key});

  @override
  State<TesoreriaHomePage> createState() => _TesoreriaHomePageState();
}

class _TesoreriaHomePageState extends State<TesoreriaHomePage> {
  bool _loading = true;
  bool _needsUnidadGestionSetup = false;
  String? _unidadGestionNombre;
  bool _showAdvanced = false;
  int _compromisosVencidos = 0;
  int _compromisosProximos = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadShowAdvanced();
    _checkUnidadGestionAndLoad();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= AppSpacing.breakpointTablet;

    // Pantalla de selección de unidad de gestión si corresponde
    if (_needsUnidadGestionSetup) {
      return UnidadGestionSelectorPage(
        isInitialFlow: true,
        onComplete: () {
          setState(() {
            _needsUnidadGestionSetup = false;
          });
          // Recargar datos después de seleccionar unidad
          _checkUnidadGestionAndLoad();
        },
      );
    }

    return ErpLayout(
      currentRoute: '/tesoreria',
      title: 'Tesorería',
      showAdvanced: _showAdvanced,
      body: _loading
          ? SkeletonLoader.cards(count: 4)
          : Column(
              children: [
                if (isDesktop)
                  AppHeader(
                    title: 'Tesorería',
                    subtitle: _unidadGestionNombre ?? 'Sin unidad seleccionada',
                    trailing: [
                      ActionChip(
                        avatar: const Icon(Icons.business, size: 16),
                        label: Text(_unidadGestionNombre ?? 'Sin seleccionar'),
                        onPressed: _cambiarUnidadGestion,
                      ),
                    ],
                  ),
                Expanded(
                  child: ResponsiveContainer(
                    maxWidth: 1200,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            Icon(
                              Icons.account_balance,
                              size: 80,
                              color: AppColors.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tesorería',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Gestión de movimientos financieros\n${_unidadGestionNombre ?? 'Sin unidad seleccionada'}',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            // Tarjetas en Wrap responsivo
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              alignment: WrapAlignment.center,
                              children: [
                                _buildActionCard(
                                  context,
                                  icon: Icons.add_circle_outline,
                                  title: 'Crear Movimiento',
                                  subtitle: 'Registrar ingreso o egreso',
                                  color: AppColors.primary,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CrearMovimientoPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.list,
                                  title: 'Ver Movimientos',
                                  subtitle: 'Historial de operaciones',
                                  color: AppColors.primary,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const MovimientosListPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.event_note,
                                  title: 'Compromisos',
                                  subtitle: _compromisosVencidos > 0
                                      ? '$_compromisosVencidos vencido${_compromisosVencidos == 1 ? '' : 's'}'
                                      : _compromisosProximos > 0
                                          ? '$_compromisosProximos próximo${_compromisosProximos == 1 ? '' : 's'} a vencer'
                                          : 'Gestionar compromisos',
                                  color: _compromisosVencidos > 0 ? AppColors.danger : AppColors.primary,
                                  badgeCount: _compromisosVencidos,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const CompromisosErpScreen()),
                                    );
                                    _cargarConteoCompromisos();
                                  },
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.handshake,
                                  title: 'Acuerdos',
                                  subtitle: 'Contratos y acuerdos',
                                  color: Colors.purple,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AcuerdosPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.groups,
                                  title: 'Plantel',
                                  subtitle: 'Situación del plantel',
                                  color: AppColors.primary,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const PlantelPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.account_balance_wallet,
                                  title: 'Cuentas',
                                  subtitle: 'Fondos y balances',
                                  color: AppColors.primary,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CuentasPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.bar_chart,
                                  title: 'Reportes',
                                  subtitle: 'Análisis e informes',
                                  color: AppColors.info,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ReportesIndexPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.dashboard,
                                  title: 'Dashboard',
                                  subtitle: 'Resumen visual',
                                  color: Colors.indigo,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const DashboardPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.category,
                                  title: 'Categorías',
                                  subtitle: 'Gestionar categorías',
                                  color: AppColors.warning,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CategoriasMovimientoPage()),
                                  ),
                                ),
                                _buildActionCard(
                                  context,
                                  icon: Icons.account_balance_wallet,
                                  title: 'Saldos Iniciales',
                                  subtitle: 'Configurar saldos',
                                  color: AppColors.primary,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const SaldosInicialesListPage()),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _cambiarUnidadGestion() async {
    await Future.delayed(const Duration(milliseconds: 150));
    
    if (!mounted) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UnidadGestionSelectorPage(isInitialFlow: false),
      ),
    );
    
    if (result == true && mounted) {
          try {
            final settings = context.read<AppSettings>();
            await settings.ensureLoaded();
            if (settings.unidadGestionActivaId != null) {
              final db = await AppDatabase.instance();
              final rows = await db.rawQuery(
                'SELECT nombre FROM unidades_gestion WHERE id = ?',
                [settings.unidadGestionActivaId],
              );
              if (!mounted) return;
              setState(() {
                _unidadGestionNombre = rows.isNotEmpty
                    ? rows.first['nombre'] as String?
                    : null;
              });
              await _checkUnidadGestionAndLoad();
            }
          } catch (e, st) {
            await AppDatabase.logLocalError(
              scope: 'tesoreria_home.cambiar_unidad',
              error: e,
              stackTrace: st,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error al cambiar la Unidad de Gestión')),
              );
            }
          }
        }
  }

  Future<void> _loadVersion() async {
    // Versión cargada desde AppBuildInfo (no se usa en UI, callback para drawer)
  }

  /// Verifica la unidad de gestión y recarga los datos necesarios.
  Future<void> _checkUnidadGestionAndLoad() async {
    setState(() {
      _loading = true;
    });
    try {
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();
      
      final unidadId = settings.unidadGestionActivaId;
      
      if (unidadId == null) {
        setState(() {
          _needsUnidadGestionSetup = true;
          _loading = false;
        });
        return;
      }
      
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery(
        'SELECT nombre FROM unidades_gestion WHERE id = ?',
        [unidadId],
      );
      
      if (rows.isEmpty) {
        await settings.setUnidadGestionActivaId(null);
        setState(() {
          _needsUnidadGestionSetup = true;
          _loading = false;
        });
        return;
      }
      
      setState(() {
        _unidadGestionNombre = rows.first['nombre'] as String;
        _loading = false;
      });

      _cargarConteoCompromisos();
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'tesoreria_home.cargar_unidad',
        error: e.toString(),
        stackTrace: stack,
        payload: {},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar la unidad de gestión.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _loading = false;
      });
    }
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 40,
                    color: color,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Carga el conteo de compromisos vencidos y próximos a vencer.
  Future<void> _cargarConteoCompromisos() async {
    try {
      final settings = context.read<AppSettings>();
      final unidadId = settings.unidadGestionActivaId;
      if (unidadId == null) return;

      final svc = CompromisosService.instance;
      final vencidos = await svc.contarVencidos(unidadGestionId: unidadId);
      final proximos = await svc.contarProximosAVencer(unidadGestionId: unidadId);

      if (mounted) {
        setState(() {
          _compromisosVencidos = vencidos;
          _compromisosProximos = proximos;
        });
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'tesoreria_home.contar_compromisos',
        error: e.toString(),
        stackTrace: stack,
      );
    }
  }
}
