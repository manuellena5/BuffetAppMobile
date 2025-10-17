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
      version: 1,
      onCreate: (db, v) async {
        // Activar FK y crear esquema base
        await db.execute('PRAGMA foreign_keys=ON');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS metodos_pago (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL)');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS Categoria_Producto (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL)');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS products ('
            'id INTEGER PRIMARY KEY, '
            'codigo_producto TEXT, '
            'nombre TEXT NOT NULL, '
            'precio_compra INTEGER, '
            'precio_venta INTEGER NOT NULL, '
            'stock_actual INTEGER DEFAULT 0, '
            'stock_minimo INTEGER DEFAULT 3, '
            'categoria_id INTEGER, '
            'visible INTEGER DEFAULT 1, '
            'color TEXT, '
            'imagen TEXT, '
            'FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id)'
            ')');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS caja_diaria ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'codigo_caja TEXT UNIQUE, disciplina TEXT, fecha TEXT, '
            'usuario_apertura TEXT, hora_apertura TEXT, apertura_dt TEXT, '
            'fondo_inicial REAL, estado TEXT, ingresos REAL DEFAULT 0, '
            'retiros REAL DEFAULT 0, diferencia REAL, total_tickets INTEGER, '
      'hora_cierre TEXT, cierre_dt TEXT, descripcion_evento TEXT, observaciones_apertura TEXT, obs_cierre TEXT'
            ')');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS ventas ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'uuid TEXT UNIQUE, '
            'fecha_hora TEXT NOT NULL, '
            'total_venta REAL NOT NULL, '
            "status TEXT DEFAULT 'No impreso', "
            'activo INTEGER DEFAULT 1, '
            'metodo_pago_id INTEGER, '
            'caja_id INTEGER, '
            'FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id), '
            'FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)'
            ')');

        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_ventas_fecha_hora ON ventas(fecha_hora)');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS venta_items ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'venta_id INTEGER NOT NULL, '
            'producto_id INTEGER NOT NULL, '
            'cantidad INTEGER NOT NULL, '
            'precio_unitario REAL NOT NULL, '
            'subtotal REAL NOT NULL, '
            'FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE, '
            'FOREIGN KEY (producto_id) REFERENCES products(id)'
            ')');

        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_items_venta_id ON venta_items(venta_id)');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS tickets ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'venta_id INTEGER, '
            'categoria_id INTEGER, '
            'producto_id INTEGER, '
            'fecha_hora TEXT NOT NULL, '
            "status TEXT DEFAULT 'No impreso', "
            'total_ticket REAL NOT NULL, '
            'identificador_ticket TEXT, '
            'FOREIGN KEY (venta_id) REFERENCES ventas(id), '
            'FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id), '
            'FOREIGN KEY (producto_id) REFERENCES products(id)'
            ')');

        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tickets_venta_id ON tickets(venta_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tickets_categoria_id ON tickets(categoria_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)');

        await db.execute(
            'CREATE TABLE IF NOT EXISTS caja_movimiento ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'caja_id INTEGER NOT NULL, '
            "tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')), "
            'monto REAL NOT NULL CHECK (monto > 0), '
            'observacion TEXT, '
            'creado_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, '
            'FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)'
            ')');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_mov_caja_id ON caja_movimiento(caja_id)');

        // Semillas iniciales en creación (única vez)
        await db.insert('metodos_pago',
            {'id': 1, 'descripcion': 'Efectivo'},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('metodos_pago',
            {'id': 2, 'descripcion': 'Transferencia'},
            conflictAlgorithm: ConflictAlgorithm.ignore);

        await db.insert('Categoria_Producto',
            {'id': 1, 'descripcion': 'Comida'},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('Categoria_Producto',
            {'id': 2, 'descripcion': 'Bebida'},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('Categoria_Producto',
            {'id': 3, 'descripcion': 'Otros'},
            conflictAlgorithm: ConflictAlgorithm.ignore);

        // Productos precargados (DONA/HIEL/PAPF)
        await db.insert(
          'products',
          {
            'codigo_producto': 'DONA',
            'nombre': 'Donacion',
            'precio_venta': 0,
            'stock_actual': 999,
            'stock_minimo': 3,
            'categoria_id': 3,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'HIEL',
            'nombre': 'Hielo',
            'precio_venta': 1000,
            'stock_actual': 999,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'PAPF',
            'nombre': 'Papas fritas',
            'precio_venta': 2000,
            'stock_actual': 999,
            'stock_minimo': 3,
            'categoria_id': 1,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        // Productos precargados adicionales (como se tenía antes)
        // Comida
        await db.insert(
          'products',
          {
            'codigo_producto': 'HAMB',
            'nombre': 'Hamburguesa',
            'precio_venta': 3000,
            'stock_actual': 50,
            'stock_minimo': 3,
            'categoria_id': 1,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'CHOR',
            'nombre': 'Choripán',
            'precio_venta': 3000,
            'stock_actual': 50,
            'stock_minimo': 3,
            'categoria_id': 1,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        // Bebidas
        await db.insert(
          'products',
          {
            'codigo_producto': 'VINO',
            'nombre': 'Vino blanco',
            'precio_venta': 2000,
            'stock_actual': 999,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'GATO',
            'nombre': 'Gatorade',
            'precio_venta': 2500,
            'stock_actual': 50,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'AGMT',
            'nombre': 'Agua mate',
            'precio_venta': 1000,
            'stock_actual': 50,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'FERN',
            'nombre': 'Fernet',
            'precio_venta': 5000,
            'stock_actual': 999,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'CERV',
            'nombre': 'Cerveza',
            'precio_venta': 2000,
            'stock_actual': 999,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'AGUA',
            'nombre': 'Agua',
            'precio_venta': 1000,
            'stock_actual': 50,
            'stock_minimo': 3,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'JARR',
            'nombre': 'Jarra gaseosa',
            'precio_venta': 2000,
            'stock_actual': 999,
            'stock_minimo': 5,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.insert(
          'products',
          {
            'codigo_producto': 'VASO',
            'nombre': 'Vaso gaseosa',
            'precio_venta': 1500,
            'stock_actual': 999,
            'stock_minimo': 5,
            'categoria_id': 2,
            'visible': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        // Catálogos de referencia (puntos de venta, disciplinas)
        await _ensureCatalogos(db);
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');

        // Migración: agregar columna descripcion_evento si falta
        final infoCaja = await db.rawQuery("PRAGMA table_info(caja_diaria)");
        final hasDescEvento = infoCaja.any((c) => (c['name'] as String?) == 'descripcion_evento');
        if (!hasDescEvento) {
          await db.execute('ALTER TABLE caja_diaria ADD COLUMN descripcion_evento TEXT');
        }

        // Asegurar catálogos también en onOpen para instalaciones previas
        await _ensureCatalogos(db);
      },
    );

    return _db!;
  }
}

Future<void> _ensureCatalogos(Database db) async {
  // punto_venta
  await db.execute(
      'CREATE TABLE IF NOT EXISTS punto_venta (codigo TEXT PRIMARY KEY, nombre TEXT NOT NULL)');
  final pvCount = await db.rawQuery('SELECT COUNT(1) as c FROM punto_venta');
  final pvc = (pvCount.first['c'] as int?) ?? (pvCount.first['c'] as num?)?.toInt() ?? 0;
  if (pvc == 0) {
    await db.insert('punto_venta', {'codigo': 'Caj01', 'nombre': 'Caja1'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('punto_venta', {'codigo': 'Caj02', 'nombre': 'Caja2'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('punto_venta', {'codigo': 'Caj03', 'nombre': 'Caja3'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // disciplinas
  await db.execute(
      'CREATE TABLE IF NOT EXISTS disciplinas (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT UNIQUE NOT NULL)');
  final disCount = await db.rawQuery('SELECT COUNT(1) as c FROM disciplinas');
  final disc = (disCount.first['c'] as int?) ?? (disCount.first['c'] as num?)?.toInt() ?? 0;
  if (disc == 0) {
    await db.insert('disciplinas', {'nombre': 'Futbol Infantil'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('disciplinas', {'nombre': 'Futbol Mayor'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('disciplinas', {'nombre': 'Evento'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('disciplinas', {'nombre': 'Otros'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
