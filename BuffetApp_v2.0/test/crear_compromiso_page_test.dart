import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffet_app/features/tesoreria/pages/crear_compromiso_page.dart';
import 'package:buffet_app/features/shared/state/app_settings.dart';
import 'package:buffet_app/data/dao/db.dart';

// Configura entorno de pruebas
Future<void> _setupTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final temp = await Directory.systemTemp.createTemp('buffet_test').then((d) => d.path);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    pathChannel,
    (MethodCall call) async => temp,
  );
}

void main() {
  setUpAll(() async {
    await _setupTestEnv();
  });

  testWidgets('CrearCompromisoPage - Carga inicial sin errores',
      (WidgetTester tester) async {
    // Inicializar base de datos
    final db = await AppDatabase.instance();
    
    // Verificar que existan las tablas necesarias
    final tablas = await db.query('sqlite_master', 
      where: 'type = ? AND name IN (?, ?, ?, ?)',
      whereArgs: ['table', 'frecuencias', 'unidades_gestion', 'categoria_movimiento', 'compromisos'],
    );
    
    expect(tablas.length, greaterThanOrEqualTo(3), 
      reason: 'Deben existir las tablas frecuencias, unidades_gestion y categoria_movimiento');

    // Crear unidad de gestión de prueba
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    // Crear AppSettings
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearCompromisoPage(),
        ),
      ),
    );

    // Esperar a que se carguen los datos
    await tester.pumpAndSettle();

    // Verificar que la página se carga sin errores
    expect(find.text('Nuevo Compromiso'), findsOneWidget);
    expect(find.text('Nombre del compromiso *'), findsOneWidget);
    expect(find.text('Tipo *'), findsOneWidget);
    expect(find.text('🔑 Modalidad del compromiso *'), findsOneWidget);
  });

  testWidgets('CrearCompromisoPage - Campos visibles según modalidad PAGO_UNICO',
      (WidgetTester tester) async {
    await AppDatabase.instance();
    
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearCompromisoPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Por defecto debería estar PAGO_UNICO seleccionado
    expect(find.text('Pago único'), findsOneWidget);
    expect(find.text('Fecha de pago/cobro *'), findsOneWidget);
    
    // No deberían estar visibles los campos de cuotas
    expect(find.text('Cantidad de cuotas *'), findsNothing);
  });

  testWidgets('CrearCompromisoPage - Cambio a modalidad MONTO_TOTAL_CUOTAS',
      (WidgetTester tester) async {
    await AppDatabase.instance();
    
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearCompromisoPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Seleccionar MONTO_TOTAL_CUOTAS
    await tester.tap(find.text('Monto total en cuotas'));
    await tester.pumpAndSettle();

    // Verificar que aparecen los campos correspondientes
    expect(find.text('Monto total del compromiso *'), findsOneWidget);
    expect(find.text('Cantidad de cuotas *'), findsOneWidget);
    expect(find.text('Frecuencia *'), findsOneWidget);
  });

  testWidgets('CrearCompromisoPage - Validación de formulario vacío',
      (WidgetTester tester) async {
    await AppDatabase.instance();
    
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearCompromisoPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Intentar guardar sin llenar campos
    await tester.tap(find.text('Guardar Compromiso'));
    await tester.pumpAndSettle();

    // Verificar que aparecen mensajes de error
    expect(find.text('Ingresá un nombre'), findsOneWidget);
    expect(find.text('Ingresá un monto'), findsOneWidget);
  });

  testWidgets('CrearCompromisoPage - Crear compromiso PAGO_UNICO exitoso',
      (WidgetTester tester) async {
    await AppDatabase.instance();
    
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearCompromisoPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Llenar campos del formulario
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del compromiso *'),
      'Sponsor Nike',
    );
    
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monto *'),
      '50000',
    );

    await tester.pumpAndSettle();

    // Guardar
    await tester.tap(find.text('Guardar Compromiso'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verificar que se guardó en la BD
    final compromisos = await db.query('compromisos');
    expect(compromisos.length, 1);
    expect(compromisos.first['nombre'], 'Sponsor Nike');
    expect(compromisos.first['monto'], 50000.0);
    expect(compromisos.first['modalidad'], 'PAGO_UNICO');

    // Verificar que se generó la cuota
    final cuotas = await db.query('compromiso_cuotas');
    expect(cuotas.length, 1);
    expect(cuotas.first['numero_cuota'], 1);
    expect(cuotas.first['monto_esperado'], 50000.0);
  });

  testWidgets('CrearCompromisoPage - Crear compromiso MONTO_TOTAL_CUOTAS con 3 cuotas',
      (WidgetTester tester) async {
    await AppDatabase.instance();
    
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearCompromisoPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Seleccionar modalidad MONTO_TOTAL_CUOTAS
    await tester.tap(find.text('Monto total en cuotas'));
    await tester.pumpAndSettle();

    // Llenar campos
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del compromiso *'),
      'Equipamiento',
    );
    
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monto total del compromiso *'),
      '30000',
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cantidad de cuotas *'),
      '3',
    );

    await tester.pumpAndSettle();

    // Debería mostrar vista previa de cuotas
    expect(find.text('📋 Vista previa de cuotas'), findsOneWidget);

    // Guardar
    await tester.tap(find.text('Guardar Compromiso'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verificar que se guardó
    final compromisos = await db.query('compromisos');
    expect(compromisos.length, 1);
    expect(compromisos.first['cuotas'], 3);

    // Verificar que se generaron 3 cuotas
    final cuotas = await db.query('compromiso_cuotas');
    expect(cuotas.length, 3);
    
    // Verificar que la suma de montos es correcta
    final sumaMontos = cuotas.fold<double>(
      0, 
      (sum, cuota) => sum + (cuota['monto_esperado'] as double),
    );
    expect((sumaMontos - 30000.0).abs(), lessThan(0.01));
  });
}
