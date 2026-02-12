import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Base de datos SQLite optimizada y reorganizada.
/// 
/// Principios de organización:
/// - Creación de tablas e índices consolidados en un solo lugar
/// - Seeds agrupados por dominio
/// - onUpgrade simplificado (resetea todo - app no en uso)
/// - Vistas para consultas comunes
class AppDatabase {
  static Database? _db;
  static bool _desktopFactoryInitialized = false;
  static DatabaseFactory? _explicitFactory;

  // ========================================================================
  // CONFIGURACIÓN Y CICLO DE VIDA
  // ========================================================================

  /// Solo para tests: cierra y resetea el singleton para aislar casos.
  static Future<void> resetForTests() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _desktopFactoryInitialized = false;
    _explicitFactory = null;
  }

  static void _ensureDesktopFactory() {
    if (_desktopFactoryInitialized) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      _explicitFactory = databaseFactoryFfi;
    }
    _desktopFactoryInitialized = true;
  }

  static Future<String> _dbFilePath() async {
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';

    if (isTest) {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'barcancha.db');
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        final baseDir = Directory(p.join(localAppData, 'Buffet_App'));
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
        return p.join(baseDir.path, 'barcancha.db');
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'barcancha.db');
  }

  static String nowLocalSqlString() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  static Future<Database> instance() async {
    if (_db != null) return _db!;

    _ensureDesktopFactory();
    final dbPath = await _dbFilePath();
    final factory = _explicitFactory ?? databaseFactory;
    
    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 19, // Agregar sync_estado a caja_diaria
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    return _db!;
  }

  // ========================================================================
  // HOOKS DE CICLO DE VIDA
  // ========================================================================

  static Future<void> _onConfigure(Database db) async {
    // FASE 24: Activar Foreign Keys globalmente para prevenir datos huérfanos
    await db.rawQuery('PRAGMA foreign_keys=ON');
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.rawQuery('PRAGMA synchronous=NORMAL');
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Activar FKs antes de crear tablas
    await db.rawQuery('PRAGMA foreign_keys=ON');
    
    final batch = db.batch();

    // 1. Tablas de catálogos base
    _createCatalogTables(batch);

    // 2. Tablas del módulo Buffet (ventas, productos, cajas)
    _createBuffetTables(batch);

    // 3. Tablas del módulo Tesorería (movimientos, compromisos, acuerdos, plantel)
    _createTesoreriaTables(batch);

    // 4. Tablas de sincronización y auditoría
    _createSyncTables(batch);

    await batch.commit(noResult: true);

    // 5. Índices (todos juntos después de crear tablas)
    await _createAllIndexes(db);

    // 6. Vistas para consultas comunes
    await _createViews(db);

    // 7. Seeds de datos iniciales
    await _seedAll(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migraciones idempotentes (NO destruir datos)
    
    // Migración a versión 13: Agregar columna observacion a categoria_movimiento
    if (oldVersion < 13) {
      try {
        // Primero verificar que la tabla existe
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='categoria_movimiento'"
        );
        
        if (tables.isNotEmpty) {
          // La tabla existe, intentar agregar columna
          await db.execute('''
            ALTER TABLE categoria_movimiento 
            ADD COLUMN observacion TEXT
          ''');
          print('✓ Migración v12→v13: Columna observacion agregada a categoria_movimiento');
        }
      } catch (e) {
        // Si la columna ya existe, ignorar el error
        if (!e.toString().contains('duplicate column')) {
          print('⚠ Error en migración v12→v13: $e');
          // No relanzar - continuar con otras migraciones
        }
      }
    }
    
    // Migración a versión 14: Migrar disciplinas → unidades_gestion
    if (oldVersion < 14) {
      await _migrateDisciplinasToUnidadesGestion(db);
    }
    
    // Migración a versión 15: Crear índices compuestos para paginación optimizada (Fase 32)
    if (oldVersion < 15) {
      await _createPaginationIndexes(db);
    }
    
    // Migración a versión 16: Versionado de acuerdos
    if (oldVersion < 16) {
      await _migrateAcuerdosVersioning(db);
    }
    
    // Migración a versión 17: Agregar columna fecha a evento_movimiento
    if (oldVersion < 17) {
      try {
        await db.execute('''
          ALTER TABLE evento_movimiento 
          ADD COLUMN fecha TEXT
        ''');
        print('✓ Migración v16→v17: Columna fecha agregada a evento_movimiento');
        
        // Backfill: inicializar fecha con created_ts convertido a YYYY-MM-DD
        await db.execute('''
          UPDATE evento_movimiento 
          SET fecha = date(created_ts / 1000, 'unixepoch', 'localtime')
          WHERE fecha IS NULL
        ''');
        print('✓ Migración v16→v17: Backfill de fecha completado');
      } catch (e) {
        if (!e.toString().contains('duplicate column')) {
          print('⚠ Error en migración v16→v17: $e');
        }
      }
    }
    
    // Migración a versión 18: Agregar columna entidad_plantel_id a evento_movimiento
    if (oldVersion < 18) {
      try {
        await db.execute('''
          ALTER TABLE evento_movimiento 
          ADD COLUMN entidad_plantel_id INTEGER REFERENCES entidades_plantel(id)
        ''');
        print('✓ Migración v17→v18: Columna entidad_plantel_id agregada a evento_movimiento');
        
        // Crear índice para mejorar búsquedas por entidad
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_evento_mov_entidad_plantel 
          ON evento_movimiento(entidad_plantel_id, fecha DESC) 
          WHERE entidad_plantel_id IS NOT NULL
        ''');
        print('✓ Migración v17→v18: Índice idx_evento_mov_entidad_plantel creado');
      } catch (e) {
        if (!e.toString().contains('duplicate column')) {
          print('⚠ Error en migración v17→v18: $e');
        }
      }
    }
    
    // Migración a versión 19: Agregar sync_estado a caja_diaria
    if (oldVersion < 19) {
      try {
        await db.execute('''
          ALTER TABLE caja_diaria 
          ADD COLUMN sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE'
        ''');
        print('✓ Migración v18→v19: Columna sync_estado agregada a caja_diaria');
      } catch (e) {
        if (!e.toString().contains('duplicate column')) {
          print('⚠ Error en migración v18→v19: $e');
        }
      }
    }
    
    // Futuras migraciones irán aquí...
  }

  /// FASE 32: Crea índices compuestos para optimizar queries de paginación
  static Future<void> _createPaginationIndexes(Database db) async {
    try {
      print('🚀 Iniciando creación de índices de optimización (Fase 32)...');
      
      // Verificar si evento_movimiento tiene la columna unidad_gestion_id
      final columns = await db.rawQuery("PRAGMA table_info(evento_movimiento)");
      final hasUnidadColumn = columns.any((col) => col['name'] == 'unidad_gestion_id');
      
      if (hasUnidadColumn) {
        // Índices para evento_movimiento (solo si tiene la columna)
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_evento_mov_unidad_fecha 
          ON evento_movimiento(unidad_gestion_id, fecha DESC, created_ts DESC)
        ''');
        
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_evento_mov_unidad_tipo_fecha 
          ON evento_movimiento(unidad_gestion_id, tipo, fecha DESC)
        ''');
        
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_evento_mov_cuenta_fecha 
          ON evento_movimiento(cuenta_id, fecha DESC) 
          WHERE cuenta_id IS NOT NULL
        ''');
        print('   ✓ 3 índices para evento_movimiento creados');
      } else {
        print('   ⚠ Columna unidad_gestion_id no existe en evento_movimiento, saltando índices');
      }
      
      // Verificar si entidades_plantel tiene la columna unidad_gestion_id
      final entidadesColumns = await db.rawQuery("PRAGMA table_info(entidades_plantel)");
      final hasEntidadUnidadColumn = entidadesColumns.any((col) => col['name'] == 'unidad_gestion_id');
      
      if (hasEntidadUnidadColumn) {
        // Índices para entidades_plantel (solo si tiene la columna)
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_entidades_unidad_activo_nombre 
          ON entidades_plantel(unidad_gestion_id, activo, apellido, nombre)
        ''');
        print('   ✓ 1 índice para entidades_plantel creado');
      } else {
        print('   ⚠ Columna unidad_gestion_id no existe en entidades_plantel, saltando índice');
      }
      
      // Índices para compromisos (paginación y filtros)
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_compromisos_unidad_fecha_venc 
        ON compromisos(unidad_gestion_id, fecha_vencimiento ASC, created_ts DESC)
      ''');
      
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_compromisos_unidad_estado_fecha 
        ON compromisos(unidad_gestion_id, estado, fecha_vencimiento ASC)
      ''');
      
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_compromisos_entidad_estado 
        ON compromisos(entidad_plantel_id, estado, fecha_vencimiento ASC) 
        WHERE entidad_plantel_id IS NOT NULL
      ''');
      print('   ✓ 3 índices para compromisos creados');
      
      print('✓ Fase 32: Índices compuestos creados exitosamente');
      
      await logLocalError(
        scope: 'db.migration.fase32',
        error: 'Índices de optimización creados (condicionales según schema)',
        stackTrace: null,
        payload: {'has_unidad_column_movimientos': hasUnidadColumn, 'has_unidad_column_entidades': hasEntidadUnidadColumn, 'version': 15},
      );
      
    } catch (e, stack) {
      print('⚠ Error en creación de índices Fase 32: $e');
      await logLocalError(
        scope: 'db.migration.fase32',
        error: 'Error creando índices: $e',
        stackTrace: stack,
        payload: null,
      );
      // NO relanzar - permitir que la app continúe incluso si fallan algunos índices
    }
  }

  /// Migración v15→v16: Versionado de acuerdos
  static Future<void> _migrateAcuerdosVersioning(Database db) async {
    try {
      print('📦 Iniciando migración de versionado de acuerdos (v15→v16)...');
      
      // 1) Crear tabla acuerdos_versiones
      await db.execute('''
        CREATE TABLE IF NOT EXISTS acuerdos_versiones (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          acuerdo_id INTEGER NOT NULL,
          version INTEGER NOT NULL,
          modalidad TEXT NOT NULL,
          monto_total REAL,
          monto_periodico REAL,
          frecuencia TEXT NOT NULL,
          frecuencia_dias INTEGER,
          cuotas INTEGER,
          fecha_vigencia_desde TEXT NOT NULL,
          fecha_vigencia_hasta TEXT,
          motivo_cambio TEXT,
          dispositivo_id TEXT,
          created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
          FOREIGN KEY (acuerdo_id) REFERENCES acuerdos(id) ON DELETE CASCADE,
          UNIQUE(acuerdo_id, version)
        )
      ''');
      print('   ✓ Tabla acuerdos_versiones creada');
      
      // 2) Agregar columnas a acuerdos (idempotente)
      await ensureAcuerdosColumn(db, 'version_actual', 'INTEGER NOT NULL DEFAULT 1');
      await ensureAcuerdosColumn(db, 'fecha_vigencia_desde', 'TEXT');
      print('   ✓ Columnas version_actual y fecha_vigencia_desde verificadas');
      
      // 3) Backfill: establecer fecha_vigencia_desde en acuerdos existentes
      await db.execute('''
        UPDATE acuerdos 
        SET fecha_vigencia_desde = fecha_inicio
        WHERE fecha_vigencia_desde IS NULL
      ''');
      print('   ✓ Backfill de fecha_vigencia_desde completado');
      
      // 4) Crear versión inicial para acuerdos existentes
      final acuerdos = await db.query('acuerdos');
      int versionesCreadas = 0;
      
      for (final acuerdo in acuerdos) {
        try {
          await db.insert('acuerdos_versiones', {
            'acuerdo_id': acuerdo['id'],
            'version': 1,
            'modalidad': acuerdo['modalidad'],
            'monto_total': acuerdo['monto_total'],
            'monto_periodico': acuerdo['monto_periodico'],
            'frecuencia': acuerdo['frecuencia'],
            'frecuencia_dias': acuerdo['frecuencia_dias'],
            'cuotas': acuerdo['cuotas'],
            'fecha_vigencia_desde': acuerdo['fecha_vigencia_desde'] ?? acuerdo['fecha_inicio'],
            'fecha_vigencia_hasta': null,
            'motivo_cambio': 'Versión inicial',
            'dispositivo_id': acuerdo['dispositivo_id'],
            'created_ts': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          versionesCreadas++;
        } catch (e) {
          print('⚠ Error creando versión inicial para acuerdo ${acuerdo['id']}: $e');
        }
      }
      
      print('✓ Versionado de acuerdos completado ($versionesCreadas versiones iniciales creadas)');
      
    } catch (e, stack) {
      print('⚠ Error en migración de versionado de acuerdos: $e');
      await logLocalError(
        scope: 'db.migration.v16',
        error: 'Error en versionado: $e',
        stackTrace: stack,
      );
      // NO relanzar - permitir que la app continúe
    }
  }

  /// Helper: asegura que exista una columna en la tabla acuerdos
  static Future<void> ensureAcuerdosColumn(Database db, String columnName, String columnDef) async {
    try {
      final columns = await db.rawQuery("PRAGMA table_info(acuerdos)");
      final exists = columns.any((col) => col['name'] == columnName);
      
      if (!exists) {
        await db.execute('ALTER TABLE acuerdos ADD COLUMN $columnName $columnDef');
        print('   ✓ Columna $columnName agregada a acuerdos');
      }
    } catch (e) {
      if (!e.toString().contains('duplicate column')) {
        print('⚠ Error verificando columna $columnName: $e');
      }
    }
  }

  /// Migra datos de tabla disciplinas a unidades_gestion (Fase 22.1)
  static Future<void> _migrateDisciplinasToUnidadesGestion(Database db) async {
    try {
      print('📦 Iniciando migración disciplinas → unidades_gestion...');
      
      // 1) Verificar que ambas tablas existen
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('disciplinas','unidades_gestion')"
      );
      
      if (tables.length < 2) {
        print('⚠ Tablas necesarias no encontradas, saltando migración');
        return;
      }
      
      // 2) Contar disciplinas existentes
      final countResult = await db.rawQuery('SELECT COUNT(*) as total FROM disciplinas');
      final totalDisciplinas = (countResult.first['total'] as int?) ?? 0;
      print('   Disciplinas encontradas: $totalDisciplinas');
      
      if (totalDisciplinas == 0) {
        print('   No hay disciplinas que migrar');
        return;
      }
      
      // 3) Migrar cada disciplina a unidad_gestion
      final disciplinas = await db.rawQuery('SELECT id, nombre FROM disciplinas');
      int migradas = 0;
      
      for (final disc in disciplinas) {
        final id = disc['id'] as int;
        final nombre = disc['nombre'] as String;
        
        try {
          await db.rawInsert('''
            INSERT OR IGNORE INTO unidades_gestion 
            (id, nombre, tipo, disciplina_ref, activo, created_ts, updated_ts)
            VALUES (?, ?, 'DISCIPLINA', ?, 1, ?, ?)
          ''', [
            id,
            nombre,
            'DISC_$id', // disciplina_ref único para referencia
            DateTime.now().millisecondsSinceEpoch,
            DateTime.now().millisecondsSinceEpoch,
          ]);
          migradas++;
        } catch (e) {
          print('⚠ Error migrando disciplina $id ($nombre): $e');
        }
      }
      
      print('✓ Migradas $migradas/$totalDisciplinas disciplinas a unidades_gestion');
      
      // 4) Backfill de evento_movimiento (si la columna existe)
      try {
        // Verificar si evento_movimiento existe
        final movTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='evento_movimiento'"
        );
        
        if (movTable.isNotEmpty) {
          // Verificar si tiene la columna unidad_gestion_id
          final columns = await db.rawQuery("PRAGMA table_info(evento_movimiento)");
          final hasColumn = columns.any((col) => col['name'] == 'unidad_gestion_id');
          
          if (hasColumn) {
            // Actualizar movimientos que no tienen unidad asignada
            final updateResult = await db.rawUpdate('''
              UPDATE evento_movimiento 
              SET unidad_gestion_id = (
                SELECT id FROM unidades_gestion 
                WHERE disciplina_ref = 'DISC_' || evento_movimiento.disciplina_id
              )
              WHERE unidad_gestion_id IS NULL 
              AND disciplina_id IS NOT NULL
            ''');
            print('   Actualizados $updateResult movimientos con unidad_gestion_id');
          }
        }
      } catch (e) {
        print('⚠ Error en backfill de evento_movimiento: $e');
        // No relanzar - esta parte es opcional
      }
      
      // 5) Validación final
      final ugCount = await db.rawQuery('SELECT COUNT(*) as total FROM unidades_gestion WHERE tipo="DISCIPLINA"');
      final totalUnidades = (ugCount.first['total'] as int?) ?? 0;
      
      print('✓ Migración completada: $totalUnidades unidades de gestión tipo DISCIPLINA');
      
      await logLocalError(
        scope: 'db.migration.fase22',
        error: 'Migración exitosa: $migradas disciplinas → unidades_gestion',
        stackTrace: null,
        payload: {
          'disciplinas_originales': totalDisciplinas,
          'migradas': migradas,
          'unidades_finales': totalUnidades,
        },
      );
      
    } catch (e, stack) {
      print('❌ Error crítico en migración disciplinas → unidades_gestion: $e');
      await logLocalError(
        scope: 'db.migration.fase22',
        error: 'Error en migración: $e',
        stackTrace: stack,
        payload: null,
      );
      // NO relanzar - permitir que la app continúe
    }
  }

  // ========================================================================
  // CREACIÓN DE TABLAS POR DOMINIO
  // ========================================================================

  static void _createCatalogTables(Batch batch) {
    // metodos_pago
    batch.execute('''
      CREATE TABLE metodos_pago (
        id INTEGER PRIMARY KEY,
        descripcion TEXT NOT NULL,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // Categoria_Producto
    batch.execute('''
      CREATE TABLE Categoria_Producto (
        id INTEGER PRIMARY KEY,
        descripcion TEXT NOT NULL,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // punto_venta
    batch.execute('''
      CREATE TABLE punto_venta (
        codigo TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        alias_caja TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // disciplinas (legacy - mantener para compatibilidad)
    batch.execute('''
      CREATE TABLE disciplinas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE NOT NULL,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // unidades_gestion (reemplazo conceptual de disciplinas)
    batch.execute('''
      CREATE TABLE unidades_gestion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('DISCIPLINA','COMISION','EVENTO')),
        disciplina_ref TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // frecuencias (para compromisos)
    batch.execute('''
      CREATE TABLE frecuencias (
        codigo TEXT PRIMARY KEY,
        descripcion TEXT NOT NULL,
        dias INTEGER
      )
    ''');

    // categoria_movimiento (tesorería)
    batch.execute('''
      CREATE TABLE categoria_movimiento (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT UNIQUE NOT NULL,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO','AMBOS')),
        icono TEXT,
        observacion TEXT,
        activa INTEGER NOT NULL DEFAULT 1,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');
  }

  static void _createBuffetTables(Batch batch) {
    // products
    batch.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        codigo_producto TEXT UNIQUE,
        nombre TEXT NOT NULL,
        precio_compra INTEGER,
        precio_venta INTEGER NOT NULL,
        stock_actual INTEGER DEFAULT 0,
        stock_minimo INTEGER DEFAULT 3,
        orden_visual INTEGER,
        categoria_id INTEGER,
        visible INTEGER DEFAULT 1,
        color TEXT,
        imagen TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id)
      )
    ''');

    // caja_diaria
    batch.execute('''
      CREATE TABLE caja_diaria (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_caja TEXT UNIQUE,
        disciplina TEXT,
        fecha TEXT,
        usuario_apertura TEXT,
        cajero_apertura TEXT,
        visible INTEGER NOT NULL DEFAULT 1,
        hora_apertura TEXT,
        apertura_dt TEXT,
        fondo_inicial REAL,
        conteo_efectivo_final REAL,
        conteo_transferencias_final REAL,
        estado TEXT,
        ingresos REAL DEFAULT 0,
        retiros REAL DEFAULT 0,
        diferencia REAL,
        total_tickets INTEGER,
        tickets_anulados INTEGER,
        entradas INTEGER,
        hora_cierre TEXT,
        cierre_dt TEXT,
        usuario_cierre TEXT,
        cajero_cierre TEXT,
        descripcion_evento TEXT,
        observaciones_apertura TEXT,
        obs_cierre TEXT,
        sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')),
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // ventas
    batch.execute('''
      CREATE TABLE ventas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE,
        fecha_hora TEXT NOT NULL,
        total_venta REAL NOT NULL,
        status TEXT DEFAULT 'No impreso',
        activo INTEGER DEFAULT 1,
        metodo_pago_id INTEGER,
        caja_id INTEGER,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id),
        FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)
      )
    ''');

    // venta_items
    batch.execute('''
      CREATE TABLE venta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER NOT NULL,
        producto_id INTEGER NOT NULL,
        cantidad INTEGER NOT NULL,
        precio_unitario REAL NOT NULL,
        subtotal REAL NOT NULL,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
        FOREIGN KEY (producto_id) REFERENCES products(id)
      )
    ''');

    // tickets
    batch.execute('''
      CREATE TABLE tickets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER,
        categoria_id INTEGER,
        producto_id INTEGER,
        fecha_hora TEXT NOT NULL,
        status TEXT DEFAULT 'No impreso',
        total_ticket REAL NOT NULL,
        identificador_ticket TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (venta_id) REFERENCES ventas(id),
        FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id),
        FOREIGN KEY (producto_id) REFERENCES products(id)
      )
    ''');

    // caja_movimiento
    batch.execute('''
      CREATE TABLE caja_movimiento (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        caja_id INTEGER NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')),
        monto REAL NOT NULL CHECK (monto > 0),
        observacion TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)
      )
    ''');
  }

  static void _createTesoreriaTables(Batch batch) {
    // entidades_plantel (jugadores, DT, etc.)
    batch.execute('''
      CREATE TABLE entidades_plantel (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        rol TEXT NOT NULL CHECK (rol IN ('JUGADOR','DT','AYUDANTE','PF','OTRO')),
        estado_activo INTEGER NOT NULL DEFAULT 1,
        observaciones TEXT,
        foto_url TEXT,
        contacto TEXT,
        dni TEXT,
        fecha_nacimiento TEXT,
        tipo_contratacion TEXT CHECK (tipo_contratacion IS NULL OR tipo_contratacion IN ('LOCAL','REFUERZO','OTRO')),
        posicion TEXT CHECK (posicion IS NULL OR posicion IN ('ARQUERO','DEFENSOR','MEDIOCAMPISTA','DELANTERO','STAFF_CT')),
        alias TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // acuerdos (contratos que generan compromisos)
    batch.execute('''
      CREATE TABLE acuerdos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        unidad_gestion_id INTEGER NOT NULL,
        entidad_plantel_id INTEGER,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')),
        modalidad TEXT NOT NULL CHECK (modalidad IN ('MONTO_TOTAL_CUOTAS','RECURRENTE')),
        monto_total REAL,
        monto_periodico REAL,
        frecuencia TEXT NOT NULL,
        frecuencia_dias INTEGER,
        cuotas INTEGER,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT,
        categoria TEXT NOT NULL,
        observaciones TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        archivo_local_path TEXT,
        archivo_remote_url TEXT,
        archivo_nombre TEXT,
        archivo_tipo TEXT,
        archivo_size INTEGER,
        dispositivo_id TEXT,
        eliminado INTEGER NOT NULL DEFAULT 0,
        origen_grupal INTEGER NOT NULL DEFAULT 0,
        acuerdo_grupal_ref TEXT,
        version_actual INTEGER NOT NULL DEFAULT 1,
        fecha_vigencia_desde TEXT NOT NULL,
        sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')),
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id),
        FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id),
        FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo),
        CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
        CHECK ((modalidad = 'MONTO_TOTAL_CUOTAS' AND monto_total IS NOT NULL AND cuotas IS NOT NULL) 
               OR (modalidad = 'RECURRENTE' AND monto_periodico IS NOT NULL))
      )
    ''');

    // acuerdos_grupales_historico (auditoría)
    batch.execute('''
      CREATE TABLE acuerdos_grupales_historico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid_ref TEXT UNIQUE NOT NULL,
        nombre TEXT NOT NULL,
        unidad_gestion_id INTEGER NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')),
        modalidad TEXT NOT NULL,
        monto_base REAL NOT NULL,
        frecuencia TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT,
        categoria TEXT NOT NULL,
        observaciones_comunes TEXT,
        genera_compromisos INTEGER NOT NULL DEFAULT 1,
        cantidad_acuerdos_generados INTEGER NOT NULL,
        payload_filtros TEXT,
        payload_jugadores TEXT NOT NULL,
        dispositivo_id TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id)
      )
    ''');

    // acuerdos_versiones (historial de modificaciones de acuerdos)
    batch.execute('''
      CREATE TABLE acuerdos_versiones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        acuerdo_id INTEGER NOT NULL,
        version INTEGER NOT NULL,
        modalidad TEXT NOT NULL,
        monto_total REAL,
        monto_periodico REAL,
        frecuencia TEXT NOT NULL,
        frecuencia_dias INTEGER,
        cuotas INTEGER,
        fecha_vigencia_desde TEXT NOT NULL,
        fecha_vigencia_hasta TEXT,
        motivo_cambio TEXT,
        dispositivo_id TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (acuerdo_id) REFERENCES acuerdos(id) ON DELETE CASCADE,
        UNIQUE(acuerdo_id, version)
      )
    ''');

    // compromisos (obligaciones financieras)
    batch.execute('''
      CREATE TABLE compromisos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        acuerdo_id INTEGER,
        unidad_gestion_id INTEGER NOT NULL,
        entidad_plantel_id INTEGER,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')),
        modalidad TEXT NOT NULL DEFAULT 'RECURRENTE' CHECK (modalidad IN ('PAGO_UNICO','MONTO_TOTAL_CUOTAS','RECURRENTE')),
        monto REAL NOT NULL CHECK (monto > 0),
        frecuencia TEXT NOT NULL,
        frecuencia_dias INTEGER,
        cuotas INTEGER,
        cuotas_confirmadas INTEGER DEFAULT 0,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT,
        categoria TEXT NOT NULL,
        observaciones TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        archivo_local_path TEXT,
        archivo_remote_url TEXT,
        archivo_nombre TEXT,
        archivo_tipo TEXT,
        archivo_size INTEGER,
        dispositivo_id TEXT,
        eliminado INTEGER NOT NULL DEFAULT 0,
        sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')),
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (acuerdo_id) REFERENCES acuerdos(id),
        FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id),
        FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id),
        FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo),
        CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
      )
    ''');

    // compromiso_cuotas
    batch.execute('''
      CREATE TABLE compromiso_cuotas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        compromiso_id INTEGER NOT NULL,
        numero_cuota INTEGER NOT NULL,
        fecha_programada TEXT NOT NULL,
        monto_esperado REAL NOT NULL CHECK (monto_esperado > 0),
        estado TEXT NOT NULL DEFAULT 'ESPERADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO')),
        monto_real REAL,
        observacion_cancelacion TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (compromiso_id) REFERENCES compromisos(id) ON DELETE CASCADE,
        UNIQUE(compromiso_id, numero_cuota)
      )
    ''');

    // cuentas_fondos (cuentas bancarias, billeteras, cajas, inversiones)
    batch.execute('''
      CREATE TABLE cuentas_fondos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('BANCO','BILLETERA','CAJA','INVERSION')),
        unidad_gestion_id INTEGER NOT NULL,
        saldo_inicial REAL NOT NULL DEFAULT 0,
        tiene_comision INTEGER NOT NULL DEFAULT 0,
        comision_porcentaje REAL DEFAULT 0,
        activa INTEGER NOT NULL DEFAULT 1,
        observaciones TEXT,
        moneda TEXT DEFAULT 'ARS',
        banco_nombre TEXT,
        cbu_alias TEXT,
        dispositivo_id TEXT,
        eliminado INTEGER NOT NULL DEFAULT 0,
        sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')),
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id)
      )
    ''');

    // evento_movimiento (movimientos financieros externos al buffet)
    batch.execute('''
      CREATE TABLE evento_movimiento (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_id TEXT,
        disciplina_id INTEGER NOT NULL,
        cuenta_id INTEGER NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')),
        categoria TEXT,
        monto REAL NOT NULL CHECK (monto > 0),
        medio_pago_id INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        observacion TEXT,
        es_transferencia INTEGER NOT NULL DEFAULT 0,
        transferencia_id TEXT,
        dispositivo_id TEXT,
        archivo_local_path TEXT,
        archivo_remote_url TEXT,
        archivo_nombre TEXT,
        archivo_tipo TEXT,
        archivo_size INTEGER,
        eliminado INTEGER NOT NULL DEFAULT 0,
        compromiso_id INTEGER,
        entidad_plantel_id INTEGER,
        estado TEXT NOT NULL DEFAULT 'CONFIRMADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO')),
        sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')),
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        updated_ts INTEGER,
        FOREIGN KEY (cuenta_id) REFERENCES cuentas_fondos(id),
        FOREIGN KEY (medio_pago_id) REFERENCES metodos_pago(id),
        FOREIGN KEY (compromiso_id) REFERENCES compromisos(id),
        FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id)
      )
    ''');

    // saldos_iniciales
    batch.execute('''
      CREATE TABLE saldos_iniciales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        unidad_gestion_id INTEGER NOT NULL,
        periodo_tipo TEXT NOT NULL CHECK (periodo_tipo IN ('ANIO','MES')),
        periodo_valor TEXT NOT NULL,
        monto REAL NOT NULL,
        observacion TEXT,
        fecha_carga TEXT NOT NULL,
        FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id)
      )
    ''');
  }

  static void _createSyncTables(Batch batch) {
    // sync_outbox
    batch.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        ref TEXT NOT NULL,
        payload TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pending',
        reintentos INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
      )
    ''');

    // sync_error_log
    batch.execute('''
      CREATE TABLE sync_error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT,
        message TEXT,
        payload TEXT,
        created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // app_error_log
    batch.execute('''
      CREATE TABLE app_error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT,
        message TEXT,
        stacktrace TEXT,
        payload TEXT,
        created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // caja_cierre_resumen (descargas desde Supabase)
    batch.execute('''
      CREATE TABLE caja_cierre_resumen (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_fecha TEXT NOT NULL,
        disciplina TEXT NOT NULL,
        codigo_caja TEXT NOT NULL,
        source_device TEXT,
        items_count INTEGER NOT NULL DEFAULT 0,
        payload TEXT NOT NULL,
        created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  // ========================================================================
  // ÍNDICES (todos consolidados)
  // ========================================================================

  static Future<void> _createAllIndexes(Database db) async {
    // Catálogos
    await db.execute('CREATE INDEX idx_unidades_gestion_tipo ON unidades_gestion(tipo, activo)');

    // Cuentas fondos
    await db.execute('CREATE INDEX idx_cuentas_activa ON cuentas_fondos(activa, eliminado)');
    await db.execute('CREATE INDEX idx_cuentas_unidad ON cuentas_fondos(unidad_gestion_id, activa)');
    await db.execute('CREATE INDEX idx_cuentas_tipo ON cuentas_fondos(tipo, activa)');

    // Products
    await db.execute('CREATE INDEX idx_products_visible_cat_order ON products(visible, categoria_id, orden_visual)');

    // Caja diaria
    await db.execute('CREATE INDEX idx_caja_estado ON caja_diaria(estado)');

    // Ventas
    await db.execute('CREATE INDEX idx_ventas_fecha_hora ON ventas(fecha_hora)');
    await db.execute('CREATE INDEX idx_ventas_caja ON ventas(caja_id)');
    await db.execute('CREATE INDEX idx_ventas_mp ON ventas(metodo_pago_id)');
    await db.execute('CREATE INDEX idx_ventas_activo ON ventas(activo)');
    await db.execute('CREATE INDEX idx_ventas_caja_activo ON ventas(caja_id, activo)'); // Covering index

    // Venta items
    await db.execute('CREATE INDEX idx_items_venta_id ON venta_items(venta_id)');

    // Tickets
    await db.execute('CREATE INDEX idx_tickets_venta_id ON tickets(venta_id)');
    await db.execute('CREATE INDEX idx_tickets_categoria_id ON tickets(categoria_id)');
    await db.execute('CREATE INDEX idx_tickets_status ON tickets(status)');
    await db.execute('CREATE INDEX idx_tickets_fecha_hora ON tickets(fecha_hora)');

    // Movimientos de caja
    await db.execute('CREATE INDEX idx_mov_caja_id ON caja_movimiento(caja_id)');
    await db.execute('CREATE INDEX idx_mov_caja_tipo ON caja_movimiento(caja_id, tipo)');

    // Evento movimiento
    await db.execute('CREATE INDEX idx_evento_mov_disc_created ON evento_movimiento(disciplina_id, created_ts)');
    await db.execute('CREATE INDEX idx_evento_mov_evento_id ON evento_movimiento(evento_id)');
    await db.execute('CREATE INDEX idx_evento_mov_mp_id ON evento_movimiento(medio_pago_id)');
    await db.execute('CREATE INDEX idx_evento_mov_compromiso ON evento_movimiento(compromiso_id, estado)');
    await db.execute('CREATE INDEX idx_evento_mov_estado ON evento_movimiento(estado, created_ts)');
    await db.execute('CREATE INDEX idx_evento_mov_sync ON evento_movimiento(sync_estado)');
    await db.execute('CREATE INDEX idx_evento_mov_cuenta ON evento_movimiento(cuenta_id, created_ts)');
    await db.execute('CREATE INDEX idx_evento_mov_transferencia ON evento_movimiento(transferencia_id) WHERE transferencia_id IS NOT NULL');
    
    // FASE 32: Índices compuestos para paginación optimizada
    // NOTA: Los índices que requieren columnas agregadas en migraciones (unidad_gestion_id, fecha)
    // se crean en la migración v15 porque evento_movimiento no tiene esas columnas en onCreate

    // Entidades plantel
    await db.execute('CREATE INDEX idx_entidades_plantel_rol ON entidades_plantel(rol, estado_activo)');
    await db.execute('CREATE INDEX idx_entidades_plantel_activo ON entidades_plantel(estado_activo)');
    await db.execute('CREATE INDEX idx_entidades_plantel_tipo_contratacion ON entidades_plantel(tipo_contratacion, estado_activo) WHERE tipo_contratacion IS NOT NULL');
    await db.execute('CREATE INDEX idx_entidades_plantel_posicion ON entidades_plantel(posicion) WHERE posicion IS NOT NULL');
    // FASE 32: Índice para paginación y búsqueda de entidades
    // NOTA: El índice que requiere unidad_gestion_id se crea en la migración v15
    // porque entidades_plantel no tiene esa columna en onCreate
    // await db.execute('CREATE INDEX idx_entidades_unidad_activo_nombre ON entidades_plantel(unidad_gestion_id, activo, apellido, nombre)');

    // Acuerdos
    await db.execute('CREATE INDEX idx_acuerdos_unidad ON acuerdos(unidad_gestion_id, activo)');
    await db.execute('CREATE INDEX idx_acuerdos_tipo ON acuerdos(tipo, activo)');
    await db.execute('CREATE INDEX idx_acuerdos_entidad ON acuerdos(entidad_plantel_id) WHERE entidad_plantel_id IS NOT NULL');
    await db.execute('CREATE INDEX idx_acuerdos_sync ON acuerdos(sync_estado)');
    await db.execute('CREATE INDEX idx_acuerdos_eliminado ON acuerdos(eliminado, activo)');
    await db.execute('CREATE INDEX idx_acuerdos_grupal_ref ON acuerdos(acuerdo_grupal_ref) WHERE acuerdo_grupal_ref IS NOT NULL');

    // Acuerdos grupales
    await db.execute('CREATE INDEX idx_acuerdos_grupales_uuid ON acuerdos_grupales_historico(uuid_ref)');
    await db.execute('CREATE INDEX idx_acuerdos_grupales_unidad ON acuerdos_grupales_historico(unidad_gestion_id, created_ts)');

    // Compromisos
    await db.execute('CREATE INDEX idx_compromisos_acuerdo ON compromisos(acuerdo_id) WHERE acuerdo_id IS NOT NULL');
    await db.execute('CREATE INDEX idx_compromisos_unidad ON compromisos(unidad_gestion_id, activo)');
    await db.execute('CREATE INDEX idx_compromisos_tipo ON compromisos(tipo, activo)');
    await db.execute('CREATE INDEX idx_compromisos_sync ON compromisos(sync_estado)');
    await db.execute('CREATE INDEX idx_compromisos_eliminado ON compromisos(eliminado, activo)');
    await db.execute('CREATE INDEX idx_compromisos_entidad_plantel ON compromisos(entidad_plantel_id) WHERE entidad_plantel_id IS NOT NULL');
    // FASE 32: Índices para paginación y filtros de compromisos
    // NOTA: Los índices que requieren columnas agregadas en migraciones (fecha_vencimiento)
    // se crean en la migración v15 porque compromisos no tiene esas columnas en onCreate
    // await db.execute('CREATE INDEX idx_compromisos_unidad_fecha_venc ON compromisos(unidad_gestion_id, fecha_vencimiento ASC, created_ts DESC)');
    // await db.execute('CREATE INDEX idx_compromisos_unidad_estado_fecha ON compromisos(unidad_gestion_id, estado, fecha_vencimiento ASC)');
    // await db.execute('CREATE INDEX idx_compromisos_entidad_estado ON compromisos(entidad_plantel_id, estado, fecha_vencimiento ASC) WHERE entidad_plantel_id IS NOT NULL');

    // Compromiso cuotas
    await db.execute('CREATE INDEX idx_compromiso_cuotas_compromiso ON compromiso_cuotas(compromiso_id, numero_cuota)');
    await db.execute('CREATE INDEX idx_compromiso_cuotas_fecha ON compromiso_cuotas(fecha_programada, estado)');

    // Sync
    await db.execute('CREATE UNIQUE INDEX ux_outbox_tipo_ref ON sync_outbox(tipo, ref)');
    await db.execute('CREATE UNIQUE INDEX ux_caja_cierre_resumen_evento ON caja_cierre_resumen(evento_fecha, disciplina, codigo_caja)');
    await db.execute('CREATE UNIQUE INDEX ux_saldo_inicial_unidad_periodo ON saldos_iniciales(unidad_gestion_id, periodo_tipo, periodo_valor)');
  }

  // ========================================================================
  // VISTAS (para consultas comunes)
  // ========================================================================

  static Future<void> _createViews(Database db) async {
    // Vista para tickets con información completa
    // Esta query se repite en: sales_list_page, caja_tickets_page, export_service
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_tickets_completo AS
      SELECT 
        t.id,
        t.venta_id,
        t.fecha_hora,
        t.total_ticket,
        t.identificador_ticket,
        t.status,
        v.metodo_pago_id,
        mp.descripcion AS metodo_pago_desc,
        v.caja_id,
        COALESCE(p.nombre, cp.descripcion, '—') AS item_nombre,
        p.id AS producto_id,
        p.codigo_producto,
        cp.id AS categoria_id
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      LEFT JOIN Categoria_Producto cp ON cp.id = t.categoria_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
    ''');

    // Vista para compromisos con información de entidad
    // Se usa en compromisos_service y plantel_service
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_compromisos_completo AS
      SELECT
        c.*,
        ep.nombre AS entidad_nombre,
        ep.rol AS entidad_rol,
        ug.nombre AS unidad_nombre,
        ug.tipo AS unidad_tipo
      FROM compromisos c
      LEFT JOIN entidades_plantel ep ON ep.id = c.entidad_plantel_id
      LEFT JOIN unidades_gestion ug ON ug.id = c.unidad_gestion_id
      WHERE c.eliminado = 0
    ''');
    
    // FASE 22.5: Vista para acuerdos con información de entidad
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_acuerdos_completo AS
      SELECT
        a.*,
        ep.nombre AS entidad_nombre,
        ep.rol AS entidad_rol,
        ug.nombre AS unidad_nombre,
        ug.tipo AS unidad_tipo
      FROM acuerdos a
      LEFT JOIN entidades_plantel ep ON ep.id = a.entidad_plantel_id
      LEFT JOIN unidades_gestion ug ON ug.id = a.unidad_gestion_id
      WHERE a.eliminado = 0
    ''');
  }

  // ========================================================================
  // SEEDS (todos agrupados por dominio)
  // ========================================================================

  static Future<void> _seedAll(Database db) async {
    await _seedCatalogosBase(db);
    await _seedUnidadesGestion(db);
    await _seedFrecuencias(db);
    await _seedCategoriasMovimiento(db);
    await _seedProductos(db);
  }

  static Future<void> _seedCatalogosBase(Database db) async {
    const metodosPago = [
      {'id': 1, 'descripcion': 'Efectivo'},
      {'id': 2, 'descripcion': 'Transferencia'},
    ];
    for (final mp in metodosPago) {
      await db.insert('metodos_pago', mp, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    const categorias = [
      {'id': 1, 'descripcion': 'Comida'},
      {'id': 2, 'descripcion': 'Bebida'},
      {'id': 3, 'descripcion': 'Otro'},
    ];
    for (final c in categorias) {
      await db.insert('Categoria_Producto', c, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    const puntosVenta = [
      {'codigo': 'Caj01', 'nombre': 'Caja1'},
      {'codigo': 'Caj02', 'nombre': 'Caja2'},
      {'codigo': 'Caj03', 'nombre': 'Caja3'},
      {'codigo': 'Caj04', 'nombre': 'Caja4'},
    ];
    for (final pv in puntosVenta) {
      await db.insert('punto_venta', pv, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    const disciplinas = [
      {'id': 1, 'nombre': 'Futbol Infantil'},
      {'id': 2, 'nombre': 'Futbol Mayor'},
      {'id': 3, 'nombre': 'Evento'},
      {'id': 4, 'nombre': 'Voley'},
      {'id': 5, 'nombre': 'Tenis'},
      {'id': 6, 'nombre': 'Patin'},
      {'id': 7, 'nombre': 'Futbol Senior'},
      {'id': 8, 'nombre': 'Otros'},
    ];
    for (final d in disciplinas) {
      await db.insert('disciplinas', d, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedUnidadesGestion(Database db) async {
    const unidadesGestion = [
      {'id': 1, 'nombre': 'Fútbol Mayor', 'tipo': 'DISCIPLINA', 'disciplina_ref': 'FUTBOL', 'activo': 1},
      {'id': 2, 'nombre': 'Fútbol Infantil', 'tipo': 'DISCIPLINA', 'disciplina_ref': 'FUTBOL', 'activo': 1},
      {'id': 3, 'nombre': 'Vóley', 'tipo': 'DISCIPLINA', 'disciplina_ref': 'VOLEY', 'activo': 1},
      {'id': 4, 'nombre': 'Patín', 'tipo': 'DISCIPLINA', 'disciplina_ref': 'PATIN', 'activo': 1},
      {'id': 5, 'nombre': 'Tenis', 'tipo': 'DISCIPLINA', 'disciplina_ref': 'TENIS', 'activo': 1},
      {'id': 6, 'nombre': 'Fútbol Senior', 'tipo': 'DISCIPLINA', 'disciplina_ref': 'FUTBOL', 'activo': 1},
      {'id': 7, 'nombre': 'Comisión Directiva', 'tipo': 'COMISION', 'disciplina_ref': null, 'activo': 1},
      {'id': 8, 'nombre': 'Evento Especial', 'tipo': 'EVENTO', 'disciplina_ref': null, 'activo': 1},
    ];
    
    for (final u in unidadesGestion) {
      await db.insert('unidades_gestion', u, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedFrecuencias(Database db) async {
    const frecuencias = [
      {'codigo': 'SEMANAL', 'descripcion': 'Semanal', 'dias': 7},
      {'codigo': 'MENSUAL', 'descripcion': 'Mensual', 'dias': 30},
      {'codigo': 'BIMESTRAL', 'descripcion': 'Bimestral', 'dias': 60},
      {'codigo': 'TRIMESTRAL', 'descripcion': 'Trimestral', 'dias': 90},
      {'codigo': 'CUATRIMESTRAL', 'descripcion': 'Cuatrimestral', 'dias': 120},
      {'codigo': 'SEMESTRAL', 'descripcion': 'Semestral', 'dias': 180},
      {'codigo': 'ANUAL', 'descripcion': 'Anual', 'dias': 365},
      {'codigo': 'UNICA_VEZ', 'descripcion': 'Única vez', 'dias': null},
    ];
    
    for (final f in frecuencias) {
      await db.insert('frecuencias', f, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedCategoriasMovimiento(Database db) async {
    const categorias = [
      // INGRESOS
      {'codigo': 'ENTR', 'nombre': 'ENTRADAS', 'tipo': 'INGRESO', 'icono': 'confirmation_number', 'activa': 1},
      {'codigo': 'UTBP', 'nombre': 'UTILIDAD BAR Y PARRILLA', 'tipo': 'INGRESO', 'icono': 'restaurant', 'activa': 1},
      {'codigo': 'VENT', 'nombre': 'VENTA NÚMERO EN CANCHA', 'tipo': 'INGRESO', 'icono': 'sports_soccer', 'activa': 1},
      {'codigo': 'TRIB', 'nombre': 'TRIBUNA', 'tipo': 'INGRESO', 'icono': 'stadium', 'activa': 1},
      {'codigo': 'PUBL', 'nombre': 'REC.PUBLICIDAD ESTÁTICA Y GASTO', 'tipo': 'INGRESO', 'icono': 'campaign', 'activa': 1},
      {'codigo': 'COLA', 'nombre': 'COLABORADORES PAGO DT Y JUG', 'tipo': 'INGRESO', 'icono': 'volunteer_activism', 'activa': 1},
      {'codigo': 'PEIN', 'nombre': 'PEÑAS E INGRESOS VARIOS', 'tipo': 'INGRESO', 'icono': 'groups', 'activa': 1},
      {'codigo': 'COVE', 'nombre': 'COMISIONES VENTA RIFAS ETC.', 'tipo': 'INGRESO', 'icono': 'local_activity', 'activa': 1},
      {'codigo': 'INTE', 'nombre': 'INTERESES y GASTOS Cuenta', 'tipo': 'INGRESO', 'icono': 'account_balance', 'activa': 1},
      {'codigo': 'LIGA', 'nombre': 'LIGA - FICHAJES Y MULTAS', 'tipo': 'INGRESO', 'icono': 'gavel', 'activa': 1},
      {'codigo': 'COBR', 'nombre': 'COBROS Y PAGOS PASE JUGADOR', 'tipo': 'INGRESO', 'icono': 'swap_horiz', 'activa': 1},
      
      // EGRESOS
      {'codigo': 'SARB', 'nombre': 'SERVICIO DE ÁRBITROS', 'tipo': 'EGRESO', 'icono': 'sports', 'activa': 1},
      {'codigo': 'SPOL', 'nombre': 'SERVICIO POLICIA ADICIONAL', 'tipo': 'EGRESO', 'icono': 'local_police', 'activa': 1},
      {'codigo': 'FUMA', 'nombre': 'FUMIGACION', 'tipo': 'EGRESO', 'icono': 'pest_control', 'activa': 1},
      {'codigo': 'PAJU', 'nombre': 'PAGO JUGADORES', 'tipo': 'EGRESO', 'icono': 'people', 'activa': 1},
      {'codigo': 'MOAP', 'nombre': 'MOVILIDAD-APORTES Y GASTOS', 'tipo': 'EGRESO', 'icono': 'directions_bus', 'activa': 1},
      {'codigo': 'SGIN', 'nombre': 'SERVICIO GIMNASIO', 'tipo': 'EGRESO', 'icono': 'fitness_center', 'activa': 1},
      {'codigo': 'SPFT', 'nombre': 'SERVICIOS P.F. Y TÉCNICO', 'tipo': 'EGRESO', 'icono': 'medical_services', 'activa': 1},
      {'codigo': 'PALO', 'nombre': 'PAGO JUGADORES LOCALES', 'tipo': 'EGRESO', 'icono': 'home', 'activa': 1},
      {'codigo': 'GAAJ', 'nombre': 'GASTOS ATENCIÓN JUGADORES', 'tipo': 'EGRESO', 'icono': 'restaurant_menu', 'activa': 1},
      {'codigo': 'GAMF', 'nombre': 'GASTOS MÉDICOS Y FARMACIA', 'tipo': 'EGRESO', 'icono': 'local_pharmacy', 'activa': 1},
      {'codigo': 'LAAR', 'nombre': 'LAVADO y ARREGLOS INDUMENT.', 'tipo': 'EGRESO', 'icono': 'local_laundry_service', 'activa': 1},
      {'codigo': 'SEGU', 'nombre': 'SEGURO', 'tipo': 'EGRESO', 'icono': 'shield', 'activa': 1},
      {'codigo': 'PUPV', 'nombre': 'PUBLICIDAD - PAGOS VARIOS', 'tipo': 'EGRESO', 'icono': 'attach_money', 'activa': 1},
      {'codigo': 'GAS', 'nombre': 'GAS', 'tipo': 'EGRESO', 'icono': 'local_fire_department', 'activa': 1},
      {'codigo': 'ENEL', 'nombre': 'ENERGIA ELECTRICA', 'tipo': 'EGRESO', 'icono': 'bolt', 'activa': 1},
      {'codigo': 'PEQD', 'nombre': 'PELOTAS-EQUIPO DEPOR.', 'tipo': 'EGRESO', 'icono': 'sports_basketball', 'activa': 1},
      {'codigo': 'FERR', 'nombre': 'FERRETERIA', 'tipo': 'EGRESO', 'icono': 'hardware', 'activa': 1},
      {'codigo': 'MACI', 'nombre': 'MANT.CANCHA Y INSTALACIONES', 'tipo': 'EGRESO', 'icono': 'build', 'activa': 1},
      {'codigo': 'SEGE', 'nombre': 'SERVICIOS GENERALES / M.de Obra', 'tipo': 'EGRESO', 'icono': 'construction', 'activa': 1},
      {'codigo': 'LISE', 'nombre': 'LIMPIEZA - Servicios', 'tipo': 'EGRESO', 'icono': 'cleaning_services', 'activa': 1},
      {'codigo': 'OBRA', 'nombre': 'OBRAS', 'tipo': 'EGRESO', 'icono': 'engineering', 'activa': 1},
      {'codigo': 'BIUS', 'nombre': 'BIENES DE USO', 'tipo': 'EGRESO', 'icono': 'inventory_2', 'activa': 1},
      {'codigo': 'CEIG', 'nombre': 'CERCO-INGRESOS Y GASTOS', 'tipo': 'AMBOS', 'icono': 'fence', 'activa': 1},
      
      // Gestión de fondos
      {'codigo': 'TRANSFERENCIA', 'nombre': 'Transferencia entre cuentas', 'tipo': 'AMBOS', 'icono': 'swap_horiz', 'activa': 1},
      {'codigo': 'COM_BANC', 'nombre': 'Comisión bancaria', 'tipo': 'EGRESO', 'icono': 'account_balance', 'activa': 1},
      {'codigo': 'INT_PF', 'nombre': 'Interés plazo fijo', 'tipo': 'INGRESO', 'icono': 'trending_up', 'activa': 1},
      {'codigo': 'INDU', 'nombre': 'INDUMENTARIA', 'tipo': 'EGRESO', 'icono': 'checkroom', 'activa': 1},
      {'codigo': 'SEMA', 'nombre': 'SERVICIO MEDICO Y AMBULANCIA', 'tipo': 'EGRESO', 'icono': 'ambulance', 'activa': 1},
      {'codigo': 'GARE', 'nombre': 'GASTOS ATENCIÓN REFUERZOS', 'tipo': 'EGRESO', 'icono': 'dinner_dining', 'activa': 1},
      {'codigo': 'INGE', 'nombre': 'INGRESOS Y GASTOS SOCIOS', 'tipo': 'AMBOS', 'icono': 'card_membership', 'activa': 1},
      {'codigo': 'BINC', 'nombre': 'BINGO CLUB', 'tipo': 'AMBOS', 'icono': 'casino', 'activa': 1},
      {'codigo': 'DSAL', 'nombre': 'DIFERENCIA SALDO', 'tipo': 'AMBOS', 'icono': 'account_balance_wallet', 'activa': 1},
    ];
    
    for (final c in categorias) {
      await db.insert('categoria_movimiento', c, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _seedProductos(Database db) async {
    const productos = [
      {'codigo_producto': 'HAMB', 'nombre': 'Hamburguesa', 'precio_venta': 3000, 'precio_compra': 3000, 'stock_actual': 50, 'stock_minimo': 3, 'orden_visual': 1, 'categoria_id': 1, 'visible': 1},
      {'codigo_producto': 'CHOR', 'nombre': 'Choripan', 'precio_venta': 3000, 'precio_compra': 3000, 'stock_actual': 50, 'stock_minimo': 3, 'orden_visual': 2, 'categoria_id': 1, 'visible': 1},
      {'codigo_producto': 'JARG', 'nombre': 'Jarra gaseosa', 'precio_venta': 2000, 'precio_compra': 2000, 'stock_actual': 999, 'stock_minimo': 5, 'orden_visual': 3, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'VASO', 'nombre': 'Vaso gaseosa', 'precio_venta': 1500, 'precio_compra': 1500, 'stock_actual': 999, 'stock_minimo': 5, 'orden_visual': 4, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'CERV', 'nombre': 'Cerveza', 'precio_venta': 3000, 'precio_compra': 3000, 'stock_actual': 999, 'stock_minimo': 3, 'orden_visual': 5, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'FERN', 'nombre': 'Fernet', 'precio_venta': 5000, 'precio_compra': 5000, 'stock_actual': 999, 'stock_minimo': 3, 'orden_visual': 6, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'AGMT', 'nombre': 'Agua Mate', 'precio_venta': 1000, 'precio_compra': 1000, 'stock_actual': 50, 'stock_minimo': 3, 'orden_visual': 7, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'AGUA', 'nombre': 'Agua', 'precio_venta': 1000, 'precio_compra': 1000, 'stock_actual': 50, 'stock_minimo': 3, 'orden_visual': 8, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'VINO', 'nombre': 'Vino', 'precio_venta': 2000, 'precio_compra': 2000, 'stock_actual': 999, 'stock_minimo': 3, 'orden_visual': 9, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'HIEL', 'nombre': 'Hielo', 'precio_venta': 1000, 'precio_compra': 1000, 'stock_actual': 999, 'stock_minimo': 3, 'orden_visual': 10, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'GATO', 'nombre': 'Gatorade', 'precio_venta': 2500, 'precio_compra': 2500, 'stock_actual': 50, 'stock_minimo': 3, 'orden_visual': 11, 'categoria_id': 2, 'visible': 1},
      {'codigo_producto': 'PAPF', 'nombre': 'Papas fritas', 'precio_venta': 2000, 'precio_compra': 2000, 'stock_actual': 999, 'stock_minimo': 3, 'orden_visual': 12, 'categoria_id': 1, 'visible': 1},
      {'codigo_producto': 'JARR', 'nombre': 'Jarra', 'precio_venta': 3000, 'precio_compra': 3000, 'stock_actual': 999, 'stock_minimo': 3, 'orden_visual': 13, 'categoria_id': 3, 'visible': 1},
    ];
    
    for (final p in productos) {
      await db.insert('products', p, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ========================================================================
  // UTILIDADES Y MÉTODOS DE NEGOCIO
  // ========================================================================

  /// Loguea errores de la app en tabla local app_error_log (no falla la app).
  static Future<void> logLocalError({
    required String scope,
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? payload,
  }) async {
    try {
      // Si la base de datos aún no está inicializada (por ejemplo durante
      // onCreate/onUpgrade), no intentamos llamar a `instance()` para evitar
      // reentradas que bloqueen la inicialización. En ese caso, emitimos el
      // error por stdout y retornamos.
      if (_db == null) {
        print('LOG_LOCAL_ERROR (pre-init) [$scope]: ${error.toString()}');
        return;
      }

      final db = await instance();
      await db.insert(
        'app_error_log',
        {
          'scope': scope,
          'message': error.toString(),
          'stacktrace': stackTrace?.toString(),
          'payload': payload == null ? null : jsonEncode(payload),
          'created_ts': nowLocalSqlString(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      // Evitar ciclos de error
    }
  }

  /// Devuelve los últimos [limit] errores almacenados localmente.
  static Future<List<Map<String, dynamic>>> ultimosErrores({int limit = 50}) async {
    try {
      final db = await instance();
      final rows = await db.query('app_error_log', orderBy: 'id DESC', limit: limit);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      await logLocalError(scope: 'app_error_log.read', error: e, stackTrace: st);
      return const [];
    }
  }

  /// Borra todos los registros del log de errores local.
  static Future<int> clearErrorLogs() async {
    try {
      final db = await instance();
      return await db.delete('app_error_log');
    } catch (e, st) {
      await logLocalError(scope: 'app_error_log.clear', error: e, stackTrace: st);
      return 0;
    }
  }

  /// Elimina logs antiguos (política de retención).
  static Future<Map<String, int>> purgeOldErrorLogs({int months = 6}) async {
    final result = <String, int>{
      'app_error_log': 0,
      'sync_error_log': 0,
      'sync_outbox_error': 0,
    };

    if (months <= 0) return result;

    String toSqlString(DateTime d) {
      String two(int v) => v.toString().padLeft(2, '0');
      return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }

    try {
      final db = await instance();
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - months, now.day, now.hour, now.minute, now.second);
      final cutoffStr = toSqlString(cutoff);
      final cutoffMs = cutoff.millisecondsSinceEpoch;

      await db.transaction((txn) async {
        result['app_error_log'] = await txn.delete('app_error_log', where: 'created_ts < ?', whereArgs: [cutoffStr]);
        result['sync_error_log'] = await txn.delete('sync_error_log', where: 'created_ts < ?', whereArgs: [cutoffStr]);
        result['sync_outbox_error'] = await txn.delete('sync_outbox', where: 'tipo=? AND created_ts < ?', whereArgs: ['error', cutoffMs]);
      });
    } catch (e, st) {
      await logLocalError(scope: 'db.purgeOldErrorLogs', error: e, stackTrace: st, payload: {'months': months});
    }

    return result;
  }

  /// Devuelve cantidad total de cajas existentes.
  static Future<int> countCajas() async {
    try {
      final db = await instance();
      final v = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(1) FROM caja_diaria')) ?? 0;
      return v;
    } catch (e, st) {
      await logLocalError(scope: 'db.countCajas', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Purga todas las cajas y datos asociados.
  static Future<Map<String, int>> purgeCajasYAsociados() async {
    final result = <String, int>{};
    try {
      final db = await instance();
      await db.transaction((txn) async {
        result['venta_items'] = await txn.delete('venta_items');
        result['tickets'] = await txn.delete('tickets');
        result['caja_movimiento'] = await txn.delete('caja_movimiento');
        result['ventas'] = await txn.delete('ventas');
        result['caja_diaria'] = await txn.delete('caja_diaria');
        result['sync_outbox'] = await txn.delete('sync_outbox',
            where: "tipo IN (?,?,?,?,?)",
            whereArgs: ['venta', 'venta_anulada', 'cierre_caja', 'ticket_anulado', 'venta_item']);
      });
    } catch (e, st) {
      await logLocalError(scope: 'db.purgeCajasYAsociados', error: e, stackTrace: st);
      rethrow;
    }
    return result;
  }

  /// Crea backup físico de la DB.
  static Future<String> crearBackupArchivo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = await _dbFilePath();
      final ts = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'backup_barcancha_${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.db';
      final backupPath = p.join(dir.path, name);
      await File(dbPath).copy(backupPath);
      return backupPath;
    } catch (e, st) {
      await logLocalError(scope: 'db.crearBackupArchivo', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ========================================================================
  // SALDOS INICIALES - DAO
  // ========================================================================

  static Future<int> insertSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
    required double monto,
    String? observacion,
  }) async {
    final db = await instance();
    return await db.insert('saldos_iniciales', {
      'unidad_gestion_id': unidadGestionId,
      'periodo_tipo': periodoTipo,
      'periodo_valor': periodoValor,
      'monto': monto,
      'observacion': observacion,
      'fecha_carga': nowLocalSqlString(),
    });
  }

  static Future<Map<String, dynamic>?> obtenerSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final db = await instance();
    final result = await db.query('saldos_iniciales',
        where: 'unidad_gestion_id = ? AND periodo_tipo = ? AND periodo_valor = ?',
        whereArgs: [unidadGestionId, periodoTipo, periodoValor],
        limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  static Future<bool> existeSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final db = await instance();
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM saldos_iniciales WHERE unidad_gestion_id = ? AND periodo_tipo = ? AND periodo_valor = ?',
        [unidadGestionId, periodoTipo, periodoValor]);
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  static Future<List<Map<String, dynamic>>> listarSaldosIniciales({int? unidadGestionId}) async {
    final db = await instance();
    if (unidadGestionId != null) {
      return await db.query('saldos_iniciales',
          where: 'unidad_gestion_id = ?', whereArgs: [unidadGestionId], orderBy: 'periodo_valor DESC');
    }
    return await db.query('saldos_iniciales', orderBy: 'unidad_gestion_id, periodo_valor DESC');
  }

  static Future<int> actualizarSaldoInicial({
    required int id,
    required double monto,
    String? observacion,
  }) async {
    final db = await instance();
    return await db.update('saldos_iniciales', {'monto': monto, 'observacion': observacion},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> eliminarSaldoInicial(int id) async {
    final db = await instance();
    return await db.delete('saldos_iniciales', where: 'id = ?', whereArgs: [id]);
  }

  // ========================================================================
  // GESTIÓN DE BASE DE DATOS
  // ========================================================================

  /// Métodos de compatibilidad (deprecated - ya no son necesarios con onCreate limpio)
  /// Se mantienen como no-op para no romper código existente
  static Future<void> ensureCajaDiariaColumn(String name, String ddl) async {
    // No-op: columnas se crean en onCreate
  }

  static Future<void> ensureCajaCierreResumenTable() async {
    // No-op: tabla se crea en onCreate
  }

  static Future<void> ensureCompromisosTablas() async {
    // No-op: tablas se crean en onCreate
  }

  static Future<void> ensureEventoMovimientoCompromisosColumns() async {
    // No-op: columnas se crean en onCreate
  }

  static Future<void> ensureEntidadesPlantelTabla() async {
    // No-op: tabla se crea en onCreate
  }

  static Future<void> close() async {
    try {
      final db = _db;
      _db = null;
      await db?.close();
    } catch (_) {
      _db = null;
    }
  }

  /// Restaura estado de fábrica: elimina DB y recrea todo.
  static Future<void> factoryReset() async {
    await close();
    final dbPath = await _dbFilePath();
    await deleteDatabase(dbPath);
    
    // Limpieza WAL/SHM (best-effort)
    try {
      await File('$dbPath-wal').delete();
    } catch (_) {}
    try {
      await File('$dbPath-shm').delete();
    } catch (_) {}
  }
}
