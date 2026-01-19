import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/buffet/services/caja_service.dart';

Future<void> _setupEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final temp = await Directory.systemTemp.createTemp('buffet_test_cierre').then((d) => d.path);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    pathChannel,
    (MethodCall call) async => temp,
  );
  const usbCh = MethodChannel('usb_printer');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    usbCh,
    (call) async => null,
  );
}

void main() {
  group('Cerrar caja y resumen', () {
    late CajaService svc;

    setUpAll(() async {
      await _setupEnv();
      svc = CajaService();
    });

    test('cerrarCaja calcula diferencia = 0 y resumen coincide', () async {
      final cajaId = await svc.abrirCaja(
        usuario: 'tester',
        fondoInicial: 1000,
        disciplina: 'Evento Demo',
        descripcionEvento: 'Cierre Test',
        puntoVentaCodigo: 'PVX',
      );
      final db = await AppDatabase.instance();
      // Obtener un producto válido
      final prod = (await db.query('products', limit: 1)).first;
      final prodId = prod['id'] as int;
      // Venta en efectivo: 3 tickets de 1000 => 3000
      final ventaEfId = await db.insert('ventas', {
        'uuid': 'v-ef-1',
        'fecha_hora': '2025-01-01 10:00:00',
        'total_venta': 3000,
        'status': 'No impreso',
        'activo': 1,
        'metodo_pago_id': 1, // Efectivo
        'caja_id': cajaId,
      });
      for (int i = 0; i < 3; i++) {
        await db.insert('tickets', {
          'venta_id': ventaEfId,
          'producto_id': prodId,
          'fecha_hora': '2025-01-01 10:0$i:00',
          'status': 'Impreso',
          'total_ticket': 1000,
          'identificador_ticket': 'EF-$i',
        });
      }
      // Venta por transferencia: 2 tickets de 1000 => 2000
      final ventaTrId = await db.insert('ventas', {
        'uuid': 'v-tr-1',
        'fecha_hora': '2025-01-01 11:00:00',
        'total_venta': 2000,
        'status': 'No impreso',
        'activo': 1,
        'metodo_pago_id': 2, // Transferencia
        'caja_id': cajaId,
      });
      for (int i = 0; i < 2; i++) {
        await db.insert('tickets', {
          'venta_id': ventaTrId,
          'producto_id': prodId,
          'fecha_hora': '2025-01-01 11:0$i:00',
          'status': 'Impreso',
          'total_ticket': 1000,
          'identificador_ticket': 'TR-$i',
        });
      }
      // Un ticket anulado (no debe sumar)
      final ventaAnId = await db.insert('ventas', {
        'uuid': 'v-an-1',
        'fecha_hora': '2025-01-01 12:00:00',
        'total_venta': 1000,
        'status': 'No impreso',
        'activo': 1,
        'metodo_pago_id': 1,
        'caja_id': cajaId,
      });
      await db.insert('tickets', {
        'venta_id': ventaAnId,
        'producto_id': prodId,
        'fecha_hora': '2025-01-01 12:00:00',
        'status': 'Anulado',
        'total_ticket': 1000,
        'identificador_ticket': 'AN-1',
      });
      // Movimientos: ingreso 200, retiro 100
      await db.insert('caja_movimiento', {'caja_id': cajaId, 'tipo': 'INGRESO', 'monto': 200});
      await db.insert('caja_movimiento', {'caja_id': cajaId, 'tipo': 'RETIRO', 'monto': 100});

      // Cerrar caja con valores que den diferencia 0
      await svc.cerrarCaja(
        cajaId: cajaId,
        efectivoEnCaja: 4100, // según fórmula
        transferencias: 2000,
        usuarioCierre: 'tester',
        observacion: 'ok',
        entradas: 3,
      );

      // Verificar estado y diferencia
      final caja = await db.query('caja_diaria', where: 'id=?', whereArgs: [cajaId], limit: 1);
      expect(caja.first['estado'], 'CERRADA');
      expect(((caja.first['diferencia'] as num?) ?? 0).toDouble().abs(), 0);

      // Resumen
      final res = await svc.resumenCaja(cajaId);
      expect(((res['total'] as num?) ?? 0).toDouble(), 5000);
      final porMp = (res['por_mp'] as List).cast<Map<String, Object?>>();
      final ef = porMp.firstWhere((m) => (m['mp'] as int?) == 1);
      final tr = porMp.firstWhere((m) => (m['mp'] as int?) == 2);
      expect(((ef['total'] as num?) ?? 0).toDouble(), 3000);
      expect(((tr['total'] as num?) ?? 0).toDouble(), 2000);
      final tk = (res['tickets'] as Map<String, Object?>);
      expect((tk['emitidos'] as int?) ?? 0, 5);
      expect((tk['anulados'] as int?) ?? 0, 1);
    });

    test('ensureCajaCierreResumenTable crea tabla y permite reemplazo', () async {
      await AppDatabase.ensureCajaCierreResumenTable();
      final db = await AppDatabase.instance();

      // Insert 1
      await db.insert(
        'caja_cierre_resumen',
        {
          'evento_fecha': '2025-01-01',
          'disciplina': 'Evento Demo',
          'codigo_caja': 'Caj01-1',
          'source_device': 'test',
          'items_count': 2,
          'payload': '{"ok":true,"n":1}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert 2 (misma clave única) -> replace
      await db.insert(
        'caja_cierre_resumen',
        {
          'evento_fecha': '2025-01-01',
          'disciplina': 'Evento Demo',
          'codigo_caja': 'Caj01-1',
          'source_device': 'test',
          'items_count': 3,
          'payload': '{"ok":true,"n":2}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rows = await db.query(
        'caja_cierre_resumen',
        where: 'evento_fecha=? AND disciplina=? AND codigo_caja=?',
        whereArgs: ['2025-01-01', 'Evento Demo', 'Caj01-1'],
      );
      expect(rows.length, 1);
      expect((rows.first['items_count'] as num?)?.toInt(), 3);
    });
  });
}
