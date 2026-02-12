import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/drawer_state.dart';
import '../pages/settings_page.dart';
import '../pages/help_page.dart';
import '../pages/error_logs_page.dart';
import '../../buffet/pages/buffet_home_page.dart';
import '../../buffet/pages/caja_open_page.dart';
import '../../buffet/pages/caja_page.dart';
import '../../buffet/pages/sales_list_page.dart';
import '../../buffet/pages/products_page.dart';
import '../../buffet/services/caja_service.dart';
import '../../eventos/pages/eventos_page.dart';
import '../../home/main_menu_page.dart';
import '../../home/home_page.dart';
import '../../tesoreria/pages/movimientos_page.dart';
import '../../tesoreria/pages/unidad_gestion_selector_page.dart';
import '../pages/printer_test_page.dart';
import 'custom_drawer.dart';

/// Helper para crear el drawer del módulo Buffet reutilizable en todas las pantallas
class BuffetDrawerHelper {
  /// Construye el drawer de Buffet con navegación consistente
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
    final drawerState = context.watch<DrawerState>();
    final isDrawerFixed = drawerState.isFixed;

    return CustomDrawer(
      title: 'BuffetApp',
      items: [
        // Home Buffet
        DrawerMenuItem(
          icon: Icons.home,
          label: 'Inicio Buffet',
          onTap: () {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            nav.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomePage()),
              (route) => false,
            );
          },
          isActive: currentRouteName == '/home',
          activeColor: Colors.blue,
        ),

        // Unidad de Gestión activa
        DrawerMenuItem(
          icon: Icons.business,
          label: unidadGestionNombre ?? 'Seleccionar Unidad',
          onTap: () {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              nav.push(
                MaterialPageRoute(
                  builder: (_) =>
                      const UnidadGestionSelectorPage(isInitialFlow: false),
                ),
              );
            });
          },
          activeColor: Colors.orange,
        ),

        // Ventas (requiere caja abierta)
        DrawerMenuItem(
          icon: Icons.point_of_sale,
          label: 'Ventas',
          onTap: () async {
            final nav = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            final caja = await CajaService().getCajaAbierta();
            if (caja == null) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Abrí una caja para vender')),
              );
              return;
            }
            nav.push(
              MaterialPageRoute(builder: (_) => const BuffetHomePage()),
            );
          },
          isActive: currentRouteName == '/ventas',
          activeColor: Colors.blue,
        ),

        // Tickets (requiere caja abierta)
        DrawerMenuItem(
          icon: Icons.history,
          label: 'Tickets',
          onTap: () async {
            final nav = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            final caja = await CajaService().getCajaAbierta();
            if (caja == null) {
              messenger.showSnackBar(
                const SnackBar(
                    content: Text('Abrí una caja para ver los tickets')),
              );
              return;
            }
            nav.push(
              MaterialPageRoute(builder: (_) => const SalesListPage()),
            );
          },
          isActive: currentRouteName == '/tickets',
          activeColor: Colors.blue,
        ),

        // Caja
        DrawerMenuItem(
          icon: Icons.store,
          label: 'Caja',
          onTap: () async {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            final caja = await CajaService().getCajaAbierta();
            if (caja == null) {
              nav.push(
                MaterialPageRoute(builder: (_) => const CajaOpenPage()),
              );
            } else {
              nav.push(
                MaterialPageRoute(builder: (_) => const CajaPage()),
              );
            }
          },
          isActive: currentRouteName == '/caja',
          activeColor: Colors.blue,
        ),

        // Eventos
        DrawerMenuItem(
          icon: Icons.event,
          label: 'Eventos',
          onTap: () {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const EventosPage()),
            );
          },
          isActive: currentRouteName == '/eventos',
          activeColor: Colors.blue,
        ),

        // Movimientos caja (requiere caja abierta)
        DrawerMenuItem(
          icon: Icons.swap_vert,
          label: 'Movimientos caja',
          onTap: () async {
            final nav = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            final caja = await CajaService().getCajaAbierta();
            if (caja == null) {
              messenger.showSnackBar(
                const SnackBar(
                    content: Text('Abrí una caja para ver movimientos')),
              );
              return;
            }
            nav.push(
              MaterialPageRoute(
                  builder: (_) => MovimientosPage(cajaId: caja['id'] as int)),
            );
          },
          isActive: currentRouteName == '/movimientos_caja',
          activeColor: Colors.blue,
        ),

        // Productos
        DrawerMenuItem(
          icon: Icons.inventory_2,
          label: 'Productos',
          onTap: () {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            nav.push(
              MaterialPageRoute(builder: (_) => const ProductsPage()),
            );
          },
          isActive: currentRouteName == '/productos',
          activeColor: Colors.blue,
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

        // Configuración impresora
        DrawerMenuItem(
          icon: Icons.print,
          label: 'Config. impresora',
          onTap: () async {
            final nav = Navigator.of(context);
            if (!isDrawerFixed) Navigator.pop(context);
            await nav.push(
              MaterialPageRoute(builder: (_) => const PrinterTestPage()),
            );
          },
          activeColor: Colors.grey,
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
          isActive: currentRouteName == '/settings',
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
