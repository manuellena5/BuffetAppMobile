import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/data/dao/db.dart';
import '../lib/features/tesoreria/services/cuenta_service.dart';

// Configura entorno de pruebas: DB FFI, rutas de path_provider y canales nativos necesarios
Future<void> _setupTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
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
}

void main() {
  setUpAll(() async {
    await _setupTestEnv();
  });

  setUp(() async {
    // Reiniciar DB antes de cada test
    await AppDatabase.close();
  });

  tearDown() async {
    await AppDatabase.close();
  };

  group('CuentaService - Crear cuenta', () {
    test('Crear cuenta válida tipo BANCO', () async {
      final svc = CuentaService();
      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Banco Nación - Cuenta Corriente',
        tipo: 'BANCO',
        saldoInicial: 50000.0,
        tieneComision: true,
        comisionPorcentaje: 1.5,
        bancoNombre: 'Banco Nación',
        cbuAlias: '0110599520000001234567',
      );

      expect(cuentaId, greaterThan(0));

      // Verificar que se guardó correctamente
      final db = await AppDatabase.instance();
      final result = await db.query(
        'cuentas_fondos',
        where: 'id = ?',
        whereArgs: [cuentaId],
      );

      expect(result.length, 1);
      expect(result.first['nombre'], 'Banco Nación - Cuenta Corriente');
      expect(result.first['tipo'], 'BANCO');
      expect(result.first['saldo_inicial'], 50000.0);
      expect(result.first['tiene_comision'], 1);
      expect(result.first['comision_porcentaje'], 1.5);
      expect(result.first['activo'], 1);
      expect(result.first['eliminado'], 0);
    });

    test('Crear cuenta BILLETERA sin comisión', () async {
      final svc = CuentaService();
      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Mercado Pago',
        tipo: 'BILLETERA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      expect(cuentaId, greaterThan(0));

      final db = await AppDatabase.instance();
      final result = await db.query(
        'cuentas_fondos',
        where: 'id = ?',
        whereArgs: [cuentaId],
      );

      expect(result.first['tipo'], 'BILLETERA');
      expect(result.first['tiene_comision'], 0);
      expect(result.first['comision_porcentaje'], isNull);
    });

    test('Crear cuenta CAJA', () async {
      final svc = CuentaService();
      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Caja Chica Fútbol',
        tipo: 'CAJA',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      expect(cuentaId, greaterThan(0));
    });

    test('Crear cuenta INVERSION', () async {
      final svc = CuentaService();
      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Plazo Fijo 30 días',
        tipo: 'INVERSION',
        saldoInicial: 100000.0,
        tieneComision: false,
      );

      expect(cuentaId, greaterThan(0));

      final db = await AppDatabase.instance();
      final result = await db.query(
        'cuentas_fondos',
        where: 'id = ?',
        whereArgs: [cuentaId],
      );

      expect(result.first['tipo'], 'INVERSION');
    });

    test('Validar nombre obligatorio', () async {
      final svc = CuentaService();

      expect(
        () => svc.crear(
          unidadGestionId: 1,
          nombre: '',
          tipo: 'BANCO',
          saldoInicial: 0.0,
          tieneComision: false,
        ),
        throwsException,
      );
    });

    test('Validar tipo válido', () async {
      final svc = CuentaService();

      expect(
        () => svc.crear(
          unidadGestionId: 1,
          nombre: 'Cuenta inválida',
          tipo: 'TIPO_INVALIDO',
          saldoInicial: 0.0,
          tieneComision: false,
        ),
        throwsException,
      );
    });

    test('Validar comisión porcentaje cuando tiene_comision es true', () async {
      final svc = CuentaService();

      expect(
        () => svc.crear(
          unidadGestionId: 1,
          nombre: 'Banco con comisión',
          tipo: 'BANCO',
          saldoInicial: 0.0,
          tieneComision: true,
          // No se pasa comisionPorcentaje
        ),
        throwsException,
      );
    });
  });

  group('CuentaService - Listar cuentas', () {
    test('Listar cuentas por unidad de gestión', () async {
      final svc = CuentaService();

      // Crear 3 cuentas en unidad 1
      await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 1',
        tipo: 'BANCO',
        saldoInicial: 0.0,
        tieneComision: false,
      );
      await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta 2',
        tipo: 'BILLETERA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      // Crear 1 cuenta en unidad 2 (otra disciplina)
      await svc.crear(
        unidadGestionId: 2,
        nombre: 'Cuenta Unidad 2',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final cuentasU1 = await svc.listarPorUnidad(1);
      expect(cuentasU1.length, 2);

      final cuentasU2 = await svc.listarPorUnidad(2);
      expect(cuentasU2.length, 1);
    });

    test('Solo listar cuentas no eliminadas', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta a eliminar',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      // Eliminar lógicamente
      await svc.eliminar(cuentaId);

      final cuentas = await svc.listarPorUnidad(1);
      expect(cuentas.any((c) => c.id == cuentaId), false);
    });
  });

  group('CuentaService - Obtener saldo', () {
    test('Saldo sin movimientos = saldo inicial', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta sin movimientos',
        tipo: 'BANCO',
        saldoInicial: 10000.0,
        tieneComision: false,
      );

      final saldo = await svc.obtenerSaldo(cuentaId);
      expect(saldo, 10000.0);
    });

    test('Saldo con ingresos y egresos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta con movimientos',
        tipo: 'BANCO',
        saldoInicial: 5000.0,
        tieneComision: false,
      );

      // Crear movimientos manualmente
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Ingreso de 3000
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'OTROS_ING',
        'monto': 3000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      // Egreso de 1500
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'GASTOS_VARIOS',
        'monto': 1500.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 1000,
        'updated_ts': now + 1000,
      });

      final saldo = await svc.obtenerSaldo(cuentaId);
      // 5000 + 3000 - 1500 = 6500
      expect(saldo, 6500.0);
    });

    test('Movimientos eliminados no afectan saldo', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta test eliminados',
        tipo: 'CAJA',
        saldoInicial: 1000.0,
        tieneComision: false,
      );

      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Ingreso eliminado
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'OTROS_ING',
        'monto': 5000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 1, // Eliminado
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      final saldo = await svc.obtenerSaldo(cuentaId);
      expect(saldo, 1000.0); // Solo saldo inicial
    });
  });

  group('CuentaService - Calcular comisión', () {
    test('Comisión sobre monto', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Banco con 2% comisión',
        tipo: 'BANCO',
        saldoInicial: 0.0,
        tieneComision: true,
        comisionPorcentaje: 2.0,
      );

      final comision = await svc.calcularComision(cuentaId, 10000.0);
      expect(comision, 200.0); // 2% de 10000
    });

    test('Comisión cero si cuenta no tiene comisión', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta sin comisión',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      final comision = await svc.calcularComision(cuentaId, 10000.0);
      expect(comision, 0.0);
    });
  });

  group('CuentaService - Actualizar y Desactivar', () {
    test('Actualizar nombre de cuenta', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Nombre original',
        tipo: 'BANCO',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      await svc.actualizar(
        id: cuentaId,
        nombre: 'Nombre actualizado',
        tipo: 'BANCO',
        saldoInicial: 0.0,
      );

      final db = await AppDatabase.instance();
      final result = await db.query(
        'cuentas_fondos',
        where: 'id = ?',
        whereArgs: [cuentaId],
      );

      expect(result.first['nombre'], 'Nombre actualizado');
    });

    test('Desactivar cuenta', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta a desactivar',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      await svc.desactivar(cuentaId);

      final db = await AppDatabase.instance();
      final result = await db.query(
        'cuentas_fondos',
        where: 'id = ?',
        whereArgs: [cuentaId],
      );

      expect(result.first['activo'], 0);
    });
  });

  group('CuentaService - Eliminar', () {
    test('Eliminar cuenta sin movimientos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta sin uso',
        tipo: 'CAJA',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      await svc.eliminar(cuentaId);

      final db = await AppDatabase.instance();
      final result = await db.query(
        'cuentas_fondos',
        where: 'id = ? AND eliminado = 0',
        whereArgs: [cuentaId],
      );

      expect(result.isEmpty, true);
    });

    test('NO eliminar cuenta con movimientos', () async {
      final svc = CuentaService();

      final cuentaId = await svc.crear(
        unidadGestionId: 1,
        nombre: 'Cuenta con movimientos',
        tipo: 'BANCO',
        saldoInicial: 0.0,
        tieneComision: false,
      );

      // Crear un movimiento
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'OTROS_ING',
        'monto': 1000.0,
        'medio_pago_id': 1,
        'es_transferencia': 0,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      // Intentar eliminar
      expect(
        () => svc.eliminar(cuentaId),
        throwsException,
      );
    });
  });
}
