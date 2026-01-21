import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/tesoreria/services/acuerdos_grupales_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() async {
    // Inicializar FFI para tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Mock path_provider para usar carpeta temporal
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final temp = await Directory.systemTemp.createTemp('buffet_test').then((d) => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (MethodCall call) async => temp,
    );
  });

  setUp(() async {
    await AppDatabase.resetForTests();
  });

  tearDown(() async {
    // Limpiar base de datos después de cada test
    await AppDatabase.resetForTests();
  });

  group('Acuerdos Grupales - Flujo Completo', () {
    test('Crear acuerdo grupal para 5 jugadores con pago mensual', () async {
      // ARRANGE: Preparar datos de prueba
      final db = await AppDatabase.instance();
      
      // 1. Crear unidad de gestión
      final unidadId = await db.insert('unidades_gestion', {
        'nombre': 'Fútbol Mayor Test',
        'tipo': 'DISCIPLINA',
        'disciplina_ref': 'FUTBOL',
        'activo': 1,
        'created_ts': DateTime.now().millisecondsSinceEpoch,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      });
      
      print('✓ Unidad de gestión creada: $unidadId');

      // 2. Verificar que exista la frecuencia MENSUAL
      final frecuencias = await db.query('frecuencias');
      print('Frecuencias disponibles: ${frecuencias.map((f) => f['codigo']).toList()}');
      
      final frecuenciaMensual = frecuencias.firstWhere(
        (f) => f['codigo'] == 'MENSUAL',
        orElse: () => throw Exception('Frecuencia MENSUAL no encontrada'),
      );
      print('✓ Frecuencia MENSUAL encontrada: ${frecuenciaMensual['descripcion']}');

      // 3. Verificar categorías disponibles
      final categorias = await db.query(
        'categoria_movimiento',
        where: 'activa = ? AND (tipo = ? OR tipo = ?)',
        whereArgs: [1, 'EGRESO', 'AMBOS'],
      );
      print('Categorías EGRESO disponibles: ${categorias.map((c) => c['nombre']).toList()}');
      
      if (categorias.isEmpty) {
        // Crear categoría de prueba si no existe
        await db.insert('categoria_movimiento', {
          'nombre': 'PAGO JUGADORES',
          'tipo': 'EGRESO',
          'icono': 'sports_soccer',
          'activa': 1,
          'created_ts': DateTime.now().millisecondsSinceEpoch,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
        });
        print('✓ Categoría PAGO JUGADORES creada');
      } else {
        print('✓ Categorías existentes verificadas');
      }

      // 4. Crear 5 jugadores de prueba
      final jugadoresIds = <int>[];
      for (int i = 1; i <= 5; i++) {
        final jugadorId = await db.insert('entidades_plantel', {
          'nombre': 'Jugador Test $i',
          'rol': 'JUGADOR',
          'alias': 'JT$i',
          'tipo_contratacion': 'LOCAL',
          'posicion': 'DELANTERO',
          'estado_activo': 1,
          'created_ts': DateTime.now().millisecondsSinceEpoch,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
        });
        jugadoresIds.add(jugadorId);
      }
      print('✓ 5 jugadores creados: $jugadoresIds');

      // 5. Preparar datos del acuerdo grupal
      final jugadoresConMonto = jugadoresIds.map((id) {
        return JugadorConMonto(
          id: id,
          nombre: 'Jugador Test ${jugadoresIds.indexOf(id) + 1}',
          rol: 'JUGADOR',
          alias: 'JT${jugadoresIds.indexOf(id) + 1}',
          tipoContratacion: 'LOCAL',
          posicion: 'DELANTERO',
          monto: 700000.0, // $700.000 por jugador
        );
      }).toList();

      final fechaInicio = DateTime.now();
      final fechaFin = DateTime(fechaInicio.year, fechaInicio.month + 12, fechaInicio.day);

      print('\n=== EJECUTANDO PREVIEW ===');
      
      // ACT: Generar preview
      final grupalSvc = AcuerdosGrupalesService.instance;
      final preview = await grupalSvc.generarPreview(
        nombre: 'Sueldos Plantel Test',
        tipo: 'EGRESO',
        modalidad: 'RECURRENTE',
        montoBase: 700000.0,
        frecuencia: 'MENSUAL',
        fechaInicio: _formatDate(fechaInicio),
        fechaFin: _formatDate(fechaFin),
        generaCompromisos: true,
        jugadores: jugadoresConMonto,
      );

      // ASSERT: Verificar preview
      expect(preview, isNotNull, reason: 'Preview no debe ser null');
      expect(preview.cantidadAcuerdos, equals(5), reason: 'Debe generar 5 acuerdos');
      expect(preview.previewsIndividuales.length, equals(5), reason: 'Debe haber 5 previews individuales');
      
      print('✓ Preview generado correctamente:');
      print('  - Acuerdos a crear: ${preview.cantidadAcuerdos}');
      print('  - Compromisos totales: ${preview.totalCompromisos}');
      print('  - Monto total comprometido: \$${preview.totalComprometido}');

      for (final p in preview.previewsIndividuales) {
        print('  - ${p.jugadorNombre}: \$${p.montoAjustado} x ${p.compromisosEstimados} cuotas');
      }

      print('\n=== CREANDO ACUERDOS ===');

      // ACT: Crear acuerdos grupales
      final resultado = await grupalSvc.crearAcuerdosGrupales(
        nombre: 'Sueldos Plantel Test',
        unidadGestionId: unidadId,
        tipo: 'EGRESO',
        modalidad: 'RECURRENTE',
        montoBase: 700000.0,
        frecuencia: 'MENSUAL',
        fechaInicio: _formatDate(fechaInicio),
        fechaFin: _formatDate(fechaFin),
        categoria: 'PAGO JUGADORES',
        observacionesComunes: 'Acuerdo grupal de prueba',
        generaCompromisos: true,
        jugadores: jugadoresConMonto,
      );

      // ASSERT: Verificar resultado
      expect(resultado, isNotNull, reason: 'Resultado no debe ser null');
      expect(resultado.todoExitoso, isTrue, reason: 'La creación debe ser exitosa');
      expect(resultado.cantidadCreados, equals(5), reason: 'Deben crearse 5 acuerdos');
      expect(resultado.errores, isEmpty, reason: 'No debe haber errores');

      print('✓ Acuerdos creados exitosamente:');
      print('  - Cantidad: ${resultado.cantidadCreados}');
      print('  - IDs: ${resultado.acuerdosCreados}');
      print('  - UUID grupal: ${resultado.grupalUuid}');

      // Verificar que los acuerdos se guardaron en DB
      final acuerdosEnDb = await db.query(
        'acuerdos',
        where: 'acuerdo_grupal_ref = ?',
        whereArgs: [resultado.grupalUuid],
      );

      expect(acuerdosEnDb.length, equals(5), reason: 'Deben existir 5 acuerdos en DB');
      print('✓ Acuerdos verificados en base de datos');

      // Verificar histórico
      final historico = await db.query(
        'acuerdos_grupales_historico',
        where: 'uuid_ref = ?',
        whereArgs: [resultado.grupalUuid],
      );

      expect(historico.length, equals(1), reason: 'Debe existir 1 registro histórico');
      expect(historico.first['cantidad_acuerdos_generados'], equals(5));
      print('✓ Histórico verificado en base de datos');

      // Verificar compromisos generados (si aplica)
      if (resultado.todoExitoso) {
        for (final acuerdoId in resultado.acuerdosCreados) {
          final compromisos = await db.query(
            'compromisos',
            where: 'acuerdo_id = ?',
            whereArgs: [acuerdoId],
          );
          
          if (compromisos.isNotEmpty) {
            final compromisoId = compromisos.first['id'] as int;
            final cuotas = await db.query(
              'compromiso_cuotas',
              where: 'compromiso_id = ?',
              whereArgs: [compromisoId],
            );
            print('  - Acuerdo #$acuerdoId: ${compromisos.length} compromisos, ${cuotas.length} cuotas');
            
            // Verificar que tiene las 13 cuotas esperadas
            expect(cuotas.length, equals(13), reason: 'Deben generarse 13 cuotas mensuales');
          }
        }
      }

      print('\n✅ TEST COMPLETADO EXITOSAMENTE');
    });

    test('Validar que no se puede crear sin categoría válida', () async {
      final db = await AppDatabase.instance();
      
      final unidadId = await db.insert('unidades_gestion', {
        'nombre': 'Test Unit',
        'tipo': 'DISCIPLINA',
        'disciplina_ref': 'FUTBOL',
        'activo': 1,
        'created_ts': DateTime.now().millisecondsSinceEpoch,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      });

      final jugadorId = await db.insert('entidades_plantel', {
        'nombre': 'Test Player',
        'rol': 'JUGADOR',
        'estado_activo': 1,
        'created_ts': DateTime.now().millisecondsSinceEpoch,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      });

      final grupalSvc = AcuerdosGrupalesService.instance;
      
      // ACT & ASSERT: Intentar crear con categoría vacía
      expect(
        () async => await grupalSvc.crearAcuerdosGrupales(
          nombre: 'Test',
          unidadGestionId: unidadId,
          tipo: 'EGRESO',
          modalidad: 'RECURRENTE',
          montoBase: 100000,
          frecuencia: 'MENSUAL',
          fechaInicio: _formatDate(DateTime.now()),
          categoria: '', // Categoría vacía
          generaCompromisos: false,
          jugadores: [
            JugadorConMonto(id: jugadorId, nombre: 'Test', monto: 100000),
          ],
        ),
        throwsException,
        reason: 'Debe lanzar error si la categoría está vacía',
      );
    });
  });
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
