import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/shared/services/movimiento_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Mock para PathProvider en tests
class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp/test_db';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  
  setUpAll(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });
  
  setUp(() async {
    await AppDatabase.resetForTests();
  });

  tearDown(() async {
    await AppDatabase.resetForTests();
  });

  test('Insertar movimiento con archivo adjunto', () async {
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
    final db = await AppDatabase.instance();
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
    final db = await AppDatabase.instance();
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
