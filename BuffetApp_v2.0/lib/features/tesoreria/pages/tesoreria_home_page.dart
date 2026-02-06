import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/state/drawer_state.dart';
import '../../shared/widgets/tesoreria_drawer_helper.dart';
import '../../../data/dao/db.dart';
import '../../shared/widgets/responsive_container.dart';
import 'crear_movimiento_page.dart';
import 'movimientos_list_page.dart';
import 'unidad_gestion_selector_page.dart';
import 'compromisos_page.dart';
import 'acuerdos_page.dart';
import 'plantel_page.dart';
import 'categorias_movimiento_page.dart';
import 'reportes_index_page.dart';
import 'saldos_iniciales_list_page.dart';
import '../../cuentas/pages/cuentas_page.dart';
import '../../../app_version.dart';

/// Pantalla principal del módulo de Tesorería
/// Permite gestionar movimientos financieros independientes del buffet
class TesoreriaHomePage extends StatefulWidget {
  const TesoreriaHomePage({super.key});

  @override
  State<TesoreriaHomePage> createState() => _TesoreriaHomePageState();
}

class _TesoreriaHomePageState extends State<TesoreriaHomePage> {
  String? _appVersion;
  bool _loading = true;
  bool _needsUnidadGestionSetup = false;
  String? _unidadGestionNombre;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
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
    final cs = theme.colorScheme;
    final drawerState = Provider.of<DrawerState>(context);

    // Pantalla de selección de unidad de gestión si corresponde
    if (_needsUnidadGestionSetup) {
      return UnidadGestionSelectorPage(
        isInitialFlow: true,
        onComplete: () {
          setState(() {
            _needsUnidadGestionSetup = false;
            _loading = true;
          });
          // Recargar datos después de seleccionar unidad
          _checkUnidadGestionAndLoad();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tesorería'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: InkWell(
                onTap: _cambiarUnidadGestion,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _unidadGestionNombre ?? 'Sin seleccionar',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: drawerState.isFixed ? null : _buildDrawerSimplified(context),
      body: Row(
        children: [
          if (drawerState.isFixed) _buildDrawerSimplified(context),
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
                        color: Colors.teal.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tesorería',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gestión de movimientos financieros\n${_unidadGestionNombre ?? 'Sin unidad seleccionada'}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.onSurface.withOpacity(0.7),
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
                            color: Colors.teal,
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
                            color: Colors.teal,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const MovimientosListPage()),
                            ),
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.event_note,
                            title: 'Compromisos',
                            subtitle: 'Gestionar compromisos',
                            color: Colors.teal,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CompromisosPage()),
                            ),
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
                            color: Colors.teal,
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
                            color: Colors.teal,
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
                            color: Colors.blue,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ReportesIndexPage()),
                            ),
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.category,
                            title: 'Categorías',
                            subtitle: 'Gestionar categorías',
                            color: Colors.orange,
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
                            color: Colors.teal,
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
    // El drawer ya hace pop antes de llamar a este método
    // Esperar un frame para que el drawer termine de cerrarse
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
              // Recargar cualquier info dependiente
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
    // Cargar la versión desde AppBuildInfo
    setState(() {
      _appVersion = AppBuildInfo.version;
    });
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
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
              Icon(
                icon,
                size: 40,
                color: color,
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

  Widget _buildDrawerSimplified(BuildContext context) {
    return TesoreriaDrawerHelper.build(
      context: context,
      currentRouteName: '/tesoreria',
      unidadGestionNombre: _unidadGestionNombre,
      showAdvanced: _showAdvanced, // Leer desde SharedPreferences en initState
      onLoadVersion: () async {
        if (mounted) {
          await _loadVersion();
        }
      },
    );
  }

  /// Verifica la unidad de gestión y recarga los datos necesarios.
  Future<void> _checkUnidadGestionAndLoad() async {
    setState(() {
      _loading = true;
    });
    try {
      // Cargar unidad de gestión activa desde AppSettings
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();
      
      final unidadId = settings.unidadGestionActivaId;
      
      if (unidadId == null) {
        // No hay unidad seleccionada - forzar selector
        setState(() {
          _needsUnidadGestionSetup = true;
          _loading = false;
        });
        return;
      }
      
      // Cargar nombre de la unidad desde DB
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery(
        'SELECT nombre FROM unidades_gestion WHERE id = ?',
        [unidadId],
      );
      
      if (rows.isEmpty) {
        // Unidad no existe - forzar selector
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
}
