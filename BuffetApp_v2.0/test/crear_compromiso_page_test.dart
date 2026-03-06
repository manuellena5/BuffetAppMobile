import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buffet_app/features/tesoreria/pages/crear_compromiso_page.dart';
import 'package:buffet_app/features/shared/state/app_settings.dart';
import 'package:buffet_app/data/dao/db.dart';

// Mock para PathProvider
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => 'test_data';

  @override
  Future<String?> getTemporaryPath() async => 'test_temp';
}

/// Construye el widget de test con providers necesarios.
Widget _buildTestWidget(AppSettings settings) {
  return ChangeNotifierProvider<AppSettings>.value(
    value: settings,
    child: const MaterialApp(
      home: CrearCompromisoPage(),
    ),
  );
}

/// Espera a que el widget cargue sus datos async (sin pumpAndSettle).
/// pumpAndSettle() causa timeout por el widget Autocomplete que nunca
/// deja de programar frames. Usamos pump() explícito como workaround.
Future<void> _waitForLoad(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  late Database db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Mock de PathProvider
    PathProviderPlatform.instance = MockPathProviderPlatform();

    // Mock de SharedPreferences channel
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
    db = await AppDatabase.instance();
  });

  setUp(() async {
    // Limpiar datos entre tests para aislamiento
    db = await AppDatabase.instance();
    await db.delete('compromiso_cuotas');
    await db.delete('compromisos');
    await db.delete('unidades_gestion');

    // Insertar unidad de gestion de prueba (id=1)
    await db.insert('unidades_gestion', {
      'nombre': 'Futbol Mayor',
      'tipo': 'DISCIPLINA',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });
  });

  testWidgets('CrearCompromisoPage - Carga inicial sin errores',
      (WidgetTester tester) async {
    // Verificar que existan las tablas necesarias
    final tablas = await db.query('sqlite_master',
      where: 'type = ? AND name IN (?, ?, ?, ?)',
      whereArgs: [
        'table',
        'frecuencias',
        'unidades_gestion',
        'categoria_movimiento',
        'compromisos',
      ],
    );

    expect(tablas.length, greaterThanOrEqualTo(3),
        reason:
            'Deben existir las tablas frecuencias, unidades_gestion y compromisos');

    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_buildTestWidget(settings));
    await _waitForLoad(tester);

    // Verificar que la pagina se carga sin errores
    expect(find.text('Nuevo Compromiso'), findsOneWidget);
    expect(find.text('Nombre del compromiso *'), findsOneWidget);
    expect(find.text('Tipo *'), findsOneWidget);
    // La pagina simplificada ya no muestra selector de modalidad
    expect(find.text('Monto *'), findsOneWidget);
    expect(find.text('Fecha programada *'), findsOneWidget);
  });

  testWidgets(
      'CrearCompromisoPage - Formulario es pago unico (sin selector de modalidad)',
      (WidgetTester tester) async {
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_buildTestWidget(settings));
    await _waitForLoad(tester);

    // No debe haber selector de modalidad ni campos de cuotas
    expect(find.text('Modalidad del compromiso *'), findsNothing);
    expect(find.text('Cantidad de cuotas *'), findsNothing);
    expect(find.text('Frecuencia *'), findsNothing);
    expect(find.text('Monto total del compromiso *'), findsNothing);

    // Debe mostrar campo de monto simple
    expect(find.text('Monto *'), findsOneWidget);
    expect(find.text('Fecha programada *'), findsOneWidget);
  });

  testWidgets('CrearCompromisoPage - Banner informativo visible',
      (WidgetTester tester) async {
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_buildTestWidget(settings));
    await _waitForLoad(tester);

    // Debe mostrar banner informativo
    expect(
      find.text('Un compromiso es un pago o cobro puntual esperado.'),
      findsOneWidget,
    );

    // Debe mostrar sugerencia de acuerdos
    expect(find.textContaining('Se repite o tiene cuotas?'), findsOneWidget);
  });

  testWidgets('CrearCompromisoPage - Validacion de formulario vacio',
      (WidgetTester tester) async {
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_buildTestWidget(settings));
    await _waitForLoad(tester);

    // Intentar guardar sin llenar campos
    await tester.tap(find.text('Crear Compromiso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verificar que aparecen mensajes de validacion
    expect(find.text('Ingresa un nombre'), findsOneWidget);
    expect(find.text('Ingresa un monto'), findsOneWidget);
  });

  testWidgets('CrearCompromisoPage - Crear compromiso PAGO_UNICO exitoso',
      (WidgetTester tester) async {
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_buildTestWidget(settings));
    await _waitForLoad(tester);

    // Llenar campos del formulario
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del compromiso *'),
      'Sponsor Nike',
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monto *'),
      '50000',
    );

    await tester.pump();

    // Tap en "Crear Compromiso"
    await tester.tap(find.text('Crear Compromiso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Aparece dialog de confirmacion
    expect(find.text('Confirmar Compromiso'), findsOneWidget);
    expect(find.text('Sponsor Nike'), findsWidgets);

    // Confirmar
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Verificar que se guardo en la BD
    final compromisos = await db.query('compromisos');
    expect(compromisos.length, 1);
    expect(compromisos.first['nombre'], 'Sponsor Nike');
    expect(compromisos.first['monto'], 50000.0);
    expect(compromisos.first['modalidad'], 'PAGO_UNICO');

    // Verificar que se genero la cuota
    final cuotas = await db.query('compromiso_cuotas');
    expect(cuotas.length, 1);
    expect(cuotas.first['numero_cuota'], 1);
    expect(cuotas.first['monto_esperado'], 50000.0);
  });

  testWidgets('CrearCompromisoPage - Tipo ingreso/egreso funciona',
      (WidgetTester tester) async {
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_buildTestWidget(settings));
    await _waitForLoad(tester);

    // Por defecto deberia ser INGRESO
    expect(find.text('Ingreso'), findsOneWidget);
    expect(find.text('Egreso'), findsOneWidget);

    // Cambiar a EGRESO
    await tester.tap(find.text('Egreso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Llenar formulario y crear
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del compromiso *'),
      'Compra insumos',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monto *'),
      '15000',
    );
    await tester.pump();

    await tester.tap(find.text('Crear Compromiso'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Confirmar en el dialog
    expect(find.text('Confirmar Compromiso'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // Verificar tipo EGRESO en BD
    final compromisos = await db.query('compromisos');
    expect(compromisos.length, 1);
    expect(compromisos.first['tipo'], 'EGRESO');
    expect(compromisos.first['monto'], 15000.0);
  });
}
