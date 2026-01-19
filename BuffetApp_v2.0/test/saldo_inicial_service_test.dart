import 'package:flutter_test/flutter_test.dart';
import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/tesoreria/services/saldo_inicial_service.dart';
import 'package:buffet_app/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('SaldoInicialService', () {
    setUp(() async {
      await AppDatabase.resetForTests();
    });

    tearDown(() async {
      await AppDatabase.resetForTests();
    });

    test('crear - debe crear un saldo inicial anual correctamente', () async {
      final id = await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 8062355.74,
        observacion: 'Saldo disponible cierre 2025',
      );

      expect(id, greaterThan(0));

      final saldo = await SaldoInicialService.obtener(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
      );

      expect(saldo, isNotNull);
      expect(saldo!.unidadGestionId, equals(1));
      expect(saldo.periodoTipo, equals('ANIO'));
      expect(saldo.periodoValor, equals('2026'));
      expect(saldo.monto, equals(8062355.74));
      expect(saldo.observacion, equals('Saldo disponible cierre 2025'));
    });

    test('crear - debe crear un saldo inicial mensual correctamente', () async {
      final id = await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'MES',
        periodoValor: '2026-01',
        monto: 500000.0,
        observacion: 'Saldo enero',
      );

      expect(id, greaterThan(0));

      final saldo = await SaldoInicialService.obtener(
        unidadGestionId: 1,
        periodoTipo: 'MES',
        periodoValor: '2026-01',
      );

      expect(saldo, isNotNull);
      expect(saldo!.periodoTipo, equals('MES'));
      expect(saldo.periodoValor, equals('2026-01'));
    });

    test('crear - debe rechazar duplicados', () async {
      // Crear el primero
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
      );

      // Intentar crear el mismo
      expect(
        () => SaldoInicialService.crear(
          unidadGestionId: 1,
          periodoTipo: 'ANIO',
          periodoValor: '2026',
          monto: 2000.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('crear - debe validar formato de período anual', () async {
      expect(
        () => SaldoInicialService.crear(
          unidadGestionId: 1,
          periodoTipo: 'ANIO',
          periodoValor: '26', // Inválido
          monto: 1000.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('crear - debe validar formato de período mensual', () async {
      expect(
        () => SaldoInicialService.crear(
          unidadGestionId: 1,
          periodoTipo: 'MES',
          periodoValor: '2026', // Falta mes
          monto: 1000.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('crear - debe rechazar montos negativos', () async {
      expect(
        () => SaldoInicialService.crear(
          unidadGestionId: 1,
          periodoTipo: 'ANIO',
          periodoValor: '2026',
          monto: -1000.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('actualizar - debe actualizar monto y observación', () async {
      final id = await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
        observacion: 'Original',
      );

      await SaldoInicialService.actualizar(
        id: id,
        monto: 2000.0,
        observacion: 'Actualizado',
      );

      final saldo = await SaldoInicialService.obtener(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
      );

      expect(saldo!.monto, equals(2000.0));
      expect(saldo.observacion, equals('Actualizado'));
    });

    test('actualizar - debe rechazar montos negativos', () async {
      final id = await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
      );

      expect(
        () => SaldoInicialService.actualizar(
          id: id,
          monto: -500.0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('eliminar - debe eliminar un saldo existente', () async {
      final id = await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
      );

      await SaldoInicialService.eliminar(id);

      final saldo = await SaldoInicialService.obtener(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
      );

      expect(saldo, isNull);
    });

    test('listar - debe listar todos los saldos', () async {
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
      );

      await SaldoInicialService.crear(
        unidadGestionId: 2,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 2000.0,
      );

      final saldos = await SaldoInicialService.listar();

      expect(saldos.length, equals(2));
    });

    test('listar - debe filtrar por unidad de gestión', () async {
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
      );

      await SaldoInicialService.crear(
        unidadGestionId: 2,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 2000.0,
      );

      final saldos = await SaldoInicialService.listar(unidadGestionId: 1);

      expect(saldos.length, equals(1));
      expect(saldos.first.unidadGestionId, equals(1));
    });

    test('calcularSaldoInicialMes - debe usar saldo anual para enero', () async {
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 8000000.0,
      );

      final saldo = await SaldoInicialService.calcularSaldoInicialMes(
        unidadGestionId: 1,
        anio: 2026,
        mes: 1,
      );

      expect(saldo, equals(8000000.0));
    });

    test('calcularSaldoInicialMes - debe preferir saldo mensual si existe', () async {
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 8000000.0,
      );

      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'MES',
        periodoValor: '2026-01',
        monto: 9000000.0,
      );

      final saldo = await SaldoInicialService.calcularSaldoInicialMes(
        unidadGestionId: 1,
        anio: 2026,
        mes: 1,
      );

      // Debe usar el saldo mensual específico
      expect(saldo, equals(9000000.0));
    });

    test('calcularSaldoInicialMes - debe retornar 0 si no hay saldo para febrero sin saldo mensual', () async {
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 8000000.0,
      );

      // Para febrero (mes != 1) sin saldo mensual específico
      final saldo = await SaldoInicialService.calcularSaldoInicialMes(
        unidadGestionId: 1,
        anio: 2026,
        mes: 2,
      );

      expect(saldo, equals(0.0));
    });

    test('existe - debe retornar true si existe el saldo', () async {
      await SaldoInicialService.crear(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
        monto: 1000.0,
      );

      final existe = await SaldoInicialService.existe(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
      );

      expect(existe, isTrue);
    });

    test('existe - debe retornar false si no existe el saldo', () async {
      final existe = await SaldoInicialService.existe(
        unidadGestionId: 1,
        periodoTipo: 'ANIO',
        periodoValor: '2026',
      );

      expect(existe, isFalse);
    });

    test('generarPeriodoValor - debe generar valor anual correctamente', () {
      final valor = SaldoInicialService.generarPeriodoValor(
        periodoTipo: 'ANIO',
        anio: 2026,
      );

      expect(valor, equals('2026'));
    });

    test('generarPeriodoValor - debe generar valor mensual correctamente', () {
      final valor = SaldoInicialService.generarPeriodoValor(
        periodoTipo: 'MES',
        anio: 2026,
        mes: 3,
      );

      expect(valor, equals('2026-03'));
    });

    test('generarPeriodoValor - debe formatear mes con cero a la izquierda', () {
      final valor = SaldoInicialService.generarPeriodoValor(
        periodoTipo: 'MES',
        anio: 2026,
        mes: 1,
      );

      expect(valor, equals('2026-01'));
    });
  });
}
