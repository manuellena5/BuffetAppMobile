import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/drawer_state.dart';
import '../pages/settings_page.dart';
import '../pages/help_page.dart';
import '../pages/error_logs_page.dart';
import '../../home/main_menu_page.dart';
import '../../tesoreria/pages/tesoreria_home_page.dart';
import '../../tesoreria/pages/crear_movimiento_page.dart';
import '../../tesoreria/pages/movimientos_list_page.dart';
import '../../tesoreria/pages/compromisos_page.dart';
import '../../tesoreria/pages/acuerdos_page.dart';
import '../../tesoreria/pages/plantel_page.dart';
import '../../tesoreria/pages/categorias_movimiento_page.dart';
import '../../tesoreria/pages/reportes_index_page.dart';
import '../../tesoreria/pages/saldos_iniciales_list_page.dart';
import '../../tesoreria/pages/unidad_gestion_selector_page.dart';
import '../../cuentas/pages/cuentas_page.dart';
import 'custom_drawer.dart';

/// Helper para crear el drawer de Tesorería reutilizable en todas las pantallas
class TesoreriaDrawerHelper {
  /// Construye el drawer de Tesorería con navegación consistente
  /// 
  /// [context] BuildContext de la pantalla actual
  /// [currentRouteName] Nombre de la ruta actual para marcar el item activo
  /// [unidadGestionNombre] Nombre de la Unidad de Gestión activa
  /// [showAdvanced] Si se deben mostrar opciones avanzadas (logs)
  /// [onLoadVersion] Callback para recargar versión después de configuración
  static Widget build({
    required BuildContext context,
    String? currentRouteName,
    String? unidadGestionNombre,
    bool showAdvanced = false,
    VoidCallback? onLoadVersion,
  }) {
    // Obtener estado del drawer para saber si está fijo o no
    final drawerState = context.watch<DrawerState>();
    final isDrawerFixed = drawerState.isFixed;
    return CustomDrawer(
      title: 'BuffetApp',
      items: [
        // Home Tesorería
        DrawerMenuItem(
          icon: Icons.home,
          label: 'Inicio Tesorería',
          onTap: () {
            final nav = Navigator.of(context);
            // Solo cerrar drawer si NO está fijo
            if (!isDrawerFixed) Navigator.pop(context);
            nav.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const TesoreriaHomePage()),
              (route) => false,
            );
          },
          isActive: currentRouteName == '/tesoreria',
          activeColor: Colors.teal,
        ),
        
        // Unidad de Gestión activa
        DrawerMenuItem(
          icon: Icons.business,
          label: unidadGestionNombre ?? 'Seleccionar Unidad',
          onTap: () {
            final nav = Navigator.of(context);
            // Solo cerrar drawer si NO está fijo
            if (!isDrawerFixed) Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              nav.push(
                MaterialPageRoute(
                  builder: (_) => const UnidadGestionSelectorPage(isInitialFlow: false),
                ),
              );
            });
          },
          activeColor: Colors.orange,
        ),
        
        // Menú Principal
        DrawerMenuItem(
          icon: Icons.home_outlined,
          label: 'Menú Principal',
          onTap: () {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            nav.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => const MainMenuPage(),
              ),
              (route) => false,
            );
          },
          activeColor: Colors.deepPurple,
        ),
        
        // Crear Movimiento
        DrawerMenuItem(
          icon: Icons.add_circle_outline,
          label: 'Crear Movimiento',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const CrearMovimientoPage()),
            );
          },
          isActive: currentRouteName == '/crear_movimiento',
          activeColor: Colors.teal,
        ),
        
        // Ver Movimientos
        DrawerMenuItem(
          icon: Icons.list,
          label: 'Ver Movimientos',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const MovimientosListPage()),
            );
          },
          isActive: currentRouteName == '/movimientos',
          activeColor: Colors.teal,
        ),
        
        // Compromisos
        DrawerMenuItem(
          icon: Icons.event_note,
          label: 'Compromisos',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const CompromisosPage()),
            );
          },
          isActive: currentRouteName == '/compromisos',
          activeColor: Colors.teal,
        ),
        
        // Acuerdos
        DrawerMenuItem(
          icon: Icons.handshake,
          label: 'Acuerdos',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const AcuerdosPage()),
            );
          },
          isActive: currentRouteName == '/acuerdos',
          activeColor: Colors.purple,
        ),
        
        // Cuentas de Fondos
        DrawerMenuItem(
          icon: Icons.account_balance_wallet,
          label: 'Cuentas de Fondos',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const CuentasPage()),
            );
          },
          isActive: currentRouteName == '/cuentas',
          activeColor: Colors.teal,
        ),
        
        // Plantel
        DrawerMenuItem(
          icon: Icons.groups,
          label: 'Plantel',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const PlantelPage()),
            );
          },
          isActive: currentRouteName == '/plantel',
          activeColor: Colors.teal,
        ),
        
        // Reportes
        DrawerMenuItem(
          icon: Icons.bar_chart,
          label: 'Reportes',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const ReportesIndexPage()),
            );
          },
          isActive: currentRouteName == '/reportes',
          activeColor: Colors.blue,
        ),
        
        // Categorías
        DrawerMenuItem(
          icon: Icons.category,
          label: 'Categorías',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const CategoriasMovimientoPage()),
            );
          },
          isActive: currentRouteName == '/categorias',
          activeColor: Colors.orange,
        ),
        
        // Saldos Iniciales
        DrawerMenuItem(
          icon: Icons.account_balance_wallet,
          label: 'Saldos Iniciales',
          onTap: () {
            final nav = Navigator.of(context);
            Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const SaldosInicialesListPage()),
            );
          },
          isActive: currentRouteName == '/saldos_iniciales',
          activeColor: Colors.teal,
        ),
        
        // Logs de errores (solo si funciones avanzadas están activadas)
        if (showAdvanced)
          DrawerMenuItem(
            icon: Icons.bug_report,
            label: 'Logs de errores',
            onTap: () async {
              final nav = Navigator.of(context);
              if (!isDrawerFixed) Navigator.pop(context);
              await nav.push(
                MaterialPageRoute(builder: (_) => const ErrorLogsPage()),
              );
            },
            activeColor: Colors.red,
          ),
        
        // Configuración
        DrawerMenuItem(
          icon: Icons.settings,
          label: 'Configuración',
          onTap: () async {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            await nav.push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
            onLoadVersion?.call();
          },
          activeColor: Colors.grey,
        ),
        
        // Ayuda
        DrawerMenuItem(
          icon: Icons.help_outline,
          label: 'Ayuda',
          onTap: () {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const HelpPage()),
            );
          },
          activeColor: Colors.blue,
        ),
      ],
    );
  }
}
