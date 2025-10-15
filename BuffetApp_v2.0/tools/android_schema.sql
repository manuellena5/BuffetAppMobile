-- Android SQLite schema (alineado a init_db.py)
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS metodos_pago (
  id INTEGER PRIMARY KEY,
  descripcion TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS Categoria_Producto (
  id INTEGER PRIMARY KEY,
  descripcion TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY,
  codigo_producto TEXT,
  nombre TEXT NOT NULL,
  precio_compra INTEGER,
  precio_venta INTEGER NOT NULL,
  stock_actual INTEGER DEFAULT 0,
  stock_minimo INTEGER DEFAULT 3,
  categoria_id INTEGER,
  visible INTEGER DEFAULT 1,
  color TEXT,
  FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id)
);

CREATE TABLE IF NOT EXISTS caja_diaria (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  codigo_caja TEXT UNIQUE,
  disciplina TEXT,
  fecha TEXT,
  usuario_apertura TEXT,
  hora_apertura TEXT,
  apertura_dt TEXT,
  fondo_inicial REAL,
  estado TEXT,
  ingresos REAL DEFAULT 0,
  retiros REAL DEFAULT 0,
  diferencia REAL,
  total_tickets INTEGER,
  hora_cierre TEXT,
  cierre_dt TEXT,
  observaciones_apertura TEXT,
  obs_cierre TEXT
);

CREATE TABLE IF NOT EXISTS ventas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT UNIQUE,
  fecha_hora TEXT NOT NULL,
  total_venta REAL NOT NULL,
  status TEXT DEFAULT 'No impreso',
  activo INTEGER DEFAULT 1,
  metodo_pago_id INTEGER,
  caja_id INTEGER,
  FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id),
  FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)
);
CREATE INDEX IF NOT EXISTS idx_ventas_fecha_hora ON ventas(fecha_hora);

CREATE TABLE IF NOT EXISTS venta_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  venta_id INTEGER NOT NULL,
  producto_id INTEGER NOT NULL,
  cantidad INTEGER NOT NULL,
  precio_unitario REAL NOT NULL,
  subtotal REAL NOT NULL,
  FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
  FOREIGN KEY (producto_id) REFERENCES products(id)
);
CREATE INDEX IF NOT EXISTS idx_items_venta_id ON venta_items(venta_id);

CREATE TABLE IF NOT EXISTS tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  venta_id INTEGER,
  categoria_id INTEGER,
  producto_id INTEGER,
  fecha_hora TEXT NOT NULL,
  status TEXT DEFAULT 'No impreso',
  total_ticket REAL NOT NULL,
  identificador_ticket TEXT,
  FOREIGN KEY (venta_id) REFERENCES ventas(id),
  FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id),
  FOREIGN KEY (producto_id) REFERENCES products(id)
);
CREATE INDEX IF NOT EXISTS idx_tickets_venta_id ON tickets(venta_id);
CREATE INDEX IF NOT EXISTS idx_tickets_categoria_id ON tickets(categoria_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);

CREATE TABLE IF NOT EXISTS caja_movimiento (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  caja_id INTEGER NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')),
  monto REAL NOT NULL CHECK (monto > 0),
  observacion TEXT,
  creado_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (caja_id) REFERENCES caja_diaria(id)
);
CREATE INDEX IF NOT EXISTS idx_mov_caja_id ON caja_movimiento(caja_id);

-- Triggers para mantener ingresos/retiros
CREATE TRIGGER IF NOT EXISTS trg_caja_mov_i AFTER INSERT ON caja_movimiento
BEGIN
  UPDATE caja_diaria
     SET ingresos = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id=NEW.caja_id AND tipo='INGRESO'),
         retiros  = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id=NEW.caja_id AND tipo='RETIRO')
   WHERE id = NEW.caja_id;
END;
CREATE TRIGGER IF NOT EXISTS trg_caja_mov_u AFTER UPDATE ON caja_movimiento
BEGIN
  UPDATE caja_diaria
     SET ingresos = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id=NEW.caja_id AND tipo='INGRESO'),
         retiros  = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id=NEW.caja_id AND tipo='RETIRO')
   WHERE id = NEW.caja_id;
END;
CREATE TRIGGER IF NOT EXISTS trg_caja_mov_d AFTER DELETE ON caja_movimiento
BEGIN
  UPDATE caja_diaria
     SET ingresos = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id=OLD.caja_id AND tipo='INGRESO'),
         retiros  = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id=OLD.caja_id AND tipo='RETIRO')
   WHERE id = OLD.caja_id;
END;
