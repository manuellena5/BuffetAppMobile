import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/dao/db.dart';
import '../lib/features/tesoreria/services/cuenta_service.dart';
import '../lib/features/tesoreria/services/transferencia_service.dart';

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
  }

  group('Saldos - Cuenta sin movimientos', () {
    test('Saldo actual = saldo inicial cuando no hay movimientos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta vacía',
        tipo: 'CAJA',
        saldoInicial: 15000.0,
        tieneComision: false,
      );

      final saldoActual = await svc.obtenerSaldo(cuentaId);

      expect(saldoActual, 15000.0);
    });
  });

  group('Saldos - Cuenta con ingresos', () {
    test('Saldo aumenta con ingresos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta con ingresos',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      // Crear 3 ingresos manualmente
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'CUOTA_SOCIO',
        'monto': 5000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'CUOTA_SOCIO',
        'monto': 3000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 1000,
        'updated_ts': now + 1000,
      });

      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'OTROS_ING',
        'monto': 2000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 2000,
        'updated_ts': now + 2000,
      });

      final saldoActual = await svc.obtenerSaldo(cuentaId);

      // 10000 + 5000 + 3000 + 2000 = 20000
      expect(saldoActual, 20000.0);
    });
  });

  group('Saldos - Cuenta con egresos', () {
    test('Saldo disminuye con egresos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta con egresos',
        tipo: 'BANCO',
        saldoInicial: 50000.0,
        tieneComision: false,
      );

      // Crear 2 egresos
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'GASTOS_VARIOS',
        'monto': 8000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'PAGO_PROVEEDORES',
        'monto': 12000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 1000,
        'updated_ts': now + 1000,
      });

      final saldoActual = await svc.obtenerSaldo(cuentaId);

      // 50000 - 8000 - 12000 = 30000
      expect(saldoActual, 30000.0);
    });
  });

  group('Saldos - Cuenta con ingresos y egresos', () {
    test('Saldo correcto con movimientos mixtos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta mixta',
        tipo: 'BANCO',
        saldoInicial: 25000.0,
        tieneComision: false,
      );

      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Ingreso 10000
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'CUOTA_SOCIO',
        'monto': 10000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      // Egreso 5000
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'GASTOS_VARIOS',
        'monto': 5000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 1000,
        'updated_ts': now + 1000,
      });

      // Ingreso 8000
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'OTROS_ING',
        'monto': 8000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 2000,
        'updated_ts': now + 2000,
      });

      // Egreso 3000
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'GASTOS_VARIOS',
        'monto': 3000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 3000,
        'updated_ts': now + 3000,
      });

      final saldoActual = await svc.obtenerSaldo(cuentaId);

      // 25000 + 10000 - 5000 + 8000 - 3000 = 35000
      expect(saldoActual, 35000.0);
    });
  });

  group('Saldos - Cuenta con transferencias', () {
    test('Transferencia afecta saldo de ambas cuentas', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      // Cuenta origen con saldo inicial de 20000
      final cuentaOrigenId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Banco Principal',
        tipo: 'BANCO',
        saldoInicial: 20000.0,
        tieneComision: false,
      );

      // Cuenta destino con saldo inicial de 5000
      final cuentaDestinoId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Caja Chica',
        tipo: 'CAJA',
        saldoInicial: 5000.0,
        tieneComision: false,
      );

      // Transferir 8000 del banco a la caja
      await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 8000.0,
        medioPagoId: 1,
        observacion: 'Reposición caja chica',
      );

      final saldoOrigen = await cuentaSvc.obtenerSaldo(cuentaOrigenId);
      final saldoDestino = await cuentaSvc.obtenerSaldo(cuentaDestinoId);

      // Origen: 20000 - 8000 = 12000
      expect(saldoOrigen, 12000.0);

      // Destino: 5000 + 8000 = 13000
      expect(saldoDestino, 13000.0);
    });

    test('Múltiples transferencias secuenciales', () async {
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
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      // Transferencia 1: cuenta1 → cuenta2 (5000)
      await transfSvc.crear(
        cuentaOrigenId: cuenta1,
        cuentaDestinoId: cuenta2,
        monto: 5000.0,
        medioPagoId: 1,
      );

      // Transferencia 2: cuenta1 → cuenta2 (3000)
      await transfSvc.crear(
        cuentaOrigenId: cuenta1,
        cuentaDestinoId: cuenta2,
        monto: 3000.0,
        medioPagoId: 1,
      );

      // Transferencia 3: cuenta2 → cuenta1 (2000)
      await transfSvc.crear(
        cuentaOrigenId: cuenta2,
        cuentaDestinoId: cuenta1,
        monto: 2000.0,
        medioPagoId: 1,
      );

      final saldo1 = await cuentaSvc.obtenerSaldo(cuenta1);
      final saldo2 = await cuentaSvc.obtenerSaldo(cuenta2);

      // Cuenta1: 50000 - 5000 - 3000 + 2000 = 44000
      expect(saldo1, 44000.0);

      // Cuenta2: 10000 + 5000 + 3000 - 2000 = 16000
      expect(saldo2, 16000.0);
    });
  });

  group('Saldos - Sistema completo (total invariante)', () {
    test('Transferencia NO afecta saldo total del sistema', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();

      final cuenta1 = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 1',
        tipo: 'BANCO',
        saldoInicial: 30000.0,
        tieneComision: false,
      );

      final cuenta2 = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 2',
        tipo: 'CAJA',
        saldoInicial: 20000.0,
        tieneComision: false,
      );

      // Saldo total ANTES de transferencia
      final saldo1Antes = await cuentaSvc.obtenerSaldo(cuenta1);
      final saldo2Antes = await cuentaSvc.obtenerSaldo(cuenta2);
      final totalAntes = saldo1Antes + saldo2Antes;

      expect(totalAntes, 50000.0);

      // Transferir
      await transfSvc.crear(
        cuentaOrigenId: cuenta1,
        cuentaDestinoId: cuenta2,
        monto: 10000.0,
        medioPagoId: 1,
      );

      // Saldo total DESPUÉS de transferencia
      final saldo1Despues = await cuentaSvc.obtenerSaldo(cuenta1);
      final saldo2Despues = await cuentaSvc.obtenerSaldo(cuenta2);
      final totalDespues = saldo1Despues + saldo2Despues;

      // El total del sistema NO debe cambiar
      expect(totalDespues, 50000.0);
      expect(totalDespues, totalAntes);
    });

    test('Ingresos externos aumentan total del sistema', () async {
      final cuentaSvc = CuentaService();

      final cuentaId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Principal',
        tipo: 'BANCO',
        saldoInicial: 20000.0,
        tieneComision: false,
      );

      final saldoAntes = await cuentaSvc.obtenerSaldo(cuentaId);

      // Agregar ingreso externo (NO transferencia)
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'CUOTA_SOCIO',
        'monto': 15000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      final saldoDespues = await cuentaSvc.obtenerSaldo(cuentaId);

      // El total del sistema AUMENTA
      expect(saldoDespues, saldoAntes + 15000.0);
      expect(saldoDespues, 35000.0);
    });

    test('Egresos externos disminuyen total del sistema', () async {
      final cuentaSvc = CuentaService();

      final cuentaId = await cuentaSvc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta Principal',
        tipo: 'BANCO',
        saldoInicial: 40000.0,
        tieneComision: false,
      );

      final saldoAntes = await cuentaSvc.obtenerSaldo(cuentaId);

      // Agregar egreso externo (NO transferencia)
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'PAGO_PROVEEDORES',
        'monto': 12000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      final saldoDespues = await cuentaSvc.obtenerSaldo(cuentaId);

      // El total del sistema DISMINUYE
      expect(saldoDespues, saldoAntes - 12000.0);
      expect(saldoDespues, 28000.0);
    });
  });
}
