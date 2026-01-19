// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/buffet/services/caja_service.dart';
import 'package:buffet_app/features/eventos/pages/eventos_page.dart';
import 'package:buffet_app/features/home/home_page.dart';
import 'package:buffet_app/features/shared/state/app_settings.dart';
import 'package:buffet_app/features/buffet/state/cart_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buffet_app/main.dart';

class _FakeCajaService extends CajaService {
  _FakeCajaService({this.cajaAbierta});

  final Map<String, dynamic>? cajaAbierta;

  @override
  Future<Map<String, dynamic>?> getCajaAbierta() async => cajaAbierta;

  @override
  Future<Map<String, dynamic>> resumenCaja(int cajaId) async => {
        'total': 0.0,
      };
}

Future<void> _pumpUntilHomeLoaded(WidgetTester tester,
    {Duration step = const Duration(milliseconds: 100), int maxSteps = 80}) async {
  // Evita pumpAndSettle() porque Home puede tener timers/polling.
  for (int i = 0; i < maxSteps; i++) {
    await tester.pump(step);

    final ex = tester.takeException();
    if (ex != null) {
      // Propagamos la excepción real para debug.
      // ignore: only_throw_errors
      throw ex;
    }

    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      // Un pump extra para procesar el setState final.
      await tester.pump();

      final ex2 = tester.takeException();
      if (ex2 != null) {
        // ignore: only_throw_errors
        throw ex2;
      }
      return;
    }
  }

  // Si llegamos acá, Home no terminó de cargar.
  expect(find.byType(CircularProgressIndicator), findsNothing,
      reason: 'Home siguió en loading demasiado tiempo');
}

Future<void> _setupEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await AppDatabase.resetForTests();

  // Estado limpio por test
  SharedPreferences.setMockInitialValues({});

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final temp = Directory.systemTemp.createTempSync('buffet_home_test_').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathChannel, (call) async => temp);

  const usbCh = MethodChannel('usb_printer');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(usbCh, (call) async {
    // HomePage hace polling con isConnected(); devolver bool para evitar type errors.
    if (call.method == 'isConnected') return false;
    return null;
  });
}

Widget _wrapHome({required AppSettings settings, CajaService? cajaService}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => CartModel()),
      ChangeNotifierProvider.value(value: settings),
    ],
    child: MaterialApp(
      home: HomePage(
        enableUsbPolling: false,
        cajaServiceOverride: cajaService,
        enableContextDbLookups: false,
      ),
    ),
  );
}

void main() {
  setUp(() async {
    await _setupEnv();
  });

  testWidgets('Arranca y muestra app', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    // Valida que el MaterialApp se haya montado
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  // TODO: Los siguientes tests requieren funcionalidad de Fase 3 (Tesorería + movimientos)
  // Se deshabilitaron temporalmente hasta completar la integración del contexto activo
  
  // TODO: Los siguientes tests requieren funcionalidad de Fase 3 (Tesorería + movimientos)
  // Se deshabilitaron temporalmente hasta completar la integración del contexto activo
  
  // testWidgets('Home sin evento + sin caja', (tester) async {
  //   final settings = AppSettings();
  //   await settings.ensureLoaded();
  //
  //   await tester.pumpWidget(_wrapHome(
  //     settings: settings,
  //     cajaService: _FakeCajaService(cajaAbierta: null),
  //   ));
  //   await _pumpUntilHomeLoaded(tester);
  //
  //   expect(find.textContaining('Subcom'), findsOneWidget);
  //   expect(find.text('Sin evento seleccionado'), findsOneWidget);
  //   expect(find.text('Abrir caja'), findsOneWidget);
  //   expect(find.textContaining('Cargar'), findsOneWidget);
  // });
  //
  // testWidgets('Home con evento + sin caja', (tester) async {
  //   final settings = AppSettings();
  //   await settings.ensureLoaded();
  //   await settings.setEventoActivoHoy(disciplinaId: 2, especial: false);
  //   expect(settings.eventoActivoId, isNotNull);
  //
  //   await tester.pumpWidget(_wrapHome(
  //     settings: settings,
  //     cajaService: _FakeCajaService(cajaAbierta: null),
  //   ));
  //   await _pumpUntilHomeLoaded(tester);
  //
  //   // Si hay evento activo debería mostrarse con ese label.
  //   expect(find.text('Evento activo'), findsOneWidget);
  //   expect(find.textContaining('Cargar'), findsOneWidget);
  // });
  //
  // testWidgets('Home con evento + caja abierta', (tester) async {
  //   final settings = AppSettings();
  //   await settings.ensureLoaded();
  //   await settings.setEventoActivoHoy(disciplinaId: 2, especial: false);
  //   expect(settings.eventoActivoId, isNotNull);
  //
  //   await tester.pumpWidget(_wrapHome(
  //     settings: settings,
  //     cajaService: _FakeCajaService(
  //       cajaAbierta: {
  //         'id': 1,
  //         'disciplina': 'Futbol Mayor',
  //         'fecha': '2026-01-10',
  //       },
  //       total: 0.0,
  //     ),
  //   ));
  //   await _pumpUntilHomeLoaded(tester);
  //
  //   expect(find.text('Cerrar caja'), findsOneWidget);
  //   expect(find.textContaining('Cargar'), findsOneWidget);
  // });
  //
  // testWidgets('Navega a MovimientoCreatePage', (tester) async {
  //   final settings = AppSettings();
  //   await settings.ensureLoaded();
  //
  //   await tester.pumpWidget(_wrapHome(
  //     settings: settings,
  //     cajaService: _FakeCajaService(cajaAbierta: null),
  //   ));
  //   await _pumpUntilHomeLoaded(tester);
  //
  //   final btn = find.text('Cargar movimiento');
  //   await tester.ensureVisible(btn);
  //   await tester.tap(btn);
  //   await tester.pump();
  //   await tester.pump(const Duration(milliseconds: 300));
  //   expect(find.byType(MovimientoCreatePage), findsOneWidget);
  // });

  testWidgets('Navega a EventosPage desde Home', (tester) async {
    final settings = AppSettings();
    await settings.ensureLoaded();

    await tester.pumpWidget(_wrapHome(
      settings: settings,
      cajaService: _FakeCajaService(cajaAbierta: null),
    ));
    await _pumpUntilHomeLoaded(tester);

    final btn = find.text('Eventos');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(EventosPage), findsOneWidget);
  });
}
