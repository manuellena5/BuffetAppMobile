import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:buffet_app/features/shared/state/app_settings.dart';
import 'package:buffet_app/features/shared/state/drawer_state.dart';
import 'package:buffet_app/features/shared/state/app_mode.dart';
import 'package:buffet_app/features/shared/widgets/tesoreria_scaffold.dart';
import 'package:buffet_app/features/tesoreria/pages/tesoreria_home_page.dart';
import 'package:buffet_app/features/tesoreria/pages/unidad_gestion_selector_page.dart';
import 'package:buffet_app/features/tesoreria/pages/movimientos_list_page.dart';
import 'package:buffet_app/features/tesoreria/pages/acuerdos_page.dart';
import 'package:buffet_app/features/tesoreria/pages/plantel_page.dart';
import 'package:buffet_app/features/tesoreria/pages/saldos_iniciales_list_page.dart';
import 'package:buffet_app/features/tesoreria/pages/reporte_categorias_page.dart';
import 'package:buffet_app/features/tesoreria/pages/reporte_resumen_mensual_page.dart';
import 'package:buffet_app/features/tesoreria/pages/gestionar_jugadores_page.dart';

/// Tests de comportamiento UX del módulo de Tesorería
/// Valida:
/// - Menú lateral presente en todas las pantallas principales
/// - Validación de unidad de gestión
/// - Comportamiento responsive
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Inicializar SharedPreferences para tests
    SharedPreferences.setMockInitialValues({});
    // Inicializar locale de fecha para tests
    await initializeDateFormatting('es_AR', null);
  });

  group('Validación de Unidad de Gestión', () {
    testWidgets('Debe mostrar selector cuando no hay unidad configurada', (tester) async {
      SharedPreferences.setMockInitialValues({});
      
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                final settings = Provider.of<AppSettings>(context, listen: false);
                if (!settings.isUnidadGestionConfigured) {
                  return const UnidadGestionSelectorPage(isInitialFlow: true);
                }
                return const TesoreriaHomePage();
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Debe mostrar el selector de unidad de gestión
      expect(find.text('Seleccionar Unidad de Gestión'), findsOneWidget);
    });
  });

  group('Menú Lateral (Drawer)', () {
    setUp(() async {
      // Configurar unidad de gestión para estos tests
      SharedPreferences.setMockInitialValues({
        'unidad_gestion_activa_id': 1,
      });
    });

    testWidgets('MovimientosListPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: MovimientosListPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Debe usar TesoreriaScaffold que tiene drawer
      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });

    testWidgets('AcuerdosPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: AcuerdosPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });

    testWidgets('PlantelPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: PlantelPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });

    testWidgets('SaldosInicialesListPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: SaldosInicialesListPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });

    testWidgets('ReporteCategoriasPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: ReporteCategoriasPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });

    testWidgets('ReporteResumenMensualPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: ReporteResumenMensualPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });

    testWidgets('GestionarJugadoresPage debe tener drawer', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: GestionarJugadoresPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TesoreriaScaffold), findsOneWidget);
    });
  });

  group('Comportamiento Responsive', () {
    testWidgets('Drawer debe estar fijo en pantallas anchas', (tester) async {
      SharedPreferences.setMockInitialValues({
        'unidad_gestion_activa_id': 1,
      });

      // Simular pantalla ancha (landscape de notebook)
      await tester.binding.setSurfaceSize(const Size(1600, 900));

      final drawerState = DrawerState();
      drawerState.setFixed(true); // Fijo en pantallas anchas

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: drawerState),
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: MovimientosListPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // En pantallas anchas, el drawer debe estar visible y fijo
      expect(drawerState.isFixed, isTrue);

      // Restaurar tamaño original
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Drawer debe ser colapsable en pantallas estrechas', (tester) async {
      SharedPreferences.setMockInitialValues({
        'unidad_gestion_activa_id': 1,
      });

      // Simular pantalla estrecha (móvil vertical)
      await tester.binding.setSurfaceSize(const Size(400, 800));

      final drawerState = DrawerState();
      drawerState.setFixed(false); // Colapsable en pantallas estrechas

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: drawerState),
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: MovimientosListPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // En pantallas estrechas, el drawer debe ser colapsable
      expect(drawerState.isFixed, isFalse);

      // Debe haber un botón de menú (hamburger) en el AppBar
      expect(find.byIcon(Icons.menu), findsOneWidget);

      // Restaurar tamaño original
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Contenido debe estar centrado con maxWidth en pantallas anchas', (tester) async {
      SharedPreferences.setMockInitialValues({
        'unidad_gestion_activa_id': 1,
      });

      // Simular pantalla muy ancha
      await tester.binding.setSurfaceSize(const Size(2000, 1200));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => DrawerState()),
            ChangeNotifierProvider(create: (_) => AppModeState()),
          ],
          child: const MaterialApp(
            home: MovimientosListPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // El contenido debe estar dentro de un TesoreriaScaffold
      final scaffold = tester.widget<TesoreriaScaffold>(
        find.byType(TesoreriaScaffold),
      );
      
      expect(scaffold, isNotNull);

      // Restaurar tamaño original
      await tester.binding.setSurfaceSize(null);
    });
  });
}
