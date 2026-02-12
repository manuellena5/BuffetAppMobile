import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/shared/state/app_settings.dart';
import 'package:buffet_app/features/shared/state/drawer_state.dart';
import 'package:buffet_app/features/tesoreria/pages/crear_movimiento_page.dart';

// Mock para PathProvider
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return 'test_data';
  }

  @override
  Future<String?> getTemporaryPath() async {
    return 'test_temp';
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Inicializar sqflite ffi para que AppDatabase use una implementación
    // en memoria/ffi durante tests (evita bloqueos en plataformas nativas).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Mock de PathProvider
    PathProviderPlatform.instance = MockPathProviderPlatform();
    
    // Mock de MethodChannel para otros plugins
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, Object>{};
        }
        return null;
      },
    );
    
    // Inicializar DB
    final db = await AppDatabase.instance();
    expect(db, isNotNull);
  });

  group('CrearMovimientoPage - Smoke Tests', () {
    testWidgets('Pantalla debe cargar sin errores (sin unidad de gestión)',
        (tester) async {
      final settings = AppSettings();
      await settings.ensureLoaded();
      // Asegurar que no haya unidad seleccionada para este caso
      await settings.setUnidadGestionActivaId(null);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider(create: (_) => DrawerState()),
            ],
            child: const CrearMovimientoPage(),
          ),
        ),
      );

      // Primer frame - debe mostrar loading
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Esperar brevemente a que el widget actualice su estado
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // Debe mostrar mensaje de seleccionar unidad de gestión
      expect(find.text('Seleccioná una Unidad de Gestión'), findsOneWidget);
      expect(
        find.textContaining('Para cargar movimientos'),
        findsOneWidget,
      );
    });

    testWidgets('Pantalla debe cargar con unidad de gestión configurada',
        (tester) async {
      final settings = AppSettings();
      await settings.ensureLoaded();

      // Configurar unidad de gestión activa
      final db = await AppDatabase.instance();
      final unidades = await db.query('unidades_gestion', limit: 1);
      if (unidades.isNotEmpty) {
        await settings.setUnidadGestionActivaId(unidades.first['id'] as int);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider(create: (_) => DrawerState()),
            ],
            child: const CrearMovimientoPage(),
          ),
        ),
      );

      // Primer frame - debe mostrar loading
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Esperar brevemente a que el widget actualice su estado
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // Debe mostrar el formulario
      expect(find.text('Tipo de Movimiento'), findsOneWidget);
      expect(find.text('💰 Ingreso'), findsOneWidget);
      expect(find.text('Categoría *'), findsOneWidget);
      expect(find.text('Monto'), findsOneWidget);
      expect(find.text('Medio de Pago'), findsOneWidget);
    });

    testWidgets('Debe filtrar categorías al cambiar tipo de movimiento',
        (tester) async {
      final settings = AppSettings();
      await settings.ensureLoaded();

      // Configurar unidad de gestión activa
      final db = await AppDatabase.instance();
      final unidades = await db.query('unidades_gestion', limit: 1);
      if (unidades.isNotEmpty) {
        await settings.setUnidadGestionActivaId(unidades.first['id'] as int);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider(create: (_) => DrawerState()),
            ],
            child: const CrearMovimientoPage(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // Verificar que está en modo INGRESO
      expect(find.text('💰 Ingreso'), findsOneWidget);

      // Cambiar a EGRESO
      await tester.tap(find.text('Tipo de Movimiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('💸 Egreso').last);
      await tester.pumpAndSettle();

      // Debe haber cambiado
      expect(find.text('💸 Egreso'), findsOneWidget);
    });

    testWidgets('Debe mostrar error si intenta guardar sin categoría',
        (tester) async {
      final settings = AppSettings();
      await settings.ensureLoaded();

      final db = await AppDatabase.instance();
      final unidades = await db.query('unidades_gestion', limit: 1);
      if (unidades.isNotEmpty) {
        await settings.setUnidadGestionActivaId(unidades.first['id'] as int);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider(create: (_) => DrawerState()),
            ],
            child: const CrearMovimientoPage(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      // Ingresar solo monto
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pumpAndSettle();

      // Intentar guardar
      await tester.tap(find.text('Guardar Movimiento'));
      await tester.pumpAndSettle();

      // Debe mostrar error
      expect(find.text('Seleccioná una categoría'), findsOneWidget);
    });
  });
}
