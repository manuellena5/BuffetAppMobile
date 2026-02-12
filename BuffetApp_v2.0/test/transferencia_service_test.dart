import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/dao/db.dart';
import '../lib/features/tesoreria/services/transferencia_service.dart';
import '../lib/features/tesoreria/services/cuenta_service.dart';

// Configura entorno de pruebas
Future<void> _setupTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  setUp(() async {
    await AppDatabase.close();
  });

  tearDown() async {
    await AppDatabase.close();
  };

  group('TransferenciaService - Crear transferencia', () {
    test('Crear transferencia válida entre dos cuentas', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      // Crear cuenta origen con saldo inicial
      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Banco Origen',
        tipo: 'BANCO',
        saldoInicial: 50000.0,
        tieneComision: false,
      );

      // Crear cuenta destino
      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Caja Destino',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      // Crear transferencia
      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 10000.0,
        medioPagoId: 1,
        observacion: 'Transferencia de prueba',
      );

      expect(transferenciaId, isNotEmpty);

      // Verificar que se crearon 2 movimientos
      final db = await AppDatabase.instance();
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
      );

      expect(movimientos.length, 2);

      // Verificar EGRESO
      final egreso = movimientos.firstWhere((m) => m['tipo'] == 'EGRESO');
      expect(egreso['cuenta_id'], cuentaOrigenId);
      expect(egreso['monto'], 10000.0);
      expect(egreso['categoria'], 'TRANSFERENCIA');
      expect(egreso['es_transferencia'], 1);

      // Verificar INGRESO
      final ingreso = movimientos.firstWhere((m) => m['tipo'] == 'INGRESO');
      expect(ingreso['cuenta_id'], cuentaDestinoId);
      expect(ingreso['monto'], 10000.0);
      expect(ingreso['categoria'], 'TRANSFERENCIA');
      expect(ingreso['es_transferencia'], 1);

      // Verificar que ambos tienen el mismo transferencia_id
      expect(egreso['transferencia_id'], ingreso['transferencia_id']);
    });

    test('Validación: No permitir misma cuenta origen y destino', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta única',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      expect(
        () => transfSvc.crear(
          cuentaOrigenId: cuentaId,
          cuentaDestinoId: cuentaId,
          monto: 5000.0,
          medioPagoId: 1,
        ),
        throwsA(predicate((e) =>
            e.toString().contains('No se puede transferir a la misma cuenta'))),
      );
    });

    test('Validación: No permitir transferencia entre unidades diferentes', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaU1 = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Unidad 1',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      final cuentaU2 = await cuentaSvc.crear(
        unidadGestionId: 2,
        nombre: 'Cuenta Unidad 2',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      expect(
        () => transfSvc.crear(
          cuentaOrigenId: cuentaU1,
          cuentaDestinoId: cuentaU2,
          monto: 5000.0,
          medioPagoId: 1,
        ),
        throwsA(predicate((e) => e
            .toString()
            .contains('No se pueden transferir fondos entre unidades diferentes'))),
      );
    });

    test('Validación: Monto debe ser mayor a cero', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Origen',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Destino',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      expect(
        () => transfSvc.crear(
          cuentaOrigenId: cuentaOrigenId,
          cuentaDestinoId: cuentaDestinoId,
          monto: 0.0,
          medioPagoId: 1,
        ),
        throwsA(predicate((e) => e.toString().contains('mayor a 0'))),
      );

      expect(
        () => transfSvc.crear(
          cuentaOrigenId: cuentaOrigenId,
          cuentaDestinoId: cuentaDestinoId,
          monto: -500.0,
          medioPagoId: 1,
        ),
        throwsA(predicate((e) => e.toString().contains('mayor a 0'))),
      );
    });
  });

  group('TransferenciaService - Verificar integridad', () {
    test('Transferencia íntegra: montos iguales', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Origen',
        tipo: 'BANCO',
        saldoInicial: 50000.0,
        tieneComision: false,
      );

      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Destino',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 8000.0,
        medioPagoId: 1,
      );

      final integra = await transfSvc.verificarIntegridad(transferenciaId);
      expect(integra, true);
    });

    test('Transferencia NO íntegra si faltan movimientos', () async {
      final transfSvc = TransferenciaService();
      final cuentaSvc = CuentaService();

      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Origen',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      // Crear solo un movimiento manualmente (simulando error)
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaOrigenId,
        'tipo': 'EGRESO',
        'categoria': 'TRANSFERENCIA',
        'monto': 5000.0,
        'medio_pago_id': 1,
        'es_transferencia': 1,
        'transferencia_id': 'test-id-incompleto',
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      final integra = await transfSvc.verificarIntegridad('test-id-incompleto');
      expect(integra, false);
    });
  });

  group('TransferenciaService - Listar transferencias', () {
    test('Listar transferencias por cuenta (origen y destino)', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuenta1 = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 1',
        tipo: 'BANCO',
        saldoInicial: 50000.0,
        tieneComision: false,
      );

      final cuenta2 = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 2',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final cuenta3 = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 3',
        tipo: 'BILLETERA',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      // Transferencia 1: cuenta1 → cuenta2
      await transfSvc.crear(
        cuentaOrigenId: cuenta1,
        cuentaDestinoId: cuenta2,
        monto: 5000.0,
        medioPagoId: 1,
      );

      // Transferencia 2: cuenta2 → cuenta3
      await transfSvc.crear(
        cuentaOrigenId: cuenta2,
        cuentaDestinoId: cuenta3,
        monto: 2000.0,
        medioPagoId: 1,
      );

      // Cuenta2 debe tener 2 transferencias (1 como destino, 1 como origen)
      final transfCuenta2 = await transfSvc.listarPorCuenta(cuenta2);
      expect(transfCuenta2.length, 2);

      // Cuenta1 debe tener 1 transferencia (como origen)
      final transfCuenta1 = await transfSvc.listarPorCuenta(cuenta1);
      expect(transfCuenta1.length, 1);

      // Cuenta3 debe tener 1 transferencia (como destino)
      final transfCuenta3 = await transfSvc.listarPorCuenta(cuenta3);
      expect(transfCuenta3.length, 1);
    });
  });

  group('TransferenciaService - Anular transferencia', () {
    test('Anular transferencia NO sincronizada', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Origen',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Destino',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 3000.0,
        medioPagoId: 1,
      );

      // Anular
      await transfSvc.anular(transferenciaId);

      // Verificar que ambos movimientos están marcados como eliminados
      final db = await AppDatabase.instance();
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
      );

      expect(movimientos.every((m) => m['eliminado'] == 1), true);
    });

    test('NO anular transferencia SINCRONIZADA', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Origen',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Destino',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 3000.0,
        medioPagoId: 1,
      );

      // Simular sincronización exitosa
      final db = await AppDatabase.instance();
      await db.update(
        'evento_movimiento',
        {'sync_estado': 'SINCRONIZADA'},
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
      );

      // Intentar anular
      expect(
        () => transfSvc.anular(transferenciaId),
        throwsA(predicate((e) =>
            e.toString().contains('No se puede anular una transferencia ya sincronizada'))),
      );
    });
  });

  group('TransferenciaService - Obtener movimientos', () {
    test('Obtener ambos movimientos de una transferencia', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Origen',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Destino',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 7500.0,
        medioPagoId: 1,
        observacion: 'Transferencia con observación',
      );

      final movimientos = await transfSvc.obtenerMovimientos(transferenciaId);

      expect(movimientos.length, 2);

      // Verificar ordenamiento (INGRESO primero por ordenBy 'tipo DESC')
      expect(movimientos[0]['tipo'], 'INGRESO');
      expect(movimientos[1]['tipo'], 'EGRESO');

      // Verificar campos comunes
      expect(movimientos.every((m) => m['monto'] == 7500.0), true);
      expect(movimientos.every((m) => m['observacion'] == 'Transferencia con observación'), true);
      expect(movimientos.every((m) => m['transferencia_id'] == transferenciaId), true);
    });
  });
}
