import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buffet_app/features/shared/services/seed_service.dart';
import 'package:buffet_app/features/buffet/services/caja_service.dart';
import 'package:buffet_app/features/buffet/services/venta_service.dart';
import 'package:buffet_app/data/dao/db.dart';

void main() {
  Future<void> _setupTestEnv() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // Usar sqflite FFI en pruebas
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Mock de path_provider: usar carpeta temporal
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final temp = await Directory.systemTemp.createTemp('buffet_test').then((d) => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (MethodCall call) async => temp,
    );
    // Mock de canal usb_printer
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

  group('Flujo completo: abrir → vender → cerrar', () {
    test('Abre caja, realiza ventas y cierra con diferencia = 0', () async {
      await _setupTestEnv();
      // 1) Seed de datos mínimos (métodos de pago + catálogo)
      await SeedService().ensureSeedData();

      // 2) Abrir caja
      const fondoInicial = 100.0;
      final cajaId = await CajaService().abrirCaja(
        usuario: 'tester',
        fondoInicial: fondoInicial,
        disciplina: 'Evento',
        descripcionEvento: 'Test QA',
        puntoVentaCodigo: 'Caj01',
      );
      expect(cajaId, greaterThan(0));

      // 3) Elegir 2 productos del catálogo y armar items
      final db = await AppDatabase.instance();
      final prods = await db.query('products',
          columns: ['id', 'precio_venta', 'nombre'],
          where: 'visible = 1',
          limit: 2,
          orderBy: 'id ASC');
      expect(prods.length, greaterThanOrEqualTo(1), reason: 'Se esperaban productos seed');

      final items = <Map<String, dynamic>>[];
      double totalEsperado = 0;
      for (var i = 0; i < prods.length; i++) {
        final p = prods[i];
        final qty = i == 0 ? 2 : 1; // 2 unidades del primero, 1 del segundo
        final unit = (p['precio_venta'] as num).toDouble();
        items.add({
          'producto_id': p['id'],
          'cantidad': qty,
          'precio_unitario': unit,
        });
        totalEsperado += unit * qty;
      }

      // 4) Crear venta en efectivo
      final venta = await VentaService().crearVenta(
        metodoPagoId: 1, // 1 = Efectivo
        items: items,
        marcarImpreso: true,
      );
      expect(venta['ventaId'], isNotNull);
      final totalTickets = items.fold<int>(0, (acc, it) => acc + (it['cantidad'] as int));
      expect((venta['ticketIds'] as List).length, totalTickets);

      // 5) Cerrar caja con conteo de efectivo que cuadra diferencia = 0
      final efectivoEnCaja = fondoInicial + totalEsperado;
      await CajaService().cerrarCaja(
        cajaId: cajaId,
        efectivoEnCaja: efectivoEnCaja,
        transferencias: 0,
        usuarioCierre: 'tester',
        observacion: 'Cierre QA',
      );

      // 6) Validaciones post-cierre
      final caja = await CajaService().getCajaById(cajaId);
      expect(caja, isNotNull);
      expect(caja!['estado'], 'CERRADA');
      final diff = (caja['diferencia'] as num?)?.toDouble() ?? 0.0;
      expect(diff.abs() < 0.0001, true, reason: 'La diferencia debería ser 0');

      // Resumen coincide con totalEsperado
      final resumen = await CajaService().resumenCaja(cajaId);
      final totalRes = (resumen['total'] as num?)?.toDouble() ?? 0.0;
      expect((totalRes - totalEsperado).abs() < 0.0001, true);
    });
  });
}
