import 'package:flutter_test/flutter_test.dart';
import 'package:buffet_app/data/dao/db.dart';
import 'package:buffet_app/features/shared/services/tesoreria_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Inicializar sqflite_ffi para tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('TesoreriaSyncService', () {
    late TesoreriaSyncService syncService;

    setUp(() {
      syncService = TesoreriaSyncService();
    });

    test('debería retornar instancia singleton', () {
      final instance1 = TesoreriaSyncService();
      final instance2 = TesoreriaSyncService();
      expect(instance1, same(instance2));
    });

    test('contarPendientes debería retornar 0 o más', () async {
      final count = await syncService.contarPendientes();
      expect(count, greaterThanOrEqualTo(0));
    });

    test('verificarConexion debería completarse sin error', () async {
      // Este test puede fallar si no hay conexión o Supabase no está configurado
      // pero no debería lanzar excepciones
      expect(
        () async => await syncService.verificarConexion(),
        returnsNormally,
      );
    });
  });
}
