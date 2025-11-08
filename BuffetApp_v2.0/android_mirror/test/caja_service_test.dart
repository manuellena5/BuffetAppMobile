import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:buffet_mirror/services/caja_service.dart';
import 'package:buffet_mirror/data/dao/db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// Configura entorno de pruebas: DB FFI, rutas de path_provider y canales nativos necesarios
Future<void> _setupTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // sqflite FFI en lugar del canal nativo
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Mock de path_provider: devolver directorio temporal para cualquier consulta
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final temp = await Directory.systemTemp.createTemp('buffet_test').then((d) => d.path);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    pathChannel,
    (MethodCall call) async => temp,
  );
  // Mock de canal usb_printer para evitar fallos si algún servicio lo consulta
  const usbCh = MethodChannel('usb_printer');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    usbCh,
    (call) async {
      switch (call.method) {
        case 'isConnected':
          return false;
        case 'listDevices':
          return <dynamic>[];
        case 'requestPermission':
        case 'connect':
        case 'printBytes':
          return true;
        case 'disconnect':
          return null;
        default:
          return null;
      }
    },
  );
}

void main() {
  group('CajaService', () {
    late CajaService svc;

    setUpAll(() async {
      await _setupTestEnv();
      svc = CajaService();
    });

    test('getCajaAbierta inicialmente null', () async {
      final abierta = await svc.getCajaAbierta();
      expect(abierta, isNull);
    });

    test('abrirCaja crea registro y luego se obtiene como ABIERTA', () async {
      final id = await svc.abrirCaja(
        usuario: 'tester',
        fondoInicial: 1000,
        disciplina: 'Evento Demo',
        descripcionEvento: 'Test',
        puntoVentaCodigo: 'PV1',
        observacion: null,
      );
      expect(id, greaterThan(0));
      final abierta = await svc.getCajaAbierta();
      expect(abierta, isNotNull);
      expect(abierta!['estado'], 'ABIERTA');
    });

    test('abrirCaja con mismo día/disciplinas agrega sufijo incremental', () async {
      final id1 = await svc.abrirCaja(
        usuario: 'tester',
        fondoInicial: 500,
        disciplina: 'Evento Demo',
        descripcionEvento: 'Otro',
        puntoVentaCodigo: 'PV1',
        observacion: null,
      );
      final id2 = await svc.abrirCaja(
        usuario: 'tester',
        fondoInicial: 700,
        disciplina: 'Evento Demo',
        descripcionEvento: 'Otro',
        puntoVentaCodigo: 'PV1',
        observacion: null,
      );
      expect(id2, greaterThan(id1));
      // Verificar que existe al menos un código con sufijo -2
      final db = await AppDatabase.instance();
      final rows = await db.query('caja_diaria', columns: ['codigo_caja'], orderBy: 'id ASC');
      final codes = rows.map((e) => (e['codigo_caja'] as String?) ?? '').toList();
      expect(codes.any((c) => RegExp(r"-\d+").hasMatch(c)), isTrue);
    });
  });
}
