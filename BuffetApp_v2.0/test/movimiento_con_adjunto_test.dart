import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/shared/services/movimiento_service.dart';

late String _tempDir;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  setUpAll(() async {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    _tempDir = await Directory.systemTemp.createTemp('buffet_test_adjunto').then((d) => d.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (MethodCall call) async => _tempDir,
    );
  });
  
  setUp(() async {
    await AppDatabase.close();
    final dbFile = File(p.join(_tempDir, 'barcancha.db'));
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  test('Insertar movimiento con archivo adjunto', () async {
    final db = await AppDatabase.instance();
    // Seed: unidad_gestion y cuenta_fondos requeridos por FK
    await db.insert('unidades_gestion', {
      'nombre': 'Test UG',
      'tipo': 'DISCIPLINA',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('cuentas_fondos', {
      'unidad_gestion_id': 1,
      'nombre': 'Caja Test',
      'tipo': 'CAJA',
      'activa': 1,
      'eliminado': 0,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final svc = EventoMovimientoService();
    
    // Crear movimiento con todos los campos de archivo
    final movId = await svc.crear(
      disciplinaId: 1,
      cuentaId: 1,
      eventoId: 'test-evento-123',
      tipo: 'INGRESO',
      categoria: 'Prueba',
      monto: 1000.0,
      medioPagoId: 1,
      observacion: 'Movimiento de prueba',
      dispositivoId: 'device-test',
      archivoLocalPath: '/path/to/file.jpg',
      archivoRemoteUrl: 'https://example.com/file.jpg',
      archivoNombre: 'file.jpg',
      archivoTipo: 'image/jpeg',
      archivoSize: 12345,
    );
    
    expect(movId, greaterThan(0));
    
    // Verificar que se guardó correctamente
    final rows = await db.query('evento_movimiento', where: 'id=?', whereArgs: [movId]);
    
    expect(rows.length, 1);
    final mov = rows.first;
    
    expect(mov['disciplina_id'], 1);
    expect(mov['tipo'], 'INGRESO');
    expect(mov['monto'], 1000.0);
    expect(mov['archivo_local_path'], '/path/to/file.jpg');
    expect(mov['archivo_remote_url'], 'https://example.com/file.jpg');
    expect(mov['archivo_nombre'], 'file.jpg');
    expect(mov['archivo_tipo'], 'image/jpeg');
    expect(mov['archivo_size'], 12345);
    
    print('✓ Movimiento con adjunto insertado correctamente');
    print('  - ID: $movId');
    print('  - Archivo local: ${mov['archivo_local_path']}');
    print('  - Archivo nombre: ${mov['archivo_nombre']}');
    print('  - Archivo tamaño: ${mov['archivo_size']} bytes');
  });

  test('Insertar movimiento SIN archivo adjunto', () async {
    final db = await AppDatabase.instance();
    await db.insert('unidades_gestion', {
      'nombre': 'Test UG',
      'tipo': 'DISCIPLINA',
      'activo': 1,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('cuentas_fondos', {
      'unidad_gestion_id': 1,
      'nombre': 'Caja Test',
      'tipo': 'CAJA',
      'activa': 1,
      'eliminado': 0,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    });

    final svc = EventoMovimientoService();
    
    // Crear movimiento sin campos de archivo (deben ser null)
    final movId = await svc.crear(
      disciplinaId: 1,
      cuentaId: 1,
      eventoId: null,
      tipo: 'EGRESO',
      categoria: 'Sin adjunto',
      monto: 500.0,
      medioPagoId: 1,
    );
    
    expect(movId, greaterThan(0));
    
    // Verificar que los campos de archivo son null
    final rows = await db.query('evento_movimiento', where: 'id=?', whereArgs: [movId]);
    
    expect(rows.length, 1);
    final mov = rows.first;
    
    expect(mov['archivo_local_path'], isNull);
    expect(mov['archivo_remote_url'], isNull);
    expect(mov['archivo_nombre'], isNull);
    expect(mov['archivo_tipo'], isNull);
    expect(mov['archivo_size'], isNull);
    
    print('✓ Movimiento sin adjunto insertado correctamente');
  });
}
