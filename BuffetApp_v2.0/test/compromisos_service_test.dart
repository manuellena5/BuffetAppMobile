import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/data/dao/db.dart';
import '../lib/features/shared/services/compromisos_service.dart';
import '../lib/features/shared/services/movimientos_proyectados_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock path_provider
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      return '.';
    });

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.resetForTests();
    final db = await AppDatabase.instance();
    
    // Insertar unidad de gestión de prueba (ya deberían existir del seed, pero por seguridad)
    await db.insert('unidades_gestion', {
      'id': 1,
      'nombre': 'Fútbol Mayor TEST',
      'tipo': 'DISCIPLINA',
      'disciplina_ref': 'FUTBOL',
      'activo': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    
    await db.insert('unidades_gestion', {
      'id': 2,
      'nombre': 'Fútbol Infantil TEST',
      'tipo': 'DISCIPLINA',
      'disciplina_ref': 'FUTBOL',
      'activo': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  });

  tearDown(() async {
    await AppDatabase.resetForTests();
  });

  group('CompromisosService - CRUD', () {
    final service = CompromisosService.instance;

    test('Crear compromiso válido', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Sponsor Empresa X',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 50000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Sponsor',
      );

      expect(id, greaterThan(0));

      final compromiso = await service.obtenerCompromiso(id);
      expect(compromiso, isNotNull);
      expect(compromiso!['nombre'], 'Sponsor Empresa X');
      expect(compromiso['tipo'], 'INGRESO');
      expect(compromiso['monto'], 50000.0);
      expect(compromiso['frecuencia'], 'MENSUAL');
      expect(compromiso['activo'], 1);
      expect(compromiso['eliminado'], 0);
      expect(compromiso['cuotas_confirmadas'], 0);
    });

    test('Crear compromiso con cuotas', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Seguro Anual',
        tipo: 'EGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 10000,
        frecuencia: 'MENSUAL',
        cuotas: 12,
        fechaInicio: '2026-01-01',
        fechaFin: '2026-12-31',
        categoria: 'Seguros',
      );

      final compromiso = await service.obtenerCompromiso(id);
      expect(compromiso!['cuotas'], 12);
      expect(compromiso['fecha_fin'], '2026-12-31');
    });

    test('Validar monto > 0', () async {
      expect(
        () => service.crearCompromiso(
          unidadGestionId: 1,
          nombre: 'Test',
          tipo: 'INGRESO',
          modalidad: 'RECURRENTE',
          monto: 0,
          frecuencia: 'MENSUAL',
          fechaInicio: '2026-01-01',
          categoria: 'Test',
        ),
        throwsArgumentError,
      );
    });

    test('Validar tipo válido', () async {
      expect(
        () => service.crearCompromiso(
          unidadGestionId: 1,
          nombre: 'Test',
          tipo: 'INVALIDO',
          modalidad: 'RECURRENTE',
          monto: 1000,
          frecuencia: 'MENSUAL',
          fechaInicio: '2026-01-01',
          categoria: 'Test',
        ),
        throwsArgumentError,
      );
    });

    test('Validar fecha_fin >= fecha_inicio', () async {
      expect(
        () => service.crearCompromiso(
          unidadGestionId: 1,
          nombre: 'Test',
          tipo: 'INGRESO',
          modalidad: 'RECURRENTE',
          monto: 1000,
          frecuencia: 'MENSUAL',
          fechaInicio: '2026-12-31',
          fechaFin: '2026-01-01',
          categoria: 'Test',
        ),
        throwsArgumentError,
      );
    });

    test('Validar frecuencia PERSONALIZADA requiere días', () async {
      expect(
        () => service.crearCompromiso(
          unidadGestionId: 1,
          nombre: 'Test',
          tipo: 'INGRESO',
          modalidad: 'RECURRENTE',
          monto: 1000,
          frecuencia: 'PERSONALIZADA',
          fechaInicio: '2026-01-01',
          categoria: 'Test',
        ),
        throwsArgumentError,
      );
    });

    test('Listar compromisos con filtros', () async {
      // Crear varios compromisos
      await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Ingreso 1',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Egreso 1',
        tipo: 'EGRESO',
        modalidad: 'RECURRENTE',
        monto: 500,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      await service.crearCompromiso(
        unidadGestionId: 2,
        nombre: 'Ingreso 2',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 2000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Filtrar por unidad
      final unidad1 = await service.listarCompromisos(unidadGestionId: 1);
      expect(unidad1.length >= 2, true); // Al menos los 2 de este test

      // Filtrar por tipo
      final ingresos = await service.listarCompromisos(tipo: 'INGRESO');
      expect(ingresos.length >= 2, true); // Al menos los 2 de este test

      final egresos = await service.listarCompromisos(tipo: 'EGRESO');
      expect(egresos.length >= 1, true); // Al menos el 1 de este test

      // Todos activos
      final activos = await service.listarCompromisos(activo: true);
      expect(activos.length >= 3, true); // Al menos los 3 de este test
    });

    test('Pausar y reactivar compromiso', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Pausar
      await service.pausarCompromiso(id);
      var compromiso = await service.obtenerCompromiso(id);
      expect(compromiso!['activo'], 0);

      // Reactivar
      await service.reactivarCompromiso(id);
      compromiso = await service.obtenerCompromiso(id);
      expect(compromiso!['activo'], 1);
    });

    test('Desactivar compromiso (soft delete)', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      await service.desactivarCompromiso(id);

      // No debería aparecer en obtenerCompromiso
      final compromiso = await service.obtenerCompromiso(id);
      expect(compromiso, isNull);

      // Pero sí con incluirEliminados
      final eliminados = await service.listarCompromisos(incluirEliminados: true);
      final miCompromiso = eliminados.where((c) => c['id'] == id).toList();
      expect(miCompromiso.length, 1);
      expect(miCompromiso.first['eliminado'], 1);
    });

    test('Actualizar compromiso', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Nombre Original',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Original',
      );

      await service.actualizarCompromiso(
        id,
        nombre: 'Nombre Actualizado',
        monto: 2000,
        categoria: 'Actualizada',
      );

      final compromiso = await service.obtenerCompromiso(id);
      expect(compromiso!['nombre'], 'Nombre Actualizado');
      expect(compromiso['monto'], 2000.0);
      expect(compromiso['categoria'], 'Actualizada');
      expect(compromiso['sync_estado'], 'PENDIENTE');
    });
  });

  group('CompromisosService - Cálculos', () {
    final service = CompromisosService.instance;

    test('Contar cuotas confirmadas', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 1000,
        frecuencia: 'MENSUAL',
        cuotas: 12,
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Simular movimiento confirmado
      final db = await AppDatabase.instance();
      await db.insert('evento_movimiento', {
        'compromiso_id': id,
        'disciplina_id': 1,
        'tipo': 'INGRESO',
        'categoria': 'Test',
        'monto': 1000,
        'medio_pago_id': 1,
        'estado': 'CONFIRMADO',
        'created_ts': DateTime.now().millisecondsSinceEpoch,
      });

      final confirmadas = await service.contarCuotasConfirmadas(id);
      expect(confirmadas, 1);
    });

    test('Calcular cuotas restantes', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 1000,
        frecuencia: 'MENSUAL',
        cuotas: 12,
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Sin movimientos
      var restantes = await service.calcularCuotasRestantes(id);
      expect(restantes, 12);

      // Simular 3 movimientos confirmados
      final db = await AppDatabase.instance();
      for (var i = 0; i < 3; i++) {
        await db.insert('evento_movimiento', {
          'compromiso_id': id,
          'disciplina_id': 1,
          'tipo': 'INGRESO',
          'categoria': 'Test',
          'monto': 1000,
          'medio_pago_id': 1,
          'estado': 'CONFIRMADO',
          'created_ts': DateTime.now().millisecondsSinceEpoch + i * 1000,
        });
      }

      restantes = await service.calcularCuotasRestantes(id);
      expect(restantes, 9);
    });

    test('Calcular próximo vencimiento - MENSUAL', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-15',
        categoria: 'Test',
      );

      final proximo = await service.calcularProximoVencimiento(id);
      expect(proximo, isNotNull);
      expect(proximo!.year, 2026);
      // El algoritmo suma 30 días desde fecha_inicio, no suma un mes calendario
      expect(proximo.month >= 1 && proximo.month <= 2, true);
      expect(proximo.day >= 14 && proximo.day <= 16, true);
    });

    test('Calcular próximo vencimiento - con movimiento previo', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Simular movimiento confirmado el 15 de enero
      final db = await AppDatabase.instance();
      final fechaPrevio = DateTime(2026, 1, 15);
      await db.insert('evento_movimiento', {
        'compromiso_id': id,
        'disciplina_id': 1,
        'tipo': 'INGRESO',
        'categoria': 'Test',
        'monto': 1000,
        'medio_pago_id': 1,
        'estado': 'CONFIRMADO',
        'created_ts': fechaPrevio.millisecondsSinceEpoch,
      });

      final proximo = await service.calcularProximoVencimiento(id);
      expect(proximo, isNotNull);
      // Debería ser ~15 de febrero (30 días después)
      expect(proximo!.month, 2);
      expect(proximo.day >= 14 && proximo.day <= 16, true);
    });

    test('Próximo vencimiento null si compromiso pausado', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      await service.pausarCompromiso(id);

      final proximo = await service.calcularProximoVencimiento(id);
      expect(proximo, isNull);
    });

    test('Próximo vencimiento null si cuotas completas', () async {
      final id = await service.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 1000,
        frecuencia: 'MENSUAL',
        cuotas: 3,
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Simular 3 movimientos confirmados
      final db = await AppDatabase.instance();
      for (var i = 0; i < 3; i++) {
        await db.insert('evento_movimiento', {
          'compromiso_id': id,
          'disciplina_id': 1,
          'tipo': 'INGRESO',
          'categoria': 'Test',
          'monto': 1000,
          'medio_pago_id': 1,
          'estado': 'CONFIRMADO',
          'created_ts': DateTime.now().millisecondsSinceEpoch + i * 1000,
        });
      }

      final proximo = await service.calcularProximoVencimiento(id);
      expect(proximo, isNull);
    });
  });

  group('MovimientosProyectadosService', () {
    final compromisosService = CompromisosService.instance;
    final proyectadosService = MovimientosProyectadosService.instance;

    /// Helper: crear compromiso y generar+guardar cuotas
    Future<int> crearCompromisoConCuotas({
      required int unidadGestionId,
      required String nombre,
      required String tipo,
      required String modalidad,
      required double monto,
      required String frecuencia,
      required String fechaInicio,
      int? cuotas,
      String? fechaFin,
      String? categoria,
    }) async {
      final id = await compromisosService.crearCompromiso(
        unidadGestionId: unidadGestionId,
        nombre: nombre,
        tipo: tipo,
        modalidad: modalidad,
        monto: monto,
        frecuencia: frecuencia,
        fechaInicio: fechaInicio,
        cuotas: cuotas,
        fechaFin: fechaFin,
        categoria: categoria ?? 'Test',
      );

      // Generar y guardar cuotas
      final cuotasGeneradas = await compromisosService.generarCuotas(id);
      if (cuotasGeneradas.isNotEmpty) {
        await compromisosService.guardarCuotas(id, cuotasGeneradas);
      }

      return id;
    }

    test('Calcular movimientos esperados - MENSUAL - 3 meses', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test Mensual',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 3, 31),
      );

      // MENSUAL: suma 1 mes a la fecha. Desde 2026-01-01: 01/01, 01/02, 01/03
      expect(movimientos.length, 3);
      expect(movimientos[0].fechaVencimiento, DateTime(2026, 1, 1)); // Enero
      expect(movimientos[1].fechaVencimiento, DateTime(2026, 2, 1)); // Febrero
      expect(movimientos[2].fechaVencimiento, DateTime(2026, 3, 1)); // Marzo
    });

    test('Excluir movimientos ya confirmados', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      // Marcar primera cuota como confirmada
      final cuotas = await compromisosService.obtenerCuotas(id);
      final primeraCuotaId = cuotas.first['id'] as int;
      await compromisosService.actualizarEstadoCuota(
        primeraCuotaId,
        'CONFIRMADO',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 3, 31),
      );

      // Excluye cuota 1 (confirmada), quedan cuotas 2 y 3
      expect(movimientos.length, 2);
      expect(movimientos[0].numeroCuota, 2);
      expect(movimientos[1].numeroCuota, 3);
    });

    test('Respetar límite de cuotas', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 1000,
        frecuencia: 'MENSUAL',
        cuotas: 3,
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 12, 31),
      );

      // Solo 3 cuotas aunque el rango sea de 12 meses
      expect(movimientos.length, 3);
    });

    test('MONTO_TOTAL_CUOTAS - fechas mensuales correctas', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Compromiso 3 Cuotas',
        tipo: 'EGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 3000,
        frecuencia: 'MENSUAL',
        cuotas: 3,
        fechaInicio: '2026-01-15',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 12, 31),
      );

      // Debe tener 3 cuotas
      expect(movimientos.length, 3);
      
      // Cuota 1: 15/01/2026
      expect(movimientos[0].numeroCuota, 1);
      expect(movimientos[0].fechaVencimiento, DateTime(2026, 1, 15));
      expect(movimientos[0].monto, 1000);
      
      // Cuota 2: 15/02/2026 (suma 1 mes)
      expect(movimientos[1].numeroCuota, 2);
      expect(movimientos[1].fechaVencimiento, DateTime(2026, 2, 15));
      expect(movimientos[1].monto, 1000);
      
      // Cuota 3: 15/03/2026 (suma 2 meses)
      expect(movimientos[2].numeroCuota, 3);
      expect(movimientos[2].fechaVencimiento, DateTime(2026, 3, 15));
      expect(movimientos[2].monto, 1000);
    });

    test('Respetar fecha_fin', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        fechaFin: '2026-03-31',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 12, 31),
      );

      // Solo hasta marzo (fecha_fin)
      expect(movimientos.length, 3);
      expect(movimientos.last.fechaVencimiento.month <= 3, true);
    });

    test('Frecuencia UNICA - un solo vencimiento', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Pago Único',
        tipo: 'EGRESO',
        modalidad: 'PAGO_UNICO',
        monto: 50000,
        frecuencia: 'UNICA',
        fechaInicio: '2026-02-15',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 12, 31),
      );

      expect(movimientos.length, 1);
      expect(movimientos.first.fechaVencimiento.month, 2);
      expect(movimientos.first.fechaVencimiento.day, 15);
    });

    test('Calcular movimientos esperados global', () async {
      // Crear 2 compromisos
      await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Compromiso 1',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Compromiso 2',
        tipo: 'EGRESO',
        modalidad: 'RECURRENTE',
        monto: 500,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-15',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperadosGlobal(
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 1, 31),
      );

      // Ambos empiezan en diferentes días, sumando 30 días generan múltiples vencimientos
      expect(movimientos.length >= 2, true); // Al menos 2 vencimientos
    });

    test('Calcular movimientos esperados por mes', () async {
      await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperadosMes(
        year: 2026,
        month: 2,
      );

      // En febrero caen vencimientos que suman 30 días desde inicio
      expect(movimientos.length >= 1, true);
      expect(movimientos.every((m) => m.fechaVencimiento.month == 2), true);
    });

    test('Calcular total esperado', () async {
      await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Ingreso',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 10000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Egreso',
        tipo: 'EGRESO',
        modalidad: 'RECURRENTE',
        monto: 3000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      final total = await proyectadosService.calcularTotalEsperado(
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 1, 31),
      );

      // Validar que hay ingresos, egresos y saldo calculado
      expect(total['ingresos']! >= 10000.0, true); // Al menos un vencimiento de cada
      expect(total['egresos']! >= 3000.0, true);
      expect(total['saldo'], total['ingresos']! - total['egresos']!);
    });

    test('Verificar si tiene movimientos esperados', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'RECURRENTE',
        monto: 1000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        fechaFin: '2026-03-31',
        categoria: 'Test',
      );

      final tiene = await proyectadosService.tieneMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
      );

      expect(tiene, true);

      // Después de fecha_fin
      final tieneFuturo = await proyectadosService.tieneMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 4, 1),
      );

      expect(tieneFuturo, false);
    });

    test('Modelo MovimientoProyectado - toMap', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Test',
        tipo: 'INGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 1000,
        frecuencia: 'MENSUAL',
        cuotas: 12,
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 1, 31),
      );

      final map = movimientos.first.toMap();
      expect(map['compromiso_id'], id);
      // Monto es dividido por cantidad de cuotas (1000 / 12 = 83.33...)
      expect(map['monto'], closeTo(83.33, 0.01));
      expect(map['tipo'], 'INGRESO');
      expect(map['estado'], 'ESPERADO');
      expect(map['fecha_vencimiento'], isNotNull);
    });

    test('Modelo MovimientoProyectado - descripcion', () async {
      final id = await crearCompromisoConCuotas(
        unidadGestionId: 1,
        nombre: 'Sponsor X',
        tipo: 'INGRESO',
        modalidad: 'MONTO_TOTAL_CUOTAS',
        monto: 1000,
        frecuencia: 'MENSUAL',
        cuotas: 12,
        fechaInicio: '2026-01-01',
        categoria: 'Test',
      );

      final movimientos = await proyectadosService.calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: DateTime(2026, 1, 1),
        fechaHasta: DateTime(2026, 1, 31),
      );

      final descripcion = movimientos.first.descripcion;
      expect(descripcion, contains('Sponsor X'));
      expect(descripcion, contains('Cuota'));
    });
  });
}
