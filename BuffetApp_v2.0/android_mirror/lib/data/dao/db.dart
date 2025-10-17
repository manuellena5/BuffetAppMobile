import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Database? _db;
  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'barcancha.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, v) async {
      // En Android no podemos usar .read; incluimos el SQL expandido o migraciones aquí.
      // Para MVP, crear tablas mínimas (productos, metodos_pago, categorias, caja_diaria, ventas, venta_items, caja_movimiento)
      await db.execute("PRAGMA foreign_keys=ON");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS metodos_pago (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL)");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS Categoria_Producto (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL)");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, codigo_producto TEXT, nombre TEXT NOT NULL, precio_compra INTEGER, precio_venta INTEGER NOT NULL, stock_actual INTEGER DEFAULT 0, stock_minimo INTEGER DEFAULT 3, categoria_id INTEGER, visible INTEGER DEFAULT 1, color TEXT, FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id))");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS caja_diaria (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo_caja TEXT UNIQUE, disciplina TEXT, fecha TEXT, usuario_apertura TEXT, hora_apertura TEXT, apertura_dt TEXT, fondo_inicial REAL, estado TEXT, ingresos REAL DEFAULT 0, retiros REAL DEFAULT 0, diferencia REAL, total_tickets INTEGER, hora_cierre TEXT, cierre_dt TEXT, observaciones_apertura TEXT, obs_cierre TEXT)");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS ventas (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT UNIQUE, fecha_hora TEXT NOT NULL, total_venta REAL NOT NULL, status TEXT DEFAULT 'No impreso', activo INTEGER DEFAULT 1, metodo_pago_id INTEGER, caja_id INTEGER, FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id), FOREIGN KEY (caja_id) REFERENCES caja_diaria(id))");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_ventas_fecha_hora ON ventas(fecha_hora)");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS venta_items (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER NOT NULL, producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL, precio_unitario REAL NOT NULL, subtotal REAL NOT NULL, FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE, FOREIGN KEY (producto_id) REFERENCES products(id))");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_items_venta_id ON venta_items(venta_id)");
      // Tickets por ítem
      await db.execute(
          "CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER, categoria_id INTEGER, producto_id INTEGER, fecha_hora TEXT NOT NULL, status TEXT DEFAULT 'No impreso', total_ticket REAL NOT NULL, identificador_ticket TEXT, FOREIGN KEY (venta_id) REFERENCES ventas(id), FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id), FOREIGN KEY (producto_id) REFERENCES products(id))");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_tickets_venta_id ON tickets(venta_id)");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_tickets_categoria_id ON tickets(categoria_id)");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS caja_movimiento (id INTEGER PRIMARY KEY AUTOINCREMENT, caja_id INTEGER NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')), monto REAL NOT NULL CHECK (monto > 0), observacion TEXT, creado_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (caja_id) REFERENCES caja_diaria(id))");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_mov_caja_id ON caja_movimiento(caja_id)");

      // Semillas iniciales (idempotentes)
      await db.insert('Categoria_Producto', {'id': 1, 'descripcion': 'Comida'}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('Categoria_Producto', {'id': 2, 'descripcion': 'Bebida'}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('Categoria_Producto', {'id': 3, 'descripcion': 'Otros'}, conflictAlgorithm: ConflictAlgorithm.ignore);

      // Productos precargados si no existen por nombre
      await db.rawInsert(
          "INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible)\n"
          "SELECT 'DONA', 'Donacion', 0, 999, 3, 3, 1\n"
          "WHERE NOT EXISTS (SELECT 1 FROM products WHERE UPPER(nombre)=UPPER('Donacion'))");
      await db.rawInsert(
          "INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible)\n"
          "SELECT 'HIEL', 'Hielo', 1000, 999, 3, 2, 1\n"
          "WHERE NOT EXISTS (SELECT 1 FROM products WHERE UPPER(nombre)=UPPER('Hielo'))");
      await db.rawInsert(
          "INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible)\n"
          "SELECT 'PAPF', 'Papas fritas', 2000, 999, 3, 1, 1\n"
          "WHERE NOT EXISTS (SELECT 1 FROM products WHERE UPPER(nombre)=UPPER('Papas fritas'))");
    }, onOpen: (db) async {
      // Asegurar llaves foráneas y tablas críticas si la DB ya existía sin ellas
      await db.execute("PRAGMA foreign_keys=ON");
      await db.execute(
          "CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER, categoria_id INTEGER, producto_id INTEGER, fecha_hora TEXT NOT NULL, status TEXT DEFAULT 'No impreso', total_ticket REAL NOT NULL, identificador_ticket TEXT, FOREIGN KEY (venta_id) REFERENCES ventas(id), FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id), FOREIGN KEY (producto_id) REFERENCES products(id))");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_tickets_venta_id ON tickets(venta_id)");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_tickets_categoria_id ON tickets(categoria_id)");
      await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)");
            // Migración ligera: agregar columna 'imagen' a products si no existe
            final cols = await db.rawQuery("PRAGMA table_info(products)");
            final hasImagen = cols.any((c) => (c['name'] as String?) == 'imagen');
            if (!hasImagen) {
                await db.execute("ALTER TABLE products ADD COLUMN imagen TEXT");
            }

                    // Semillas también en onOpen (idempotentes), por si la DB ya existía
                    await db.insert('Categoria_Producto', {'id': 1, 'descripcion': 'Comida'}, conflictAlgorithm: ConflictAlgorithm.ignore);
                    await db.insert('Categoria_Producto', {'id': 2, 'descripcion': 'Bebida'}, conflictAlgorithm: ConflictAlgorithm.ignore);
                    await db.insert('Categoria_Producto', {'id': 3, 'descripcion': 'Otros'}, conflictAlgorithm: ConflictAlgorithm.ignore);

            await db.rawInsert(
                "INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible)\n"
                "SELECT 'DONA', 'Donacion', 0, 999, 3, 3, 1\n"
                "WHERE NOT EXISTS (SELECT 1 FROM products WHERE UPPER(nombre)=UPPER('Donacion'))");
            await db.rawInsert(
                "INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible)\n"
                "SELECT 'HIEL', 'Hielo', 1000, 999, 3, 2, 1\n"
                "WHERE NOT EXISTS (SELECT 1 FROM products WHERE UPPER(nombre)=UPPER('Hielo'))");
            await db.rawInsert(
                "INSERT INTO products (codigo_producto, nombre, precio_venta, stock_actual, stock_minimo, categoria_id, visible)\n"
                "SELECT 'PAPF', 'Papas fritas', 2000, 999, 3, 1, 1\n"
                "WHERE NOT EXISTS (SELECT 1 FROM products WHERE UPPER(nombre)=UPPER('Papas fritas'))");

            // Backfill de códigos si existen sin código
            await db.rawUpdate(
            "UPDATE products SET codigo_producto='DONA' WHERE UPPER(nombre)=UPPER('Donacion') AND (codigo_producto IS NULL OR TRIM(codigo_producto)='')");
            await db.rawUpdate(
            "UPDATE products SET codigo_producto='HIEL' WHERE UPPER(nombre)=UPPER('Hielo') AND (codigo_producto IS NULL OR TRIM(codigo_producto)='')");
            await db.rawUpdate(
            "UPDATE products SET codigo_producto='PAPF' WHERE UPPER(nombre)=UPPER('Papas fritas') AND (codigo_producto IS NULL OR TRIM(codigo_producto)='')");
    });
    return _db!;
  }
}
