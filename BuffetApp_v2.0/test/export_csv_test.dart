import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buffet_app/services/seed_service.dart';
import 'package:buffet_app/services/caja_service.dart';
import 'package:buffet_app/services/venta_service.dart';
import 'package:buffet_app/services/export_service.dart';
import 'package:buffet_app/data/dao/db.dart';

void main() {
  Future<String> _setupTestEnvAndTempDir() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // sqflite FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Mock path_provider a carpeta temporal
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final temp = await Directory.systemTemp.createTemp('buffet_export_test').then((d) => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (MethodCall call) async => temp,
    );
    // Mock impresora USB para evitar canales nativos en pruebas
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
    return temp;
  }

  group('Export CSV', () {
    test('Guarda CSV en carpeta indicada con nombre por código de caja', () async {
      await _setupTestEnvAndTempDir();
      await SeedService().ensureSeedData();

      // Abrir caja y registrar una venta simple
      final cajaId = await CajaService().abrirCaja(
        usuario: 'tester',
        fondoInicial: 100,
        disciplina: 'Evento',
        descripcionEvento: 'Test export CSV',
        puntoVentaCodigo: 'Caj01',
      );
      // Tomar un producto visible
      final db = await AppDatabase.instance();
      final prods = await db.query('products', where: 'visible = 1', limit: 1, orderBy: 'id ASC');
      expect(prods, isNotEmpty, reason: 'Se esperaban productos seed');
      final p = prods.first;
      await VentaService().crearVenta(
        metodoPagoId: 1,
        items: [
          {
            'producto_id': p['id'],
            'cantidad': 1,
            'precio_unitario': (p['precio_venta'] as num).toDouble(),
          }
        ],
        marcarImpreso: true,
      );
      await CajaService().cerrarCaja(
        cajaId: cajaId,
        efectivoEnCaja: 100 + ((p['precio_venta'] as num).toDouble()),
        transferencias: 0,
        usuarioCierre: 'tester',
        observacion: 'Cerrar para export',
      );

      // Exportar
      final caja = await CajaService().getCajaById(cajaId);
      final codigo = caja!['codigo_caja'] as String;
      final outDir = await Directory.systemTemp.createTemp('buffet_out');
      final file = await ExportService().exportCajaToCsv(cajaId, directoryPath: outDir.path);

      expect(await file.exists(), true, reason: 'El archivo CSV debería existir');
      expect(file.path.endsWith('caja_${codigo}.csv'), true, reason: 'Debe respetar el nombre por código de caja');
      final content = await file.readAsString();
      expect(content.isNotEmpty, true);
      expect(content.split('\n').first.contains('Codigo de caja'), true, reason: 'Cabecera CSV esperada');
    });
  });
}
