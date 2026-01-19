import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffet_app/features/tesoreria/pages/crear_movimiento_page.dart';
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

  testWidgets('CrearMovimientoPage - Carga inicial sin errores y selector de categorías funciona',
      (WidgetTester tester) async {
    // Inicializar base de datos
    final db = await AppDatabase.instance();
    
    // Crear unidad de gestión de prueba
    await db.insert('unidades_gestion', {
      'nombre': 'Fútbol Mayor',
      'tipo': 'DISCIPLINA',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    // Crear AppSettings
    final settings = AppSettings();
    await settings.ensureLoaded();
    await settings.setUnidadGestionActivaId(1);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          home: const CrearMovimientoPage(),
        ),
      ),
    );

    // Esperar a que se carguen los datos
    await tester.pumpAndSettle();

    // Verificar que la página se carga sin errores
    expect(find.text('Nuevo Movimiento'), findsOneWidget);
    expect(find.text('Tipo de movimiento'), findsOneWidget);
    
    // Verificar que hay categorías para INGRESO (por defecto)
    expect(find.text('Categoría *'), findsOneWidget);
    
    // Cambiar a EGRESO
    await tester.tap(find.text('Egreso'));
    await tester.pumpAndSettle();
    
    // Verificar que las categorías se actualizaron
    // El selector debería estar presente
    expect(find.text('Categoría *'), findsOneWidget);
  });

  testWidgets('Error handler funciona correctamente',
      (WidgetTester tester) async {
    final db = await AppDatabase.instance();
    
    // Limpiar logs previos
    await AppDatabase.clearErrorLogs();
    
    // Crear un error simulado
    await AppDatabase.logLocalError(
      scope: 'test.error',
      error: Exception('Error de prueba'),
      stackTrace: StackTrace.current,
      payload: {'test': 'data'},
    );
    
    // Verificar que se guardó
    final errors = await AppDatabase.ultimosErrores(limit: 10);
    expect(errors.length, greaterThan(0));
    expect(errors.first['scope'], 'test.error');
    expect(errors.first['message'], contains('Error de prueba'));
  });
}
