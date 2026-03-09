import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../features/shared/state/drawer_state.dart';
import '../features/shared/state/app_settings.dart';
import 'erp_sidebar.dart';

// Imports para navegación
import '../features/tesoreria/pages/tesoreria_home_page.dart';
import '../features/tesoreria/pages/crear_movimiento_page.dart';
import '../features/tesoreria/pages/movimientos_list_page.dart';
import '../features/tesoreria/pages/compromisos_page.dart';
import '../features/tesoreria/pages/acuerdos_page.dart';
import '../features/tesoreria/pages/adhesiones_page.dart';
import '../features/eventos_cdm/pages/eventos_cdm_page.dart';
import '../features/tesoreria/pages/plantel_page.dart';
import '../features/tesoreria/pages/categorias_movimiento_page.dart';
import '../features/tesoreria/pages/reportes_index_page.dart';
import '../features/tesoreria/pages/dashboard_page.dart';
import '../features/tesoreria/pages/saldos_iniciales_list_page.dart';
import '../features/cuentas/pages/cuentas_page.dart';
import '../features/shared/pages/settings_page.dart';
import '../features/shared/pages/help_page.dart';
import '../features/shared/pages/error_logs_page.dart';
import '../features/home/main_menu_page.dart';

/// Layout principal del sistema ERP.
///
/// En Windows/desktop (ancho >= 900): sidebar fijo + contenido.
/// En Android/mobile (ancho < 900): Scaffold con drawer.
///
/// Uso:
/// ```dart
/// ErpLayout(
///   currentRoute: '/compromisos',
///   title: 'Compromisos',
///   body: MiContenido(),
/// )
/// ```
class ErpLayout extends StatelessWidget {
  final String? currentRoute;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showAdvanced;

  const ErpLayout({
    super.key,
    this.currentRoute,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showAdvanced = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= AppSpacing.breakpointTablet;

    // En desktop Windows: sidebar fijo
    if (isDesktop && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return _DesktopLayout(
        currentRoute: currentRoute,
        title: title,
        body: body,
        actions: actions,
        floatingActionButton: floatingActionButton,
        showAdvanced: showAdvanced,
      );
    }

    // En mobile/tablet: drawer
    return _MobileLayout(
      currentRoute: currentRoute,
      title: title,
      body: body,
      actions: actions,
      floatingActionButton: floatingActionButton,
      showAdvanced: showAdvanced,
    );
  }
}

// ─── Desktop con sidebar fijo ───

class _DesktopLayout extends StatelessWidget {
  final String? currentRoute;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showAdvanced;

  const _DesktopLayout({
    this.currentRoute,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showAdvanced = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawerState>(
      builder: (context, drawerState, _) {
        return Scaffold(
          body: Row(
            children: [
              // Sidebar — siempre dark
              Theme(
                data: AppTheme.dark,
                child: ErpSidebar(
                  sections: _buildSections(context),
                  currentRoute: currentRoute,
                  isExpanded: drawerState.isExpanded,
                  onToggleExpanded: drawerState.toggleExpanded,
                ),
              ),
              // Separador visual
              Container(
                width: 1,
                color: context.appColors.border,
              ),
              // Contenido
              Expanded(
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(title),
                    automaticallyImplyLeading: false,
                    actions: actions,
                  ),
                  floatingActionButton: floatingActionButton,
                  body: body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<ErpMenuSection> _buildSections(BuildContext context) {
    return _buildErpMenuSections(
      context: context,
      currentRoute: currentRoute,
      showAdvanced: showAdvanced,
    );
  }
}

// ─── Mobile con Drawer ───

class _MobileLayout extends StatelessWidget {
  final String? currentRoute;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showAdvanced;

  const _MobileLayout({
    this.currentRoute,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showAdvanced = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      drawer: Theme(
        data: AppTheme.dark,
        child: SizedBox(
          width: AppSpacing.sidebarWidth,
          child: Drawer(
            backgroundColor: AppColors.bgSurface,
            child: SafeArea(
              child: ErpSidebar(
                sections: _buildErpMenuSections(
                  context: context,
                  currentRoute: currentRoute,
                  showAdvanced: showAdvanced,
                  closeDrawer: true,
                ),
                currentRoute: currentRoute,
                isExpanded: true,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}

// ─── Helper: construye las secciones del menú ERP ───

List<ErpMenuSection> _buildErpMenuSections({
  required BuildContext context,
  String? currentRoute,
  bool showAdvanced = false,
  bool closeDrawer = false,
}) {
  // Leer showAdvanced desde AppSettings (fuente de verdad única)
  final advancedEffective =
      showAdvanced || context.read<AppSettings>().showAdvanced;
  void navigate(Widget page) {
    final nav = Navigator.of(context);
    if (closeDrawer) Navigator.pop(context); // cierra drawer
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  void navigatePush(Widget page) {
    final nav = Navigator.of(context);
    if (closeDrawer) Navigator.pop(context);
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  return [
    ErpMenuSection(
      items: [
        ErpMenuItem(
          icon: Icons.home_outlined,
          label: 'Menú Principal',
          routeName: '/main_menu',
          onTap: () => navigate(const MainMenuPage()),
        ),
      ],
    ),
    ErpMenuSection(
      title: 'General',
      items: [
        ErpMenuItem(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          routeName: '/dashboard',
          onTap: () => navigatePush(const DashboardPage()),
        ),
        ErpMenuItem(
          icon: Icons.home_outlined,
          label: 'Inicio Tesorería',
          routeName: '/tesoreria',
          onTap: () => navigate(const TesoreriaHomePage()),
        ),
      ],
    ),
    ErpMenuSection(
      title: 'Operaciones',
      items: [
        ErpMenuItem(
          icon: Icons.add_circle_outline,
          label: 'Crear Movimiento',
          routeName: '/crear_movimiento',
          onTap: () => navigatePush(const CrearMovimientoPage()),
        ),
        ErpMenuItem(
          icon: Icons.receipt_long_outlined,
          label: 'Movimientos',
          routeName: '/movimientos',
          onTap: () => navigatePush(const MovimientosListPage()),
        ),
        ErpMenuItem(
          icon: Icons.event_note_outlined,
          label: 'Compromisos',
          routeName: '/compromisos',
          onTap: () => navigatePush(const CompromisosPage()),
        ),
        ErpMenuItem(
          icon: Icons.handshake_outlined,
          label: 'Acuerdos',
          routeName: '/acuerdos',
          onTap: () => navigatePush(const AcuerdosPage()),
        ),
        ErpMenuItem(
          icon: Icons.volunteer_activism_outlined,
          label: 'Adhesiones',
          routeName: '/adhesiones',
          onTap: () => navigatePush(const AdhesionesPage()),
        ),
        ErpMenuItem(
          icon: Icons.sports_soccer_outlined,
          label: 'Eventos',
          routeName: '/eventos_cdm',
          onTap: () => navigatePush(const EventosCdmPage()),
        ),
      ],
    ),
    ErpMenuSection(
      title: 'Gestión',
      items: [
        ErpMenuItem(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Cuentas de Fondos',
          routeName: '/cuentas',
          onTap: () => navigatePush(const CuentasPage()),
        ),
        ErpMenuItem(
          icon: Icons.groups_outlined,
          label: 'Plantel',
          routeName: '/plantel',
          onTap: () => navigatePush(const PlantelPage()),
        ),
        ErpMenuItem(
          icon: Icons.category_outlined,
          label: 'Categorías',
          routeName: '/categorias',
          onTap: () => navigatePush(const CategoriasMovimientoPage()),
        ),
        ErpMenuItem(
          icon: Icons.account_balance_outlined,
          label: 'Saldos Iniciales',
          routeName: '/saldos_iniciales',
          onTap: () => navigatePush(const SaldosInicialesListPage()),
        ),
      ],
    ),
    ErpMenuSection(
      title: 'Reportes',
      items: [
        ErpMenuItem(
          icon: Icons.bar_chart_outlined,
          label: 'Reportes',
          routeName: '/reportes',
          onTap: () => navigatePush(const ReportesIndexPage()),
        ),
      ],
    ),
    ErpMenuSection(
      title: 'Sistema',
      items: [
        if (advancedEffective)
          ErpMenuItem(
            icon: Icons.bug_report_outlined,
            label: 'Logs de Errores',
            routeName: '/logs',
            onTap: () => navigatePush(const ErrorLogsPage()),
          ),
        ErpMenuItem(
          icon: Icons.settings_outlined,
          label: 'Configuración',
          routeName: '/settings',
          onTap: () => navigatePush(const SettingsPage()),
        ),
        ErpMenuItem(
          icon: Icons.help_outline,
          label: 'Ayuda',
          routeName: '/help',
          onTap: () => navigatePush(const HelpPage()),
        ),
      ],
    ),
  ];
}
