// Barrel de compatibilidad: re-exporta todos los DAOs y AppDatabase.
// Los imports existentes de 'data/dao/db.dart' siguen funcionando sin cambios.
// Para codigo nuevo, importar el archivo especifico directamente.
export '../database/app_database.dart';
export 'error_log_dao.dart';
export 'buffet_dao.dart';
export 'tesoreria_dao.dart';
