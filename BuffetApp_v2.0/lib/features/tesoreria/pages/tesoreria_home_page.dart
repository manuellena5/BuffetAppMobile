import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/pages/settings_page.dart';
import '../../shared/pages/help_page.dart';
import '../../shared/pages/error_logs_page.dart';
import '../../buffet/pages/buffet_home_page.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/state/app_mode.dart';
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
  DateTime? _lastBackPress;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _checkUnidadGestionAndLoad();
  }

  Future<void> _checkUnidadGestionAndLoad() async {
    try {
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();
      
      if (!settings.isUnidadGestionConfigured) {
        if (mounted) {
          setState(() {
            _needsUnidadGestionSetup = true;
            _loading = false;
          });
        }
        return;
      }
      
      // Cargar nombre de la unidad de gestión activa
      final db = await AppDatabase.instance();
      final rows = await db.rawQuery(
        'SELECT nombre FROM unidades_gestion WHERE id = ?',
        [settings.unidadGestionActivaId],
      );
      
      if (mounted) {
        setState(() {
          _unidadGestionNombre = rows.isNotEmpty 
              ? rows.first['nombre'] as String? 
              : null;
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'tesoreria_home.check_unidad_gestion',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    await _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = AppBuildInfo.version;
    final sp = await SharedPreferences.getInstance();
    final advanced = sp.getBool('show_advanced_options') ?? false;
    if (mounted) {
      setState(() {
        _appVersion = v;
        _showAdvanced = advanced;
      });
    }
  }
  
  Future<void> _cambiarUnidadGestion() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UnidadGestionSelectorPage(isInitialFlow: false),
      ),
    );
    
    if (result == true && mounted) {
      setState(() => _loading = true);
      await _checkUnidadGestionAndLoad();
    }
  }
  
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presioná nuevamente para salir'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // Si necesita configurar Unidad de Gestión, mostrar selector
    if (_needsUnidadGestionSetup) {
      return UnidadGestionSelectorPage(
        isInitialFlow: true,
        onComplete: () {
          setState(() {
            _needsUnidadGestionSetup = false;
            _loading = true;
          });
          _checkUnidadGestionAndLoad();
        },
      );
    }
    
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
        title: const Text('Tesorería'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          // Indicador de Unidad de Gestión activa
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: InkWell(
                onTap: () => _cambiarUnidadGestion(),
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
      drawer: _buildDrawer(context),
      body: ResponsiveContainer(
        maxWidth: 1200,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance,
                size: 100,
                color: Colors.green.withOpacity(0.5),
              ),
              const SizedBox(height: 24),
              Text(
                'Tesorería',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Gestión de movimientos financieros\n${_unidadGestionNombre ?? 'Sin unidad seleccionada'}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // Placeholder para funcionalidades futuras
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add_circle_outline, color: Colors.green),
                        title: const Text('Crear Movimiento'),
                        subtitle: const Text('Registrar ingreso o egreso'),
                        enabled: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CrearMovimientoPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.list, color: Colors.green),
                        title: const Text('Ver Movimientos'),
                        subtitle: const Text('Historial de ingresos y egresos'),
                        enabled: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MovimientosListPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.event_note, color: Colors.green),
                        title: const Text('Compromisos'),
                        subtitle: const Text('Gestionar compromisos financieros'),
                        enabled: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CompromisosPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.handshake, color: Colors.purple),
                        title: const Text('Acuerdos'),
                        subtitle: const Text('Gestionar contratos y acuerdos'),
                        enabled: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AcuerdosPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.groups, color: Colors.green),
                        title: const Text('Plantel'),
                        subtitle: const Text('Ver situación económica del plantel'),
                        enabled: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlantelPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.sync, color: Colors.green),
                        title: const Text('Sincronizar'),
                        subtitle: const Text('Próximamente'),
                        enabled: false,
                        onTap: () {
                          // TODO: Navegar a pendientes_sync_page
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    ));
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Colors.green,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.account_balance, size: 48, color: Colors.white),
                const SizedBox(height: 8),
                const Text(
                  'Tesorería',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_appVersion != null)
                  Text(
                    'v$_appVersion',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          
          // Unidad de Gestión activa
          ListTile(
            leading: const Icon(Icons.business, color: Colors.green),
            title: const Text('Unidad de Gestión'),
            subtitle: Text(_unidadGestionNombre ?? 'Sin seleccionar'),
            trailing: const Icon(Icons.swap_horiz),
            onTap: () {
              Navigator.pop(context);
              _cambiarUnidadGestion();
            },
          ),
          
          const Divider(),
          
          // Cambiar a Buffet
          ListTile(
            leading: const Icon(Icons.store, color: Colors.blue),
            title: const Text('Cambiar a Buffet'),
            subtitle: const Text('Gestión de ventas del partido'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cambiar módulo'),
                  content: const Text(
                    'Vas a cambiar al módulo Buffet.\n\n'
                    '¿Deseas continuar?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              );
              
              if (confirm == true && context.mounted) {
                // Cambiar modo y navegar directo a Buffet
                final modeState = context.read<AppModeState>();
                await modeState.setMode(AppMode.buffet);
                
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const BuffetHomePage(),
                  ),
                  (route) => false,
                );
              }
            },
          ),
          
          const Divider(),
          
          // Crear Movimiento
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: const Text('Crear Movimiento'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CrearMovimientoPage()),
              );
            },
          ),
          
          // Ver Movimientos
          ListTile(
            leading: const Icon(Icons.list, color: Colors.green),
            title: const Text('Ver Movimientos'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MovimientosListPage()),
              );
            },
          ),
          
          // Compromisos
          ListTile(
            leading: const Icon(Icons.event_note, color: Colors.green),
            title: const Text('Compromisos'),
            subtitle: const Text('Obligaciones recurrentes'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CompromisosPage()),
              );
            },
          ),
          
          // Plantel
          ListTile(
            leading: const Icon(Icons.groups, color: Colors.green),
            title: const Text('Plantel'),
            subtitle: const Text('Ver situación económica del plantel'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlantelPage()),
              );
            },
          ),
          
          // Reportes
          ListTile(
            leading: const Icon(Icons.bar_chart, color: Colors.blue),
            title: const Text('📊 Reportes'),
            subtitle: const Text('Análisis y estadísticas'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportesIndexPage()),
              );
            },
          ),
          
          const Divider(),
          
          // Categorías de Movimientos
          ListTile(
            leading: const Icon(Icons.category, color: Colors.orange),
            title: const Text('Categorías'),
            subtitle: const Text('Administrar categorías de movimientos'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriasMovimientoPage()),
              );
            },
          ),
                    // Saldos Iniciales
          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Colors.teal),
            title: const Text('Saldos Iniciales'),
            subtitle: const Text('Configurar saldo de apertura de períodos'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SaldosInicialesListPage()),
              );
            },
          ),
                    const Divider(),
          
          // Logs de errores (solo visible si funciones avanzadas están activadas)
          if (_showAdvanced)
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('Logs de errores'),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    nav.pop();
                    await nav.push(
                      MaterialPageRoute(builder: (_) => const ErrorLogsPage()),
                    );
                  },
                ),
          
          // Configuración
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Configuración'),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              // Recargar configuración al volver
              if (mounted) {
                await _loadVersion();
              }
            },
          ),
          
          // Ayuda
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Ayuda'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
