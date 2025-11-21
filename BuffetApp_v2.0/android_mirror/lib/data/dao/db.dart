import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'barcancha.db');

    _db = await openDatabase(
      dbPath,
      version: 3,
      onConfigure: (db) async {
        // PRAGMAs: en Android usar rawQuery porque devuelven filas
        await db.rawQuery('PRAGMA foreign_keys=ON');
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA synchronous=NORMAL');
      },
      onCreate: (db, v) async {
        final batch = db.batch();

        // Tablas base de catálogos
        batch.execute('CREATE TABLE metodos_pago ('
            'id INTEGER PRIMARY KEY, '
            'descripcion TEXT NOT NULL, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
            ')');

        batch.execute('CREATE TABLE Categoria_Producto ('
            'id INTEGER PRIMARY KEY, '
            'descripcion TEXT NOT NULL, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
            ')');

        // Productos
        batch.execute('CREATE TABLE products ('
            'id INTEGER PRIMARY KEY, '
            'codigo_producto TEXT UNIQUE, '
            'nombre TEXT NOT NULL, '
            'precio_compra INTEGER, '
            'precio_venta INTEGER NOT NULL, '
            'stock_actual INTEGER DEFAULT 0, '
            'stock_minimo INTEGER DEFAULT 3, '
            'orden_visual INTEGER, '
            'categoria_id INTEGER, '
            'visible INTEGER DEFAULT 1, '
            'color TEXT, '
            'imagen TEXT, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            'FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id)'
            ')');
        batch.execute('CREATE INDEX idx_products_visible_cat_order '
            'ON products(visible, categoria_id, orden_visual)');

        // Caja diaria
        batch.execute('CREATE TABLE caja_diaria ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'codigo_caja TEXT UNIQUE, '
            'disciplina TEXT, '
            'fecha TEXT, '
            'usuario_apertura TEXT, '
            'cajero_apertura TEXT, '
          'visible INTEGER NOT NULL DEFAULT 1, '
            'hora_apertura TEXT, '
            'apertura_dt TEXT, '
            'fondo_inicial REAL, '
      'conteo_efectivo_final REAL, '
            'estado TEXT, '
            'ingresos REAL DEFAULT 0, '
            'retiros REAL DEFAULT 0, '
            'diferencia REAL, '
            'total_tickets INTEGER, '
            'tickets_anulados INTEGER, '
            'entradas INTEGER, '
            'hora_cierre TEXT, '
            'cierre_dt TEXT, '
            'usuario_cierre TEXT, '
            'cajero_cierre TEXT, '
            'descripcion_evento TEXT, '
            'observaciones_apertura TEXT, '
            'obs_cierre TEXT, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
            ')');
        batch.execute('CREATE INDEX idx_caja_estado ON caja_diaria(estado)');

        // Ventas + items
        batch.execute('CREATE TABLE ventas ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'uuid TEXT UNIQUE, '
            'fecha_hora TEXT NOT NULL, '
            'total_venta REAL NOT NULL, '
            "status TEXT DEFAULT 'No impreso', "
            'activo INTEGER DEFAULT 1, '
            'metodo_pago_id INTEGER, '
            'caja_id INTEGER, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            'FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id), '
            'FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)'
            ')');
        batch.execute('CREATE INDEX idx_ventas_fecha_hora ON ventas(fecha_hora)');
        batch.execute('CREATE INDEX idx_ventas_caja ON ventas(caja_id)');
        batch.execute('CREATE INDEX idx_ventas_mp ON ventas(metodo_pago_id)');
        batch.execute('CREATE INDEX idx_ventas_activo ON ventas(activo)');

        batch.execute('CREATE TABLE venta_items ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'venta_id INTEGER NOT NULL, '
            'producto_id INTEGER NOT NULL, '
            'cantidad INTEGER NOT NULL, '
            'precio_unitario REAL NOT NULL, '
            'subtotal REAL NOT NULL, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            'FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE, '
            'FOREIGN KEY (producto_id) REFERENCES products(id)'
            ')');
        batch.execute('CREATE INDEX idx_items_venta_id ON venta_items(venta_id)');

        // Tickets
        batch.execute('CREATE TABLE tickets ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'venta_id INTEGER, '
            'categoria_id INTEGER, '
            'producto_id INTEGER, '
            'fecha_hora TEXT NOT NULL, '
            "status TEXT DEFAULT 'No impreso', "
            'total_ticket REAL NOT NULL, '
            'identificador_ticket TEXT, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            'FOREIGN KEY (venta_id) REFERENCES ventas(id), '
            'FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id), '
            'FOREIGN KEY (producto_id) REFERENCES products(id)'
            ')');
        batch.execute('CREATE INDEX idx_tickets_venta_id ON tickets(venta_id)');
        batch.execute('CREATE INDEX idx_tickets_categoria_id ON tickets(categoria_id)');
        batch.execute('CREATE INDEX idx_tickets_status ON tickets(status)');

        // Movimientos de caja
        batch.execute('CREATE TABLE caja_movimiento ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'caja_id INTEGER NOT NULL, '
            "tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')), "
            'monto REAL NOT NULL CHECK (monto > 0), '
            'observacion TEXT, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            'FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)'
            ')');
        batch.execute('CREATE INDEX idx_mov_caja_id ON caja_movimiento(caja_id)');
        batch.execute('CREATE INDEX idx_mov_caja_tipo ON caja_movimiento(caja_id, tipo)');

        // Catálogo: Punto de venta / Disciplinas
        batch.execute('CREATE TABLE punto_venta ('
            'codigo TEXT PRIMARY KEY, '
            'nombre TEXT NOT NULL, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
            ')');
        batch.execute('CREATE TABLE disciplinas ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'nombre TEXT UNIQUE NOT NULL, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
            "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
            ')');

        // Outbox de sincronización con Supabase
        batch.execute('CREATE TABLE sync_outbox ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'tipo TEXT NOT NULL, '
            'ref TEXT NOT NULL, '
            'payload TEXT NOT NULL, '
            "estado TEXT NOT NULL DEFAULT 'pending', "
            'reintentos INTEGER NOT NULL DEFAULT 0, '
            'last_error TEXT, '
            "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
            ')');
        batch.execute('CREATE UNIQUE INDEX ux_outbox_tipo_ref ON sync_outbox(tipo, ref)');

        // Log de errores de sync (existente) y log de errores de app (nuevo)
        batch.execute('CREATE TABLE sync_error_log ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'scope TEXT, '
            'message TEXT, '
            'payload TEXT, '
            'created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP'
            ')');
        batch.execute('CREATE TABLE app_error_log ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'scope TEXT, '
            'message TEXT, '
            'stacktrace TEXT, '
            'payload TEXT, '
            'created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP'
            ')');

        await batch.commit(noResult: true);

        // Semillas iniciales (única vez)
        await _seedData(db);
      },
      // Migraciones para instalaciones previas (v1 -> v2)
      onUpgrade: (db, from, to) async {
        // Asegurar FKs (usar rawQuery en Android)
        await db.rawQuery('PRAGMA foreign_keys=ON');
        // Crear tablas ausentes (idempotente)
        await db.execute('CREATE TABLE IF NOT EXISTS metodos_pago (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
        await db.execute('CREATE TABLE IF NOT EXISTS Categoria_Producto (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
        await db.execute('CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, codigo_producto TEXT UNIQUE, nombre TEXT NOT NULL, precio_compra INTEGER, precio_venta INTEGER NOT NULL, stock_actual INTEGER DEFAULT 0, stock_minimo INTEGER DEFAULT 3, orden_visual INTEGER, categoria_id INTEGER, visible INTEGER DEFAULT 1, color TEXT, imagen TEXT, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id))');
        await db.execute('CREATE TABLE IF NOT EXISTS caja_diaria (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo_caja TEXT UNIQUE, disciplina TEXT, fecha TEXT, usuario_apertura TEXT, cajero_apertura TEXT, visible INTEGER NOT NULL DEFAULT 1, hora_apertura TEXT, apertura_dt TEXT, fondo_inicial REAL, estado TEXT, ingresos REAL DEFAULT 0, retiros REAL DEFAULT 0, diferencia REAL, total_tickets INTEGER, tickets_anulados INTEGER, entradas INTEGER, hora_cierre TEXT, cierre_dt TEXT, usuario_cierre TEXT, cajero_cierre TEXT, descripcion_evento TEXT, observaciones_apertura TEXT, obs_cierre TEXT, created_ts INTEGER, updated_ts INTEGER)');
        await db.execute('CREATE TABLE IF NOT EXISTS ventas (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT UNIQUE, fecha_hora TEXT NOT NULL, total_venta REAL NOT NULL, status TEXT DEFAULT "No impreso", activo INTEGER DEFAULT 1, metodo_pago_id INTEGER, caja_id INTEGER, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id), FOREIGN KEY (caja_id) REFERENCES caja_diaria(id))');
        await db.execute('CREATE TABLE IF NOT EXISTS venta_items (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER NOT NULL, producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL, precio_unitario REAL NOT NULL, subtotal REAL NOT NULL, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE, FOREIGN KEY (producto_id) REFERENCES products(id))');
        await db.execute('CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER, categoria_id INTEGER, producto_id INTEGER, fecha_hora TEXT NOT NULL, status TEXT DEFAULT "No impreso", total_ticket REAL NOT NULL, identificador_ticket TEXT, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (venta_id) REFERENCES ventas(id), FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id), FOREIGN KEY (producto_id) REFERENCES products(id))');
        await db.execute('CREATE TABLE IF NOT EXISTS caja_movimiento (id INTEGER PRIMARY KEY AUTOINCREMENT, caja_id INTEGER NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN (\'INGRESO\',\'RETIRO\')), monto REAL NOT NULL CHECK (monto > 0), observacion TEXT, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (caja_id) REFERENCES caja_diaria(id))');
        await db.execute('CREATE TABLE IF NOT EXISTS punto_venta (codigo TEXT PRIMARY KEY, nombre TEXT NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
        await db.execute('CREATE TABLE IF NOT EXISTS disciplinas (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT UNIQUE NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
        await db.execute('CREATE TABLE IF NOT EXISTS sync_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, tipo TEXT NOT NULL, ref TEXT NOT NULL, payload TEXT NOT NULL, estado TEXT NOT NULL DEFAULT \"pending\", reintentos INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_ts INTEGER NOT NULL DEFAULT (strftime(\'%s\',\'now\')*1000))');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_outbox_tipo_ref ON sync_outbox(tipo, ref)');
        await db.execute('CREATE TABLE IF NOT EXISTS sync_error_log (id INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT, message TEXT, payload TEXT, created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');
        await db.execute('CREATE TABLE IF NOT EXISTS app_error_log (id INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT, message TEXT, stacktrace TEXT, payload TEXT, created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');

        // Asegurar columnas nuevas en caja_diaria
        final cajaInfo = await db.rawQuery('PRAGMA table_info(caja_diaria)');
        Future<void> _ensureCol(String name, String ddl) async {
          final exists = cajaInfo.any((c) => (c['name'] as String?) == name);
          if (!exists) await db.execute('ALTER TABLE caja_diaria ADD COLUMN ' + ddl);
        }
        await _ensureCol('descripcion_evento', 'descripcion_evento TEXT');
        await _ensureCol('tickets_anulados', 'tickets_anulados INTEGER');
        await _ensureCol('entradas', 'entradas INTEGER');
        await _ensureCol('cajero_apertura', 'cajero_apertura TEXT');
        await _ensureCol('cajero_cierre', 'cajero_cierre TEXT');
        await _ensureCol('usuario_cierre', 'usuario_cierre TEXT');
        await _ensureCol('conteo_efectivo_final', 'conteo_efectivo_final REAL');
        await _ensureCol('visible', 'visible INTEGER NOT NULL DEFAULT 1');

        // Inicializar cajero_apertura si se agregó
        final hasCajeroA = cajaInfo.any((c) => (c['name'] as String?) == 'cajero_apertura');
        if (!hasCajeroA) {
          await db.rawUpdate("UPDATE caja_diaria SET cajero_apertura = COALESCE(usuario_apertura, 'admin')");
        }

        // Asegurar columna orden_visual en products
        final prodInfo = await db.rawQuery('PRAGMA table_info(products)');
        final hasOrden = prodInfo.any((c) => (c['name'] as String?) == 'orden_visual');
        if (!hasOrden) {
          await db.execute('ALTER TABLE products ADD COLUMN orden_visual INTEGER');
          await db.rawUpdate('UPDATE products SET orden_visual = 1000 + id WHERE orden_visual IS NULL');
        }
        // Índices útiles
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_visible_cat_order ON products(visible, categoria_id, orden_visual)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_fecha_hora ON ventas(fecha_hora)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_caja ON ventas(caja_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_mp ON ventas(metodo_pago_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_activo ON ventas(activo)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_items_venta_id ON venta_items(venta_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_venta_id ON tickets(venta_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_categoria_id ON tickets(categoria_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mov_caja_id ON caja_movimiento(caja_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mov_caja_tipo ON caja_movimiento(caja_id, tipo)');

        // Categorías base (evita errores FK)
        await db.insert('Categoria_Producto', {'id': 1, 'descripcion': 'Comida'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('Categoria_Producto', {'id': 2, 'descripcion': 'Bebidas'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        // Métodos de pago base
        await db.insert('metodos_pago', {'id': 1, 'descripcion': 'Efectivo'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('metodos_pago', {'id': 2, 'descripcion': 'Transferencia'}, conflictAlgorithm: ConflictAlgorithm.ignore);

        // Punto de venta y disciplinas mínimos
        final pvCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(1) FROM punto_venta')) ?? 0;
        if (pvCount == 0) {
          await db.insert('punto_venta', {'codigo': 'Caj01', 'nombre': 'Caja1'}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('punto_venta', {'codigo': 'Caj02', 'nombre': 'Caja2'}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('punto_venta', {'codigo': 'Caj03', 'nombre': 'Caja3'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        final disCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(1) FROM disciplinas')) ?? 0;
        if (disCount == 0) {
          await db.insert('disciplinas', {'nombre': 'Futbol Infantil'}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('disciplinas', {'nombre': 'Futbol Mayor'}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('disciplinas', {'nombre': 'Evento'}, conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('disciplinas', {'nombre': 'Otros'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // Deduplicar outbox pre-índice único (por si existía)
        await db.rawDelete('DELETE FROM sync_outbox WHERE id NOT IN (SELECT MAX(id) FROM sync_outbox GROUP BY tipo, ref)');
      },
    );

    return _db!;
  }

  /// Loguea errores de la app en tabla local app_error_log (no falla la app)
  static Future<void> logLocalError({
    required String scope,
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? payload,
  }) async {
    try {
      final db = await instance();
      await db.insert(
        'app_error_log',
        {
          'scope': scope,
          'message': error.toString(),
          'stacktrace': stackTrace?.toString(),
          'payload': payload == null ? null : jsonEncode(payload),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      // Evitar ciclos de error; como último recurso, ignorar
    }
  }

  /// Devuelve los últimos [limit] errores almacenados localmente.
  static Future<List<Map<String, dynamic>>> ultimosErrores({int limit = 50}) async {
    try {
      final db = await instance();
      final rows = await db.query('app_error_log', orderBy: 'id DESC', limit: limit);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      // Si incluso esto falla, registramos en memoria (no persistente)
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

  /// Asegura en tiempo de ejecución que la tabla caja_diaria tenga la columna indicada.
  /// Útil cuando la app ya estaba en v2 y no volvió a ejecutar onUpgrade.
  static Future<void> ensureCajaDiariaColumn(String name, String ddl) async {
    try {
      final db = await instance();
      final info = await db.rawQuery('PRAGMA table_info(caja_diaria)');
      final exists = info.any((c) => (c['name'] as String?) == name);
      if (!exists) {
        await db.execute('ALTER TABLE caja_diaria ADD COLUMN ' + ddl);
      }
    } catch (e, st) {
      await logLocalError(scope: 'db.ensureCajaDiariaColumn', error: e, stackTrace: st, payload: {'name': name, 'ddl': ddl});
      rethrow;
    }
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

  /// Purga todas las cajas y datos asociados (ventas, items, tickets, movimientos) + entradas relacionadas en outbox.
  /// Devuelve conteo de filas eliminadas por tabla. Se ejecuta en transacción.
  static Future<Map<String, int>> purgeCajasYAsociados() async {
    final result = <String, int>{};
    try {
      final db = await instance();
      await db.transaction((txn) async {
        // Orden respetando FKs
        result['venta_items'] = await txn.delete('venta_items');
        result['tickets'] = await txn.delete('tickets');
        result['caja_movimiento'] = await txn.delete('caja_movimiento');
        result['ventas'] = await txn.delete('ventas');
        result['caja_diaria'] = await txn.delete('caja_diaria');
        // Limpiar outbox de tipos relacionados para evitar referencias huérfanas
        result['sync_outbox'] = await txn.delete('sync_outbox', where: "tipo IN (?,?,?,?,?)", whereArgs: ['venta','venta_anulada','cierre_caja','ticket_anulado','venta_item'] );
      });
    } catch (e, st) {
      await logLocalError(scope: 'db.purgeCajasYAsociados', error: e, stackTrace: st);
      rethrow;
    }
    return result;
  }

  /// Crea un archivo físico de backup de la base de datos SQLite actual y devuelve la ruta.
  /// El archivo queda en el directorio de documentos de la app con nombre timestamp.
  static Future<String> crearBackupArchivo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'barcancha.db');
      final ts = DateTime.now();
      String two(int v) => v.toString().padLeft(2,'0');
      final name = 'backup_barcancha_${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.db';
      final backupPath = p.join(dir.path, name);
      await File(dbPath).copy(backupPath);
      return backupPath;
    } catch (e, st) {
      await logLocalError(scope: 'db.crearBackupArchivo', error: e, stackTrace: st);
      rethrow;
    }
  }
}

Future<void> _seedData(Database db) async {
  final batch = db.batch();

  // Métodos de pago
  batch.insert('metodos_pago', {'id': 1, 'descripcion': 'Efectivo'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('metodos_pago', {'id': 2, 'descripcion': 'Transferencia'}, conflictAlgorithm: ConflictAlgorithm.ignore);

  // Categorías base
  batch.insert('Categoria_Producto', {'id': 1, 'descripcion': 'Comida'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('Categoria_Producto', {'id': 2, 'descripcion': 'Bebidas'}, conflictAlgorithm: ConflictAlgorithm.ignore);

  // Catálogos de referencia (puntos de venta, disciplinas)
  batch.insert('punto_venta', {'codigo': 'Caj01', 'nombre': 'Caja1'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('punto_venta', {'codigo': 'Caj02', 'nombre': 'Caja2'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('punto_venta', {'codigo': 'Caj03', 'nombre': 'Caja3'}, conflictAlgorithm: ConflictAlgorithm.ignore);

  batch.insert('disciplinas', {'nombre': 'Futbol Infantil'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('disciplinas', {'nombre': 'Futbol Mayor'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('disciplinas', {'nombre': 'Evento'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  batch.insert('disciplinas', {'nombre': 'Otros'}, conflictAlgorithm: ConflictAlgorithm.ignore);

  // Productos precargados
  const productos = [
    {
      'codigo_producto': 'HAMB',
      'nombre': 'Hamburguesa',
      'precio_venta': 3000,
      'stock_actual': 50,
      'stock_minimo': 3,
      'orden_visual': 1,
      'categoria_id': 1,
      'visible': 1,
    },
    {
      'codigo_producto': 'CHOR',
      'nombre': 'Choripan',
      'precio_venta': 3000,
      'stock_actual': 50,
      'stock_minimo': 3,
      'orden_visual': 2,
      'categoria_id': 1,
      'visible': 1,
    },
    {
      'codigo_producto': 'JARR',
      'nombre': 'Jarra gaseosa',
      'precio_venta': 2000,
      'stock_actual': 999,
      'stock_minimo': 5,
      'orden_visual': 3,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'VASO',
      'nombre': 'Vaso gaseosa',
      'precio_venta': 1500,
      'stock_actual': 999,
      'stock_minimo': 5,
      'orden_visual': 4,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'CERV',
      'nombre': 'Cerveza',
      'precio_venta': 2000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 5,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'FERN',
      'nombre': 'Fernet',
      'precio_venta': 5000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 6,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'AGMT',
      'nombre': 'Agua Mate',
      'precio_venta': 1000,
      'stock_actual': 50,
      'stock_minimo': 3,
      'orden_visual': 7,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'AGUA',
      'nombre': 'Agua',
      'precio_venta': 1000,
      'stock_actual': 50,
      'stock_minimo': 3,
      'orden_visual': 8,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'VINO',
      'nombre': 'Vino',
      'precio_venta': 2000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 9,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'HIEL',
      'nombre': 'Hielo',
      'precio_venta': 1000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 10,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'GATO',
      'nombre': 'Gatorade',
      'precio_venta': 2500,
      'stock_actual': 50,
      'stock_minimo': 3,
      'orden_visual': 11,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'PAPF',
      'nombre': 'Papas fritas',
      'precio_venta': 2000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 12,
      'categoria_id': 1,
      'visible': 1,
    },
  ];
  for (final p in productos) {
    batch.insert('products', p, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  await batch.commit(noResult: true);
}
