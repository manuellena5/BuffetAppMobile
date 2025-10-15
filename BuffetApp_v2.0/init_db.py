# archivo: init_db.py
import sqlite3
from db_utils import get_connection
from app_config import get_device_id, get_device_name

def init_db():
    
    conn = get_connection()
    c = conn.cursor()

    # Métodos de pago
    c.execute('''
    CREATE TABLE IF NOT EXISTS metodos_pago (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        descripcion TEXT NOT NULL
    )
    ''')
    # Insertar métodos de pago por defecto si la tabla está vacía
    c.execute("SELECT COUNT(*) FROM metodos_pago")
    if c.fetchone()[0] == 0:
        c.execute("INSERT INTO metodos_pago (descripcion) VALUES ('Efectivo')")
        c.execute("INSERT INTO metodos_pago (descripcion) VALUES ('Transferencia')")


    # Categorías de productos
    c.execute('''
    CREATE TABLE IF NOT EXISTS Categoria_Producto (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        descripcion TEXT NOT NULL
    )
    ''')

    # Productos con referencia a categoría
    c.execute('''
    CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_producto TEXT,
        nombre TEXT NOT NULL,
        precio_compra INTEGER NOT NULL,
        precio_venta INTEGER NOT NULL,
        stock_actual INTEGER DEFAULT 0,
        stock_minimo INTEGER DEFAULT 3,
        categoria_id INTEGER,
        visible INTEGER DEFAULT 1,
        color TEXT,
        FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id)
    )
    ''')
    # Intentar agregar columnas opcionales si no existen
    for col in ("color", "codigo_producto"):
        try:
            c.execute(f"ALTER TABLE products ADD COLUMN {col} TEXT")
        except Exception:
            pass

    # Ventas (una venta puede tener varios tickets)
    c.execute('''
    CREATE TABLE IF NOT EXISTS ventas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha_hora TEXT NOT NULL,
        total_venta REAL NOT NULL,
        status TEXT DEFAULT 'No impreso',
        activo INTEGER DEFAULT 1,
        metodo_pago_id INTEGER,
        FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id)
    )
    ''')
    # Índice para búsquedas por fecha de venta
    try:
        c.execute("CREATE INDEX idx_ventas_fecha_hora ON ventas(fecha_hora)")
    except Exception:
        pass

    # Tickets por categoría en cada venta
    c.execute('''
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
    )
    ''')
    # Índices para mejorar búsquedas y uniones en tickets
    try:
        c.execute("CREATE INDEX idx_tickets_venta_id ON tickets(venta_id)")
    except Exception:
        pass
    try:
        c.execute("CREATE INDEX idx_tickets_categoria_id ON tickets(categoria_id)")
    except Exception:
        pass
    try:
        c.execute("CREATE INDEX idx_tickets_status ON tickets(status)")
    except Exception:
        pass

    # Ítems de cada ticket
    c.execute('''
    CREATE TABLE IF NOT EXISTS venta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id INTEGER,
        producto_id INTEGER,
        cantidad INTEGER,
        precio_unitario REAL,
        subtotal REAL,
        FOREIGN KEY (ticket_id) REFERENCES tickets(id),
        FOREIGN KEY (producto_id) REFERENCES products(id)
    )
    ''')
    # Índice para búsquedas rápidas de ítems por ticket
    try:
        c.execute("CREATE INDEX idx_venta_items_ticket_id ON venta_items(ticket_id)")
    except Exception:
        pass

    # Registro de stock
    c.execute('''
    CREATE TABLE IF NOT EXISTS stock_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        producto_id INTEGER,
        cantidad INTEGER,
        fecha_hora TEXT NOT NULL,
        motivo TEXT,
        FOREIGN KEY(producto_id) REFERENCES products(id)
    )
    ''')

    # Tabla de logueo de errores
    c.execute('''
    CREATE TABLE IF NOT EXISTS error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha_hora TEXT,
        modulo TEXT,
        mensaje TEXT
    )
    ''')

    # Caja diaria (apertura/cierre de jornada)
    # --- Caja diaria ---
    c.execute('''
    CREATE TABLE IF NOT EXISTS caja_diaria (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo_caja TEXT,
        disciplina TEXT,
        fecha TEXT NOT NULL,
        usuario_apertura TEXT,
        hora_apertura TEXT NOT NULL,
        fondo_inicial REAL NOT NULL,
        observaciones_apertura TEXT,
        estado TEXT NOT NULL CHECK (estado IN ('abierta','cerrada')),
        hora_cierre TEXT,
        usuario_cierre TEXT,
        apertura_dt TEXT,
        cierre_dt TEXT,
        total_ventas REAL,
        total_efectivo_teorico REAL,
        conteo_efectivo_final REAL,
        transferencias_final REAL DEFAULT 0,
        ingresos REAL DEFAULT 0,
        retiros REAL DEFAULT 0,
        diferencia REAL,
        total_tickets INTEGER,
        obs_cierre TEXT
    )
    ''')


    # Movimientos manuales (ingreso / retiro) por caja
    c.execute('''
    CREATE TABLE IF NOT EXISTS caja_movimiento (
      id          INTEGER PRIMARY KEY,
      caja_id     INTEGER NOT NULL,
      tipo        TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')),
      monto       NUMERIC NOT NULL CHECK (monto > 0),
      observacion TEXT,
      creado_ts   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
    ''')

    # Migration: prior versions had a UNIQUE constraint on (caja_id, tipo)
    # which prevented multiple ingresos/retiros per caja. If an old index
    # exists, migrate data to a new table without that UNIQUE constraint.
    try:
        cur = conn.cursor()
        # detect an index that enforces uniqueness on caja_movimiento(caja_id, tipo)
        cur.execute("PRAGMA index_list('caja_movimiento')")
        indexes = cur.fetchall()
        unique_index = None
        for idx in indexes:
            # idx: (seq, name, unique, origin, partial)
            if idx[2] == 1:
                # inspect index info
                name = idx[1]
                cur.execute(f"PRAGMA index_info('{name}')")
                cols = [r[2] for r in cur.fetchall()]
                if cols == ['caja_id', 'tipo'] or cols == ['tipo', 'caja_id']:
                    unique_index = name
                    break
        if unique_index:
            # perform migration: create new table, copy data, drop old, rename new
            cur.execute('''
                CREATE TABLE IF NOT EXISTS caja_movimiento_new (
                    id INTEGER PRIMARY KEY,
                    caja_id INTEGER NOT NULL,
                    tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','RETIRO')),
                    monto NUMERIC NOT NULL CHECK (monto > 0),
                    observacion TEXT,
                    creado_ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            cur.execute("INSERT INTO caja_movimiento_new (id, caja_id, tipo, monto, observacion, creado_ts) SELECT id, caja_id, tipo, monto, observacion, creado_ts FROM caja_movimiento")
            cur.execute("DROP TABLE caja_movimiento")
            cur.execute("ALTER TABLE caja_movimiento_new RENAME TO caja_movimiento")
            conn.commit()
    except Exception:
        # if migration fails, continue silently (we prefer not to break install)
        pass


    # --- Triggers to keep caja_diaria.ingresos and retiros consistent ---
    try:
        # AFTER INSERT: add monto to the corresponding field
        c.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_caja_mov_insert
        AFTER INSERT ON caja_movimiento
        BEGIN
            UPDATE caja_diaria
            SET ingresos = COALESCE(ingresos,0) + CASE WHEN NEW.tipo='INGRESO' THEN NEW.monto ELSE 0 END,
                retiros  = COALESCE(retiros,0)  + CASE WHEN NEW.tipo='RETIRO'  THEN NEW.monto ELSE 0 END
            WHERE id = NEW.caja_id;
        END;
        ''')

        # AFTER DELETE: subtract monto from the corresponding field
        c.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_caja_mov_delete
        AFTER DELETE ON caja_movimiento
        BEGIN
            UPDATE caja_diaria
            SET ingresos = COALESCE(ingresos,0) - CASE WHEN OLD.tipo='INGRESO' THEN OLD.monto ELSE 0 END,
                retiros  = COALESCE(retiros,0)  - CASE WHEN OLD.tipo='RETIRO'  THEN OLD.monto ELSE 0 END
            WHERE id = OLD.caja_id;
        END;
        ''')

        # AFTER UPDATE: remove OLD values and add NEW values (covers tipo/caja_id/monto changes)
        c.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_caja_mov_update
        AFTER UPDATE ON caja_movimiento
        BEGIN
            -- subtract OLD
            UPDATE caja_diaria
            SET ingresos = COALESCE(ingresos,0) - CASE WHEN OLD.tipo='INGRESO' THEN OLD.monto ELSE 0 END,
                retiros  = COALESCE(retiros,0)  - CASE WHEN OLD.tipo='RETIRO'  THEN OLD.monto ELSE 0 END
            WHERE id = OLD.caja_id;
            -- add NEW
            UPDATE caja_diaria
            SET ingresos = COALESCE(ingresos,0) + CASE WHEN NEW.tipo='INGRESO' THEN NEW.monto ELSE 0 END,
                retiros  = COALESCE(retiros,0)  + CASE WHEN NEW.tipo='RETIRO'  THEN NEW.monto ELSE 0 END
            WHERE id = NEW.caja_id;
        END;
        ''')

        # Recompute totals once to normalize any legacy data (idempotent)
        c.execute('''
        UPDATE caja_diaria
        SET ingresos = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id = caja_diaria.id AND tipo='INGRESO'),
            retiros  = (SELECT COALESCE(SUM(monto),0) FROM caja_movimiento WHERE caja_id = caja_diaria.id AND tipo='RETIRO')
        ''')
        conn.commit()
    except Exception:
        # Do not fail install if triggers cannot be created
        pass


    # --- Columna caja_id en ventas ---
    try:
        c.execute("ALTER TABLE ventas ADD COLUMN caja_id INTEGER REFERENCES caja_diaria(id)")
    except Exception:
        pass
    # Índices para acelerar filtros por caja en ventas
    try:
        c.execute("CREATE INDEX idx_ventas_caja_id ON ventas(caja_id)")
    except Exception:
        pass

    # Asegura un único registro con estado 'abierta'
    try:
        c.execute("CREATE UNIQUE INDEX idx_caja_diaria_abierta ON caja_diaria(estado) WHERE estado='abierta'")
    except Exception:
        pass

    # Columnas de fecha/hora completa para apertura y cierre
    for columna in ("apertura_dt", "cierre_dt"):
        try:
            c.execute(f"ALTER TABLE caja_diaria ADD COLUMN {columna} TEXT")
        except Exception:
            pass


    # Usuarios del sistema
    c.execute('''
    CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        rol TEXT NOT NULL
    )
    ''')

    # Tabla de disciplinas
    c.execute('''
    CREATE TABLE IF NOT EXISTS disciplinas (
        codigo TEXT PRIMARY KEY,
        descripcion TEXT NOT NULL
    )
    ''')
    # Insertar disciplinas por defecto si la tabla está vacía
    c.execute("SELECT COUNT(*) FROM disciplinas")
    if c.fetchone()[0] == 0:
        disciplinas = [
            ("BAR", "BAR"),
            ("FUTI", "Futbol Infantil"),
            ("FUTM", "Futbol Mayor"),
            ("PAT", "Patin"),
            ("VOL", "Voley"),
        ]
        c.executemany(
            "INSERT INTO disciplinas (codigo, descripcion) VALUES (?, ?)",
            disciplinas,
        )
   

    # Insertar productos si no hay nada
    c.execute("SELECT COUNT(*) FROM products")
    if c.fetchone()[0] == 0:
        # Insertar categorías
        categorias = [
            ('Comida',),
            ('Bebida',),
            ('Otros',)
        ]
        c.executemany("INSERT INTO Categoria_Producto (descripcion) VALUES (?)", categorias)
        # Obtener IDs de categorías
        c.execute("SELECT id FROM Categoria_Producto WHERE descripcion='Comida'")
        id_comida = c.fetchone()[0]
        c.execute("SELECT id FROM Categoria_Producto WHERE descripcion='Bebida'")
        id_bebida = c.fetchone()[0]
        c.execute("SELECT id FROM Categoria_Producto WHERE descripcion='Otros'")
        id_otros = c.fetchone()[0]

        productos = [
            # codigo, nombre, precio_compra, precio_venta, stock_actual, stock_minimo, categoria_id
            ('CHOR', 'Choripán', 1500, 3000, 50, 3, id_comida),
            ('HAMB', 'Hamburguesa', 1600, 3000, 50, 3, id_comida),
            ('VASO', 'Vaso Gaseosa', 300, 1500, 999, 5, id_bebida),
            ('JARR', 'Jarra Gaseosa', 800, 2000, 999, 5, id_bebida),
            ('AGUA', 'Agua', 600, 1000, 50, 3, id_bebida),
            ('CERV', 'Cerveza', 1000, 2000, 999, 3, id_bebida),
            ('VINO', 'Vino', 1000, 2000, 999, 3, id_bebida),
            ('FERN', 'Fernet', 3000, 5000, 999, 3, id_bebida),
            ('AGMT', 'Agua Mate', 200, 1000, 50, 3, id_bebida),
            ('GATO', 'Gatorade', 1000, 2500, 50, 3, id_bebida)
        ]
        c.executemany("INSERT INTO products (codigo_producto, nombre, precio_compra, precio_venta, stock_actual, stock_minimo, categoria_id) VALUES (?, ?, ?, ?, ?, ?, ?)", productos)
        print("Productos y categorías cargados")

    # Insertar usuarios por defecto si no existen
    c.execute("SELECT COUNT(*) FROM usuarios")
    if c.fetchone()[0] == 0:
        c.execute("INSERT INTO usuarios (usuario, password, rol) VALUES (?, ?, ?)", ("admin", "admin123", "administrador"))
        c.execute("INSERT INTO usuarios (usuario, password, rol) VALUES (?, ?, ?)", ("cajero", "cajero123", "cajero"))

    conn.commit()
    
    # --- POS y Settings para identificar dispositivo/Punto de Venta ---
    try:
        # Tabla settings KV simple (si no existiera)
        c.execute('''
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        ''')
        # Tabla pos (puntos de venta)
        c.execute('''
        CREATE TABLE IF NOT EXISTS pos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pos_uuid TEXT NOT NULL UNIQUE,
            nombre   TEXT NOT NULL,
            device_id TEXT,
            hostname TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        )
        ''')
        # Tabla caja_diaria ya existe; agregamos columnas pos_uuid y caja_uuid si faltan
        c.execute("PRAGMA table_info(caja_diaria)")
        cols = [r[1] for r in c.fetchall()]
        if 'pos_uuid' not in cols:
            try:
                c.execute("ALTER TABLE caja_diaria ADD COLUMN pos_uuid TEXT")
            except Exception:
                pass
        if 'caja_uuid' not in cols:
            try:
                c.execute("ALTER TABLE caja_diaria ADD COLUMN caja_uuid TEXT")
            except Exception:
                pass
        # Índices útiles
        try:
            c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_caja_uuid ON caja_diaria(caja_uuid)")
        except Exception:
            pass
        try:
            c.execute("CREATE INDEX IF NOT EXISTS idx_caja_pos_uuid ON caja_diaria(pos_uuid)")
        except Exception:
            pass
        # Agregar columnas para relacionar plantilla de caja y su prefijo
        c.execute("PRAGMA table_info(caja_diaria)")
        cols = [r[1] for r in c.fetchall()]
        if 'pos_caja_id' not in cols:
            try:
                c.execute("ALTER TABLE caja_diaria ADD COLUMN pos_caja_id INTEGER")
            except Exception:
                pass
        if 'caja_prefijo' not in cols:
            try:
                c.execute("ALTER TABLE caja_diaria ADD COLUMN caja_prefijo TEXT")
            except Exception:
                pass

        # Crear/asegurar POS local basado en config (device_id/device_name)
        device_id = get_device_id()
        device_name = get_device_name()
        # Buscar pos por device_id; si no existe, crearlo
        c.execute("SELECT id, pos_uuid FROM pos WHERE device_id=?", (device_id,))
        row = c.fetchone()
        if not row:
            import uuid, platform
            pos_uuid = str(uuid.uuid4())
            hostname = platform.node() or "Equipo"
            c.execute(
                "INSERT INTO pos (pos_uuid, nombre, device_id, hostname) VALUES (?, ?, ?, ?)",
                (pos_uuid, device_name or hostname, device_id, hostname)
            )
            # Guardar referencia en settings
            try:
                c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('device_pos_uuid', ?)", (pos_uuid,))
            except Exception:
                pass
        else:
            # Alinear nombre si cambió desde config
            try:
                c.execute("UPDATE pos SET nombre=? WHERE device_id=?", (device_name, device_id))
            except Exception:
                pass
    except Exception:
        # No romper la inicialización ante errores de POS/Settings
        pass

    # --- Plantillas de Cajas (pos_cajas) ---
    try:
        c.execute('''
        CREATE TABLE IF NOT EXISTS pos_cajas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            descripcion TEXT NOT NULL,
            prefijo TEXT NOT NULL,
            predeterminada INTEGER DEFAULT 0,
            activo INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(prefijo)
        )
        ''')
        # Precarga si está vacío
        c.execute('SELECT COUNT(*) FROM pos_cajas')
        if (c.fetchone() or [0])[0] == 0:
            c.execute("INSERT INTO pos_cajas (descripcion, prefijo, predeterminada) VALUES ('Caja1', 'Caj01', 1)")
            c.execute("INSERT INTO pos_cajas (descripcion, prefijo, predeterminada) VALUES ('Caja2', 'Caj02', 0)")
        else:
            # Asegurar que exista exactamente una predeterminada
            c.execute('SELECT COUNT(*) FROM pos_cajas WHERE predeterminada=1')
            cnt = (c.fetchone() or [0])[0]
            if cnt == 0:
                # Marcar la primera como predeterminada
                c.execute('UPDATE pos_cajas SET predeterminada=1 WHERE id=(SELECT id FROM pos_cajas ORDER BY id LIMIT 1)')
            elif cnt > 1:
                # Dejar solo la más antigua como predeterminada
                c.execute('''
                    UPDATE pos_cajas SET predeterminada=CASE WHEN id=(SELECT id FROM pos_cajas ORDER BY id LIMIT 1) THEN 1 ELSE 0 END
                ''')
        conn.commit()
    except Exception:
        pass
    conn.close()
    print("Base de datos inicializada.")

# Función para registrar errores
def log_error(fecha_hora, modulo, mensaje):

        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute("INSERT INTO error_log (fecha_hora, modulo, mensaje) VALUES (?, ?, ?)", (fecha_hora, modulo, mensaje))
            conn.commit()
        finally:
            try:
                cursor.close()
                conn.close()
            except Exception as e:
                pass

