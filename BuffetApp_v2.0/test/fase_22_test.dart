import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/shared/services/compromisos_service.dart';
import 'package:buffet_app/features/tesoreria/services/transferencia_service.dart';
import 'package:buffet_app/features/tesoreria/services/cuenta_service.dart';

/// Test de la Fase 22: Correcciones Críticas de UX y Lógica
/// 
/// Valida:
/// - 22.1: Recalcular estado de compromisos al modificar
/// - 22.3: Comisiones en transferencias bidireccionales
/// - 22.4: Cálculo correcto de saldos en detalle cuenta
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
    
    // Eliminar archivo de DB para forzar onCreate
    final dbFile = File('.dart_tool/sqflite_common_ffi/databases/barcancha.db');
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    
    // Asegurar que existe unidad de gestión de prueba
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'id': 1,
      'nombre': 'Unidad Test',
      'tipo': 'DISCIPLINA',
      'disciplina_ref': 'FUTBOL',
      'activo': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  });

  group('FASE 22.1 - Recalcular Estado de Compromisos', () {
    test('Recalcula cuotas_totales y cuotas_confirmadas al modificar compromiso', () async {
      final svc = CompromisosService.instance;
      final db = await AppDatabase.instance();

      // Crear compromiso inicial con 12 cuotas
      final compromisoId = await svc.crearCompromiso(
        unidadGestionId: 1,
        nombre: 'Sueldo DT',
        tipo: 'EGRESO',
        modalidad: 'RECURRENTE',
        monto: 10000,
        frecuencia: 'MENSUAL',
        fechaInicio: '2026-01-01',
        fechaFin: '2026-12-31',
        categoria: 'SUELDO',
      );

      // Generar cuotas iniciales (12 cuotas)
      final cuotasIniciales = await svc.generarCuotas(compromisoId);
      expect(cuotasIniciales.length, 12);
      
      await svc.guardarCuotas(compromisoId, cuotasIniciales);

      // Recalcular estado inicial para poblar cuotas
      await svc.recalcularEstado(compromisoId);

      // Verificar estado inicial
      var compromiso = await svc.obtenerCompromiso(compromisoId);
      expect(compromiso!['cuotas'], 12); // 12 cuotas generadas

      // Modificar: cambiar fecha fin para que solo tenga 10 cuotas
      await svc.actualizarCompromiso(
        compromisoId,
        fechaFin: '2026-10-31',
      );

      // Eliminar cuotas existentes y regenerar
      await db.delete('compromiso_cuotas', where: 'compromiso_id = ?', whereArgs: [compromisoId]);
      final cuotasNuevas = await svc.generarCuotas(compromisoId);
      expect(cuotasNuevas.length, 10); // Ahora solo 10 cuotas
      await svc.guardarCuotas(compromisoId, cuotasNuevas);

      // Recalcular estado
      final resultado = await svc.recalcularEstado(compromisoId);
      
      expect(resultado['cuotas_totales'], 10, reason: 'Debe reflejar las nuevas 10 cuotas');
      expect(resultado['cuotas_confirmadas'], 0, reason: 'Ninguna confirmada aún');

      // Confirmar 3 cuotas
      final cuotasGuardadas = await db.query(
        'compromiso_cuotas',
        where: 'compromiso_id = ?',
        whereArgs: [compromisoId],
        limit: 3,
      );

      for (final cuota in cuotasGuardadas) {
        await db.update(
          'compromiso_cuotas',
          {'estado': 'CONFIRMADO'},
          where: 'id = ?',
          whereArgs: [cuota['id']],
        );
      }

      // Recalcular nuevamente
      final resultadoFinal = await svc.recalcularEstado(compromisoId);
      
      expect(resultadoFinal['cuotas_totales'], 10);
      expect(resultadoFinal['cuotas_confirmadas'], 3, reason: '3 cuotas confirmadas');

      // Verificar que se guardó en la tabla compromisos
      compromiso = await svc.obtenerCompromiso(compromisoId);
      expect(compromiso!['cuotas'], 10);
      expect(compromiso['cuotas_confirmadas'], 3);
    });
  });

  group('FASE 22.3 - Comisiones en Transferencias Bidireccionales', () {
    test('Genera comisión en cuenta ORIGEN cuando cobra comisión por egreso', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();
      final db = await AppDatabase.instance();

      // Crear cuenta ORIGEN con comisión
      final cuentaOrigenId = await cuentaSvc.crear(
        nombre: 'Banco Origen',
        tipo: 'BANCO',
        unidadGestionId: 1,
        saldoInicial: 100000,
        tieneComision: true,
        comisionPorcentaje: 2.5, // 2.5% de comisión
      );

      // Crear cuenta DESTINO sin comisión
      final cuentaDestinoId = await cuentaSvc.crear(
        nombre: 'Billetera Destino',
        tipo: 'BILLETERA',
        unidadGestionId: 1,
        saldoInicial: 0,
      );

      // Realizar transferencia de $10,000
      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 10000,
        medioPagoId: 1,
      );

      // Verificar movimientos generados
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
        orderBy: 'tipo DESC, categoria ASC',
      );

      // Debe haber 3 movimientos:
      // 1. EGRESO en origen (transferencia)
      // 2. EGRESO en origen (comisión)
      // 3. INGRESO en destino
      expect(movimientos.length, 3, reason: 'Debe generar 3 movimientos');

      final movEgresoTransf = movimientos.firstWhere(
        (m) => m['tipo'] == 'EGRESO' && m['categoria'] == 'TRANSFERENCIA',
      );
      expect(movEgresoTransf['monto'], 10000);
      expect(movEgresoTransf['cuenta_id'], cuentaOrigenId);

      final movEgresoComision = movimientos.firstWhere(
        (m) => m['tipo'] == 'EGRESO' && m['categoria'] == 'COM_BANC',
      );
      expect(movEgresoComision['monto'], 250, reason: '2.5% de 10,000 = 250');
      expect(movEgresoComision['cuenta_id'], cuentaOrigenId, reason: 'Comisión en cuenta origen');

      final movIngreso = movimientos.firstWhere(
        (m) => m['tipo'] == 'INGRESO',
      );
      expect(movIngreso['monto'], 10000);
      expect(movIngreso['cuenta_id'], cuentaDestinoId);
    });

    test('Genera comisión en cuenta DESTINO cuando cobra comisión por ingreso', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();
      final db = await AppDatabase.instance();

      // Crear cuenta ORIGEN sin comisión
      final cuentaOrigenId = await cuentaSvc.crear(
        nombre: 'Caja Origen',
        tipo: 'CAJA',
        unidadGestionId: 1,
        saldoInicial: 50000,
      );

      // Crear cuenta DESTINO con comisión
      final cuentaDestinoId = await cuentaSvc.crear(
        nombre: 'Banco Destino',
        tipo: 'BANCO',
        unidadGestionId: 1,
        saldoInicial: 0,
        tieneComision: true,
        comisionPorcentaje: 1.0, // 1% de comisión
      );

      // Realizar transferencia de $5,000
      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 5000,
        medioPagoId: 1,
      );

      // Verificar movimientos generados
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
      );

      expect(movimientos.length, 3);

      final movComisionDestino = movimientos.firstWhere(
        (m) => m['tipo'] == 'EGRESO' && 
               m['categoria'] == 'COM_BANC' && 
               m['cuenta_id'] == cuentaDestinoId,
      );

      expect(movComisionDestino['monto'], 50, reason: '1% de 5,000 = 50');
      expect(movComisionDestino['cuenta_id'], cuentaDestinoId, reason: 'Comisión en cuenta destino');
    });

    test('Genera comisión en AMBAS cuentas si ambas cobran comisión', () async {
      final cuentaSvc = CuentaService();
      final transfSvc = TransferenciaService();
      final db = await AppDatabase.instance();

      // Crear cuenta ORIGEN con comisión
      final cuentaOrigenId = await cuentaSvc.crear(
        nombre: 'Banco A',
        tipo: 'BANCO',
        unidadGestionId: 1,
        saldoInicial: 100000,
        tieneComision: true,
        comisionPorcentaje: 1.5,
      );

      // Crear cuenta DESTINO con comisión
      final cuentaDestinoId = await cuentaSvc.crear(
        nombre: 'Banco B',
        tipo: 'BANCO',
        unidadGestionId: 1,
        saldoInicial: 0,
        tieneComision: true,
        comisionPorcentaje: 2.0,
      );

      // Realizar transferencia de $20,000
      final transferenciaId = await transfSvc.crear(
        cuentaOrigenId: cuentaOrigenId,
        cuentaDestinoId: cuentaDestinoId,
        monto: 20000,
        medioPagoId: 1,
      );

      // Verificar movimientos generados
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
      );

      // Debe haber 4 movimientos:
      // 1. EGRESO transferencia en origen
      // 2. EGRESO comisión en origen
      // 3. INGRESO en destino
      // 4. EGRESO comisión en destino
      expect(movimientos.length, 4, reason: 'Debe generar 4 movimientos (2 comisiones)');

      final comisionOrigen = movimientos.firstWhere(
        (m) => m['categoria'] == 'COM_BANC' && m['cuenta_id'] == cuentaOrigenId,
      );
      expect(comisionOrigen['monto'], 300, reason: '1.5% de 20,000 = 300');

      final comisionDestino = movimientos.firstWhere(
        (m) => m['categoria'] == 'COM_BANC' && m['cuenta_id'] == cuentaDestinoId,
      );
      expect(comisionDestino['monto'], 400, reason: '2% de 20,000 = 400');
    });
  });

  group('FASE 22.4 - Cálculo de Saldos Acumulados', () {
    test('Calcula saldo acumulado correctamente con movimientos mixtos', () async {
      final cuentaSvc = CuentaService();
      final db = await AppDatabase.instance();

      // Crear cuenta con saldo inicial de 1000
      final cuentaId = await cuentaSvc.crear(
        nombre: 'Caja Chica',
        tipo: 'CAJA',
        unidadGestionId: 1,
        saldoInicial: 1000,
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      // Agregar movimientos en orden cronológico
      // Mov 1: +100 → saldo = 1100
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'VENTA',
        'monto': 100,
        'medio_pago_id': 1,
        'eliminado': 0,
        'estado': 'CONFIRMADO',
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 1000,
      });

      // Mov 2: -50 → saldo = 1050
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'GASTO',
        'monto': 50,
        'medio_pago_id': 1,
        'eliminado': 0,
        'estado': 'CONFIRMADO',
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 2000,
      });

      // Mov 3: +200 → saldo = 1250
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'INGRESO',
        'categoria': 'VENTA',
        'monto': 200,
        'medio_pago_id': 1,
        'eliminado': 0,
        'estado': 'CONFIRMADO',
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 3000,
      });

      // Mov 4: -150 → saldo = 1100
      await db.insert('evento_movimiento', {
        'disciplina_id': 1,
        'cuenta_id': cuentaId,
        'tipo': 'EGRESO',
        'categoria': 'GASTO',
        'monto': 150,
        'medio_pago_id': 1,
        'eliminado': 0,
        'estado': 'CONFIRMADO',
        'sync_estado': 'PENDIENTE',
        'created_ts': now + 4000,
      });

      // Obtener movimientos en orden cronológico (más antiguo primero)
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'cuenta_id = ? AND eliminado = 0',
        whereArgs: [cuentaId],
        orderBy: 'created_ts ASC',
      );

      // Calcular saldos acumulados
      double saldoAcumulado = 1000; // Saldo inicial
      final saldosEsperados = [1100, 1050, 1250, 1100];

      for (int i = 0; i < movimientos.length; i++) {
        final mov = movimientos[i];
        final tipo = mov['tipo'] as String;
        final monto = (mov['monto'] as num).toDouble();

        if (tipo == 'INGRESO') {
          saldoAcumulado += monto;
        } else {
          saldoAcumulado -= monto;
        }

        expect(
          saldoAcumulado, 
          saldosEsperados[i],
          reason: 'Saldo acumulado después del movimiento ${i + 1} debe ser ${saldosEsperados[i]}',
        );
      }

      // Verificar saldo final
      final saldoFinal = await cuentaSvc.obtenerSaldo(cuentaId);
      expect(saldoFinal, 1100, reason: 'Saldo final debe ser 1100');
    });
  });
}
