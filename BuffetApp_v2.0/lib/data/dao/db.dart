import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static Database? _db;
  static bool _desktopFactoryInitialized = false;
  static DatabaseFactory? _explicitFactory;

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
    // En Windows/Linux/macOS usamos sqflite_common_ffi.
    // En Android/iOS seguimos usando sqflite nativo.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      // Evitamos cambiar la factory global para no disparar warnings de sqflite
      // y para no afectar a librerías de terceros que usen sqflite.
      _explicitFactory = databaseFactoryFfi;
    }
    _desktopFactoryInitialized = true;
  }

  static Future<String> _dbFilePath() async {
    final isTest = Platform.environment['FLUTTER_TEST'] == 'true';

    // En tests respetamos path_provider (mockeable) para aislar la DB.
    if (isTest) {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'barcancha.db');
    }

    // Windows: almacenar en AppData\Local (LOCALAPPDATA) como pidió el usuario.
    // Esto facilita instalación multi-usuario y evita ensuciar Documents.
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        final baseDir = Directory(p.join(localAppData, 'Buffet_App'));
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
        return p.join(baseDir.path, 'barcancha.db');
      }
      // Fallback si por algún motivo no existe la env var.
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
        version: 11,
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
              'conteo_transferencias_final REAL, '
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
          batch.execute(
              'CREATE INDEX idx_ventas_fecha_hora ON ventas(fecha_hora)');
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
          batch.execute(
              'CREATE INDEX idx_items_venta_id ON venta_items(venta_id)');

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
          batch.execute(
              'CREATE INDEX idx_tickets_venta_id ON tickets(venta_id)');
          batch.execute(
              'CREATE INDEX idx_tickets_categoria_id ON tickets(categoria_id)');
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
          batch.execute(
              'CREATE INDEX idx_mov_caja_id ON caja_movimiento(caja_id)');
          batch.execute(
              'CREATE INDEX idx_mov_caja_tipo ON caja_movimiento(caja_id, tipo)');

          // Movimientos financieros externos al buffet (vNext)
          // FASE 13.1: Actualizado con campos de compromisos
          batch.execute('CREATE TABLE evento_movimiento ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'evento_id TEXT, '
              'disciplina_id INTEGER NOT NULL, '
              "tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), "
              'categoria TEXT, '
              'monto REAL NOT NULL CHECK (monto > 0), '
              'medio_pago_id INTEGER NOT NULL, '
              'observacion TEXT, '
              'dispositivo_id TEXT, '
              'archivo_local_path TEXT, '
              'archivo_remote_url TEXT, '
              'archivo_nombre TEXT, '
              'archivo_tipo TEXT, '
              'archivo_size INTEGER, '
              'eliminado INTEGER NOT NULL DEFAULT 0, '
              'compromiso_id INTEGER, '
              "estado TEXT NOT NULL DEFAULT 'CONFIRMADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO')), "
              "sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), "
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              'updated_ts INTEGER, '
              'FOREIGN KEY (medio_pago_id) REFERENCES metodos_pago(id), '
              'FOREIGN KEY (compromiso_id) REFERENCES compromisos(id)'
              ')');
          batch.execute(
              'CREATE INDEX idx_evento_mov_disc_created ON evento_movimiento(disciplina_id, created_ts)');
          batch.execute(
              'CREATE INDEX idx_evento_mov_evento_id ON evento_movimiento(evento_id)');
          batch.execute(
              'CREATE INDEX idx_evento_mov_mp_id ON evento_movimiento(medio_pago_id)');
          batch.execute(
              'CREATE INDEX idx_evento_mov_compromiso ON evento_movimiento(compromiso_id, estado)');
          batch.execute(
              'CREATE INDEX idx_evento_mov_estado ON evento_movimiento(estado, created_ts)');

          // Catálogo: Punto de venta / Disciplinas
          batch.execute('CREATE TABLE punto_venta ('
              'codigo TEXT PRIMARY KEY, '
              'nombre TEXT NOT NULL, '
              'alias_caja TEXT, '
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
              ')');
          batch.execute('CREATE TABLE disciplinas ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'nombre TEXT UNIQUE NOT NULL, '
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
              ')');
          
          // Nueva tabla: Unidades de Gestión (reemplaza conceptualmente a disciplinas)
          batch.execute('CREATE TABLE unidades_gestion ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'nombre TEXT UNIQUE NOT NULL, '
              "tipo TEXT NOT NULL CHECK (tipo IN ('DISCIPLINA','COMISION','EVENTO')), "
              'disciplina_ref TEXT, '
              'activo INTEGER NOT NULL DEFAULT 1, '
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
              ')');
          batch.execute('CREATE INDEX idx_unidades_gestion_tipo ON unidades_gestion(tipo, activo)');

          // FASE 13.1: Tabla de frecuencias (catálogo estático para compromisos)
          batch.execute('CREATE TABLE frecuencias ('
              'codigo TEXT PRIMARY KEY, '
              'descripcion TEXT NOT NULL, '
              'dias INTEGER'
              ')');

          // FASE 18: Tabla de acuerdos (reglas/contratos que generan compromisos)
          batch.execute('CREATE TABLE acuerdos ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'unidad_gestion_id INTEGER NOT NULL, '
              'entidad_plantel_id INTEGER, '
              'nombre TEXT NOT NULL, '
              "tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), "
              "modalidad TEXT NOT NULL CHECK (modalidad IN ('MONTO_TOTAL_CUOTAS','RECURRENTE')), "
              'monto_total REAL, '
              'monto_periodico REAL, '
              'frecuencia TEXT NOT NULL, '
              'frecuencia_dias INTEGER, '
              'cuotas INTEGER, '
              'fecha_inicio TEXT NOT NULL, '
              'fecha_fin TEXT, '
              'categoria TEXT NOT NULL, '
              'observaciones TEXT, '
              'activo INTEGER NOT NULL DEFAULT 1, '
              'archivo_local_path TEXT, '
              'archivo_remote_url TEXT, '
              'archivo_nombre TEXT, '
              'archivo_tipo TEXT, '
              'archivo_size INTEGER, '
              'dispositivo_id TEXT, '
              'eliminado INTEGER NOT NULL DEFAULT 0, '
              "sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), "
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              'FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id), '
              'FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id), '
              'FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo), '
              'CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio), '
              'CHECK ((modalidad = \'MONTO_TOTAL_CUOTAS\' AND monto_total IS NOT NULL AND cuotas IS NOT NULL) OR (modalidad = \'RECURRENTE\' AND monto_periodico IS NOT NULL))'
              ')');
          batch.execute('CREATE INDEX idx_acuerdos_unidad ON acuerdos(unidad_gestion_id, activo)');
          batch.execute('CREATE INDEX idx_acuerdos_tipo ON acuerdos(tipo, activo)');
          batch.execute('CREATE INDEX idx_acuerdos_entidad ON acuerdos(entidad_plantel_id) WHERE entidad_plantel_id IS NOT NULL');
          batch.execute('CREATE INDEX idx_acuerdos_sync ON acuerdos(sync_estado)');
          batch.execute('CREATE INDEX idx_acuerdos_eliminado ON acuerdos(eliminado, activo)');

          // Tabla de categorías de movimientos de tesorería
          batch.execute('CREATE TABLE categoria_movimiento ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'codigo TEXT UNIQUE NOT NULL, '
              'nombre TEXT NOT NULL, '
              "tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO','AMBOS')), "
              'icono TEXT, '
              'activa INTEGER NOT NULL DEFAULT 1, '
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
              ')');

          // FASE 13.1: Tabla de compromisos (obligaciones financieras recurrentes)
          // FASE 18: Agregado acuerdo_id para vincular con acuerdos
          batch.execute('CREATE TABLE compromisos ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'acuerdo_id INTEGER, '
              'unidad_gestion_id INTEGER NOT NULL, '
              'entidad_plantel_id INTEGER, '
              'nombre TEXT NOT NULL, '
              "tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), "
              "modalidad TEXT NOT NULL DEFAULT 'RECURRENTE' CHECK (modalidad IN ('PAGO_UNICO','MONTO_TOTAL_CUOTAS','RECURRENTE')), "
              'monto REAL NOT NULL CHECK (monto > 0), '
              'frecuencia TEXT NOT NULL, '
              'frecuencia_dias INTEGER, '
              'cuotas INTEGER, '
              'cuotas_confirmadas INTEGER DEFAULT 0, '
              'fecha_inicio TEXT NOT NULL, '
              'fecha_fin TEXT, '
              'categoria TEXT NOT NULL, '
              'observaciones TEXT, '
              'activo INTEGER NOT NULL DEFAULT 1, '
              'archivo_local_path TEXT, '
              'archivo_remote_url TEXT, '
              'archivo_nombre TEXT, '
              'archivo_tipo TEXT, '
              'archivo_size INTEGER, '
              'dispositivo_id TEXT, '
              'eliminado INTEGER NOT NULL DEFAULT 0, '
              "sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), "
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              'FOREIGN KEY (acuerdo_id) REFERENCES acuerdos(id), '
              'FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id), '
              'FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id), '
              'FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo), '
              'CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)'
              ')');          batch.execute('CREATE INDEX idx_compromisos_acuerdo ON compromisos(acuerdo_id) WHERE acuerdo_id IS NOT NULL');
          batch.execute('CREATE INDEX idx_compromisos_unidad ON compromisos(unidad_gestion_id, activo)');
          batch.execute('CREATE INDEX idx_compromisos_tipo ON compromisos(tipo, activo)');
          batch.execute('CREATE INDEX idx_compromisos_sync ON compromisos(sync_estado)');
          batch.execute('CREATE INDEX idx_compromisos_eliminado ON compromisos(eliminado, activo)');
          batch.execute('CREATE INDEX idx_compromisos_entidad_plantel ON compromisos(entidad_plantel_id) WHERE entidad_plantel_id IS NOT NULL');
          
          // FASE 17.1: Tabla de entidades del plantel (jugadores, cuerpo técnico)
          batch.execute('CREATE TABLE entidades_plantel ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'nombre TEXT NOT NULL, '
              "rol TEXT NOT NULL CHECK (rol IN ('JUGADOR','DT','AYUDANTE','PF','OTRO')), "
              'estado_activo INTEGER NOT NULL DEFAULT 1, '
              'observaciones TEXT, '
              'foto_url TEXT, '
              'contacto TEXT, '
              'dni TEXT, '
              'fecha_nacimiento TEXT, '
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
              ')');
          batch.execute('CREATE INDEX idx_entidades_plantel_rol ON entidades_plantel(rol, estado_activo)');
          batch.execute('CREATE INDEX idx_entidades_plantel_activo ON entidades_plantel(estado_activo)');
          
          // FASE 13.5: Tabla de cuotas de compromisos
          batch.execute('CREATE TABLE compromiso_cuotas ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'compromiso_id INTEGER NOT NULL, '
              'numero_cuota INTEGER NOT NULL, '
              'fecha_programada TEXT NOT NULL, '
              'monto_esperado REAL NOT NULL CHECK (monto_esperado > 0), '
              "estado TEXT NOT NULL DEFAULT 'ESPERADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO')), "
              'monto_real REAL, '
              'observacion_cancelacion TEXT, '
              "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
              'FOREIGN KEY (compromiso_id) REFERENCES compromisos(id) ON DELETE CASCADE, '
              'UNIQUE(compromiso_id, numero_cuota)'
              ')');
          batch.execute('CREATE INDEX idx_compromiso_cuotas_compromiso ON compromiso_cuotas(compromiso_id, numero_cuota)');
          batch.execute('CREATE INDEX idx_compromiso_cuotas_fecha ON compromiso_cuotas(fecha_programada, estado)');

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
          batch.execute(
              'CREATE UNIQUE INDEX ux_outbox_tipo_ref ON sync_outbox(tipo, ref)');

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

          // Resúmenes de cierre descargados desde Supabase (solo lectura / auditoría)
          batch.execute('CREATE TABLE caja_cierre_resumen ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'evento_fecha TEXT NOT NULL, '
              'disciplina TEXT NOT NULL, '
              'codigo_caja TEXT NOT NULL, '
              'source_device TEXT, '
              'items_count INTEGER NOT NULL DEFAULT 0, '
              'payload TEXT NOT NULL, '
              'created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP'
              ')');
          batch.execute(
              'CREATE UNIQUE INDEX ux_caja_cierre_resumen_evento ON caja_cierre_resumen(evento_fecha, disciplina, codigo_caja)');

          // Saldos Iniciales: balance al comienzo de un período (anual o mensual)
          // NO se registra como movimiento, se usa como base para cálculos
          batch.execute('CREATE TABLE saldos_iniciales ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'unidad_gestion_id INTEGER NOT NULL, '
              "periodo_tipo TEXT NOT NULL CHECK (periodo_tipo IN ('ANIO','MES')), "
              'periodo_valor TEXT NOT NULL, '
              'monto REAL NOT NULL, '
              'observacion TEXT, '
              'fecha_carga TEXT NOT NULL, '
              'FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id)'
              ')');
          batch.execute(
              'CREATE UNIQUE INDEX ux_saldo_inicial_unidad_periodo ON saldos_iniciales(unidad_gestion_id, periodo_tipo, periodo_valor)');

          await batch.commit(noResult: true);

          // Semillas iniciales (única vez)
          await _seedData(db);
          
          // Seed de unidades de gestión (tabla nueva que reemplaza disciplinas)
          await _seedUnidadesGestion(db);
          
          // FASE 13.1: Seed de frecuencias
          await _seedFrecuencias(db);
          
          // Seed de categorías de movimientos
          await _seedCategoriasMovimiento(db);
        },
        // Migraciones para instalaciones previas (v1 -> v2)
        onUpgrade: (db, from, to) async {
          // Asegurar FKs (usar rawQuery en Android)
          await db.rawQuery('PRAGMA foreign_keys=ON');
          // Crear tablas ausentes (idempotente)
          await db.execute(
              'CREATE TABLE IF NOT EXISTS metodos_pago (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS Categoria_Producto (id INTEGER PRIMARY KEY, descripcion TEXT NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, codigo_producto TEXT UNIQUE, nombre TEXT NOT NULL, precio_compra INTEGER, precio_venta INTEGER NOT NULL, stock_actual INTEGER DEFAULT 0, stock_minimo INTEGER DEFAULT 3, orden_visual INTEGER, categoria_id INTEGER, visible INTEGER DEFAULT 1, color TEXT, imagen TEXT, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id))');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS caja_diaria (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo_caja TEXT UNIQUE, disciplina TEXT, fecha TEXT, usuario_apertura TEXT, cajero_apertura TEXT, visible INTEGER NOT NULL DEFAULT 1, hora_apertura TEXT, apertura_dt TEXT, fondo_inicial REAL, conteo_efectivo_final REAL, conteo_transferencias_final REAL, estado TEXT, ingresos REAL DEFAULT 0, retiros REAL DEFAULT 0, diferencia REAL, total_tickets INTEGER, tickets_anulados INTEGER, entradas INTEGER, hora_cierre TEXT, cierre_dt TEXT, usuario_cierre TEXT, cajero_cierre TEXT, descripcion_evento TEXT, observaciones_apertura TEXT, obs_cierre TEXT, created_ts INTEGER, updated_ts INTEGER)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS ventas (id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT UNIQUE, fecha_hora TEXT NOT NULL, total_venta REAL NOT NULL, status TEXT DEFAULT "No impreso", activo INTEGER DEFAULT 1, metodo_pago_id INTEGER, caja_id INTEGER, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (metodo_pago_id) REFERENCES metodos_pago(id), FOREIGN KEY (caja_id) REFERENCES caja_diaria(id))');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS venta_items (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER NOT NULL, producto_id INTEGER NOT NULL, cantidad INTEGER NOT NULL, precio_unitario REAL NOT NULL, subtotal REAL NOT NULL, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE, FOREIGN KEY (producto_id) REFERENCES products(id))');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS tickets (id INTEGER PRIMARY KEY AUTOINCREMENT, venta_id INTEGER, categoria_id INTEGER, producto_id INTEGER, fecha_hora TEXT NOT NULL, status TEXT DEFAULT "No impreso", total_ticket REAL NOT NULL, identificador_ticket TEXT, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (venta_id) REFERENCES ventas(id), FOREIGN KEY (categoria_id) REFERENCES Categoria_Producto(id), FOREIGN KEY (producto_id) REFERENCES products(id))');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS caja_movimiento (id INTEGER PRIMARY KEY AUTOINCREMENT, caja_id INTEGER NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN (\'INGRESO\',\'RETIRO\')), monto REAL NOT NULL CHECK (monto > 0), observacion TEXT, created_ts INTEGER, updated_ts INTEGER, FOREIGN KEY (caja_id) REFERENCES caja_diaria(id))');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS punto_venta (codigo TEXT PRIMARY KEY, nombre TEXT NOT NULL, alias_caja TEXT, created_ts INTEGER, updated_ts INTEGER)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS disciplinas (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT UNIQUE NOT NULL, created_ts INTEGER, updated_ts INTEGER)');
          await db.execute(
              "CREATE TABLE IF NOT EXISTS unidades_gestion (id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT UNIQUE NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('DISCIPLINA','COMISION','EVENTO')), disciplina_ref TEXT, activo INTEGER NOT NULL DEFAULT 1, created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000))");
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_unidades_gestion_tipo ON unidades_gestion(tipo, activo)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS sync_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, tipo TEXT NOT NULL, ref TEXT NOT NULL, payload TEXT NOT NULL, estado TEXT NOT NULL DEFAULT \"pending\", reintentos INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_ts INTEGER NOT NULL DEFAULT (strftime(\'%s\',\'now\')*1000))');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS ux_outbox_tipo_ref ON sync_outbox(tipo, ref)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS sync_error_log (id INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT, message TEXT, payload TEXT, created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS app_error_log (id INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT, message TEXT, stacktrace TEXT, payload TEXT, created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');

          // Tabla vNext: movimientos financieros externos (idempotente)
          await db.execute(
              "CREATE TABLE IF NOT EXISTS evento_movimiento (id INTEGER PRIMARY KEY AUTOINCREMENT, evento_id TEXT, disciplina_id INTEGER NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), categoria TEXT, monto REAL NOT NULL CHECK (monto > 0), medio_pago_id INTEGER NOT NULL, observacion TEXT, dispositivo_id TEXT, sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (medio_pago_id) REFERENCES metodos_pago(id))");
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_evento_mov_disc_created ON evento_movimiento(disciplina_id, created_ts)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_evento_mov_evento_id ON evento_movimiento(evento_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_evento_mov_mp_id ON evento_movimiento(medio_pago_id)');

          // FASE 13.1: Crear tablas de compromisos si no existen (idempotente)
          await db.execute(
              'CREATE TABLE IF NOT EXISTS frecuencias (codigo TEXT PRIMARY KEY, descripcion TEXT NOT NULL, dias INTEGER)');
          
          // FASE 18: Crear tabla de acuerdos (idempotente)
          await db.execute(
              "CREATE TABLE IF NOT EXISTS acuerdos (id INTEGER PRIMARY KEY AUTOINCREMENT, unidad_gestion_id INTEGER NOT NULL, entidad_plantel_id INTEGER, nombre TEXT NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), modalidad TEXT NOT NULL CHECK (modalidad IN ('MONTO_TOTAL_CUOTAS','RECURRENTE')), monto_total REAL, monto_periodico REAL, frecuencia TEXT NOT NULL, frecuencia_dias INTEGER, cuotas INTEGER, fecha_inicio TEXT NOT NULL, fecha_fin TEXT, categoria TEXT NOT NULL, observaciones TEXT, activo INTEGER NOT NULL DEFAULT 1, archivo_local_path TEXT, archivo_remote_url TEXT, archivo_nombre TEXT, archivo_tipo TEXT, archivo_size INTEGER, dispositivo_id TEXT, eliminado INTEGER NOT NULL DEFAULT 0, sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id), FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id), FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo), CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio), CHECK ((modalidad = 'MONTO_TOTAL_CUOTAS' AND monto_total IS NOT NULL AND cuotas IS NOT NULL) OR (modalidad = 'RECURRENTE' AND monto_periodico IS NOT NULL)))");
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_acuerdos_unidad ON acuerdos(unidad_gestion_id, activo)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_acuerdos_tipo ON acuerdos(tipo, activo)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_acuerdos_entidad ON acuerdos(entidad_plantel_id) WHERE entidad_plantel_id IS NOT NULL');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_acuerdos_sync ON acuerdos(sync_estado)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_acuerdos_eliminado ON acuerdos(eliminado, activo)');
          
          // Tabla de categorías de movimientos (idempotente)
          await db.execute(
              "CREATE TABLE IF NOT EXISTS categoria_movimiento (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT UNIQUE NOT NULL, nombre TEXT NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO','AMBOS')), icono TEXT, observacion TEXT, activa INTEGER NOT NULL DEFAULT 1, created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000))");
          
          // FASE 13.5: Agregar columna modalidad a compromisos si no existe
          await _ensureCompromisoModalidadColumn(db);
          
          // FASE 18: Asegurar columna acuerdo_id en compromisos si no existe
          await _ensureCompromisoAcuerdoIdColumn(db);
          
          await db.execute(
              "CREATE TABLE IF NOT EXISTS compromisos (id INTEGER PRIMARY KEY AUTOINCREMENT, acuerdo_id INTEGER, unidad_gestion_id INTEGER NOT NULL, nombre TEXT NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), modalidad TEXT NOT NULL DEFAULT 'RECURRENTE' CHECK (modalidad IN ('PAGO_UNICO','MONTO_TOTAL_CUOTAS','RECURRENTE')), monto REAL NOT NULL CHECK (monto > 0), frecuencia TEXT NOT NULL, frecuencia_dias INTEGER, cuotas INTEGER, cuotas_confirmadas INTEGER DEFAULT 0, fecha_inicio TEXT NOT NULL, fecha_fin TEXT, categoria TEXT NOT NULL, observaciones TEXT, activo INTEGER NOT NULL DEFAULT 1, archivo_local_path TEXT, archivo_remote_url TEXT, archivo_nombre TEXT, archivo_tipo TEXT, archivo_size INTEGER, dispositivo_id TEXT, eliminado INTEGER NOT NULL DEFAULT 0, sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (acuerdo_id) REFERENCES acuerdos(id), FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id), FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo), CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio))");
          
          await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_acuerdo ON compromisos(acuerdo_id) WHERE acuerdo_id IS NOT NULL');
          
          // FASE 13.5: Crear tabla de cuotas si no existe
          await db.execute(
              "CREATE TABLE IF NOT EXISTS compromiso_cuotas (id INTEGER PRIMARY KEY AUTOINCREMENT, compromiso_id INTEGER NOT NULL, numero_cuota INTEGER NOT NULL, fecha_programada TEXT NOT NULL, monto_esperado REAL NOT NULL CHECK (monto_esperado > 0), estado TEXT NOT NULL DEFAULT 'ESPERADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO')), monto_real REAL, created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (compromiso_id) REFERENCES compromisos(id) ON DELETE CASCADE, UNIQUE(compromiso_id, numero_cuota))");
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_compromiso_cuotas_compromiso ON compromiso_cuotas(compromiso_id, numero_cuota)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_compromiso_cuotas_fecha ON compromiso_cuotas(fecha_programada, estado)');
          
          await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_unidad ON compromisos(unidad_gestion_id, activo)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_tipo ON compromisos(tipo, activo)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_sync ON compromisos(sync_estado)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_eliminado ON compromisos(eliminado, activo)');

          // Migración desde v6 (id TEXT / medio_pago TEXT) a v7 (id autoincrement / medio_pago_id FK)
          try {
            final emInfo = await db.rawQuery('PRAGMA table_info(evento_movimiento)');
            final hasMedioPagoId =
                emInfo.any((c) => (c['name'] as String?) == 'medio_pago_id');
            final hasMedioPagoText =
                emInfo.any((c) => (c['name'] as String?) == 'medio_pago');
            final idType = emInfo
                .firstWhere(
                  (c) => (c['name'] as String?) == 'id',
                  orElse: () => const <String, Object?>{},
                )['type']
                ?.toString()
                .toUpperCase();
            final idIsText = (idType ?? '').contains('TEXT');

            if (emInfo.isNotEmpty && (hasMedioPagoText || !hasMedioPagoId || idIsText)) {
              await db.transaction((txn) async {
                await txn.execute(
                    'ALTER TABLE evento_movimiento RENAME TO evento_movimiento_legacy_v6');

                await txn.execute(
                    "CREATE TABLE evento_movimiento (id INTEGER PRIMARY KEY AUTOINCREMENT, evento_id TEXT, disciplina_id INTEGER NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), categoria TEXT, monto REAL NOT NULL CHECK (monto > 0), medio_pago_id INTEGER NOT NULL, observacion TEXT, dispositivo_id TEXT, sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (medio_pago_id) REFERENCES metodos_pago(id))");
                await txn.execute(
                    'CREATE INDEX IF NOT EXISTS idx_evento_mov_disc_created ON evento_movimiento(disciplina_id, created_ts)');
                await txn.execute(
                    'CREATE INDEX IF NOT EXISTS idx_evento_mov_evento_id ON evento_movimiento(evento_id)');
                await txn.execute(
                    'CREATE INDEX IF NOT EXISTS idx_evento_mov_mp_id ON evento_movimiento(medio_pago_id)');

                // Copia best-effort desde el esquema viejo.
                // Mapear medio_pago TEXT -> medio_pago_id (1/2) si aplica; fallback a 1 (Efectivo).
                await txn.execute(
                    "INSERT INTO evento_movimiento (evento_id, disciplina_id, tipo, categoria, monto, medio_pago_id, observacion, dispositivo_id, sync_estado, created_ts) "
                    "SELECT evento_id, disciplina_id, tipo, categoria, monto, "
                    "CASE medio_pago "
                    "  WHEN 'Efectivo' THEN 1 "
                    "  WHEN 'Transferencia' THEN 2 "
                    "  ELSE 1 "
                    "END AS medio_pago_id, "
                    "observacion, dispositivo_id, sync_estado, created_ts "
                    "FROM evento_movimiento_legacy_v6");

                await txn.execute('DROP TABLE evento_movimiento_legacy_v6');
              });
            }
          } catch (e, st) {
            await logLocalError(
                scope: 'db.migrate_evento_movimiento_v7',
                error: e,
                stackTrace: st);
          }

          // Tabla para persistir descargas de cierres (idempotente)
          await db.execute(
              'CREATE TABLE IF NOT EXISTS caja_cierre_resumen (id INTEGER PRIMARY KEY AUTOINCREMENT, evento_fecha TEXT NOT NULL, disciplina TEXT NOT NULL, codigo_caja TEXT NOT NULL, source_device TEXT, items_count INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL, created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)');
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS ux_caja_cierre_resumen_evento ON caja_cierre_resumen(evento_fecha, disciplina, codigo_caja)');

          // Asegurar columnas nuevas en caja_diaria
          final cajaInfo = await db.rawQuery('PRAGMA table_info(caja_diaria)');
          Future<void> _ensureCol(String name, String ddl) async {
            final exists = cajaInfo.any((c) => (c['name'] as String?) == name);
            if (!exists) {
              await db.execute('ALTER TABLE caja_diaria ADD COLUMN $ddl');
            }
          }

          await _ensureCol('descripcion_evento', 'descripcion_evento TEXT');
          await _ensureCol('tickets_anulados', 'tickets_anulados INTEGER');
          await _ensureCol('entradas', 'entradas INTEGER');
          await _ensureCol('cajero_apertura', 'cajero_apertura TEXT');
          await _ensureCol('cajero_cierre', 'cajero_cierre TEXT');
          await _ensureCol('usuario_cierre', 'usuario_cierre TEXT');
          await _ensureCol(
              'conteo_efectivo_final', 'conteo_efectivo_final REAL');
          await _ensureCol('conteo_transferencias_final',
              'conteo_transferencias_final REAL');
          await _ensureCol('visible', 'visible INTEGER NOT NULL DEFAULT 1');

          // Asegurar columnas de archivo en evento_movimiento
          final emColumnInfo = await db.rawQuery('PRAGMA table_info(evento_movimiento)');
          Future<void> _ensureColEM(String name, String ddl) async {
            final exists = emColumnInfo.any((c) => (c['name'] as String?) == name);
            if (!exists) {
              await db.execute('ALTER TABLE evento_movimiento ADD COLUMN $ddl');
            }
          }
          
          await _ensureColEM('archivo_local_path', 'archivo_local_path TEXT');
          await _ensureColEM('archivo_remote_url', 'archivo_remote_url TEXT');
          await _ensureColEM('archivo_nombre', 'archivo_nombre TEXT');
          await _ensureColEM('archivo_tipo', 'archivo_tipo TEXT');
          await _ensureColEM('archivo_size', 'archivo_size INTEGER');
          await _ensureColEM('eliminado', 'eliminado INTEGER NOT NULL DEFAULT 0');
          await _ensureColEM('updated_ts', 'updated_ts INTEGER');
          
          // FASE 13.1: Asegurar nuevas columnas de compromisos en evento_movimiento
          await _ensureColEM('compromiso_id', 'compromiso_id INTEGER');
          await _ensureColEM('estado', "estado TEXT NOT NULL DEFAULT 'CONFIRMADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO'))");
          
          // Crear índices de compromisos si no existen
          await db.execute('CREATE INDEX IF NOT EXISTS idx_evento_mov_compromiso ON evento_movimiento(compromiso_id, estado)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_evento_mov_estado ON evento_movimiento(estado, created_ts)');

          // Tabla para saldos iniciales (idempotente)
          // Balance al comienzo de un período (anual o mensual) - NO se registra como movimiento
          await db.execute(
              "CREATE TABLE IF NOT EXISTS saldos_iniciales ("
              "id INTEGER PRIMARY KEY AUTOINCREMENT, "
              "unidad_gestion_id INTEGER NOT NULL, "
              "periodo_tipo TEXT NOT NULL CHECK (periodo_tipo IN ('ANIO','MES')), "
              "periodo_valor TEXT NOT NULL, "
              "monto REAL NOT NULL, "
              "observacion TEXT, "
              "fecha_carga TEXT NOT NULL, "
              "FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id)"
              ")");
          await db.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS ux_saldo_inicial_unidad_periodo ON saldos_iniciales(unidad_gestion_id, periodo_tipo, periodo_valor)');


          // Asegurar columna alias_caja en punto_venta
          try {
            final pvInfo = await db.rawQuery('PRAGMA table_info(punto_venta)');
            final hasAliasCaja =
                pvInfo.any((c) => (c['name'] as String?) == 'alias_caja');
            if (!hasAliasCaja) {
              await db.execute(
                  'ALTER TABLE punto_venta ADD COLUMN alias_caja TEXT');
            }
          } catch (e, st) {
            await logLocalError(
                scope: 'db.ensurePvAliasCaja', error: e, stackTrace: st);
          }

          // Inicializar cajero_apertura si se agregó
          final hasCajeroA =
              cajaInfo.any((c) => (c['name'] as String?) == 'cajero_apertura');
          if (!hasCajeroA) {
            await db.rawUpdate(
                "UPDATE caja_diaria SET cajero_apertura = COALESCE(usuario_apertura, 'admin')");
          }

          // Asegurar columna orden_visual en products
          final prodInfo = await db.rawQuery('PRAGMA table_info(products)');
          final hasOrden =
              prodInfo.any((c) => (c['name'] as String?) == 'orden_visual');
          if (!hasOrden) {
            await db.execute(
                'ALTER TABLE products ADD COLUMN orden_visual INTEGER');
            await db.rawUpdate(
                'UPDATE products SET orden_visual = 1000 + id WHERE orden_visual IS NULL');
          }
          // Índices útiles
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_visible_cat_order ON products(visible, categoria_id, orden_visual)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_ventas_fecha_hora ON ventas(fecha_hora)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_ventas_caja ON ventas(caja_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_ventas_mp ON ventas(metodo_pago_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_ventas_activo ON ventas(activo)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_items_venta_id ON venta_items(venta_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_tickets_venta_id ON tickets(venta_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_tickets_categoria_id ON tickets(categoria_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_mov_caja_id ON caja_movimiento(caja_id)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_mov_caja_tipo ON caja_movimiento(caja_id, tipo)');

          // Catálogos base (normalizados): como no consideramos datos históricos,
          // dejamos los catálogos exactamente como el listado esperado.
          
          // Asegurar seed de unidades_gestion (incluso si la tabla ya existía)
          await _seedUnidadesGestion(db);

          // metodos_pago
          await db.rawUpdate(
              "UPDATE metodos_pago SET descripcion='Efectivo' WHERE id=1");
          await db.rawUpdate(
              "UPDATE metodos_pago SET descripcion='Transferencia' WHERE id=2");
          await db.execute('DELETE FROM metodos_pago WHERE id NOT IN (1,2)');
          await db.insert('metodos_pago', {'id': 1, 'descripcion': 'Efectivo'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert(
              'metodos_pago', {'id': 2, 'descripcion': 'Transferencia'},
              conflictAlgorithm: ConflictAlgorithm.ignore);

          // Categoria_Producto
          await db.rawUpdate(
              "UPDATE Categoria_Producto SET descripcion='Comida' WHERE id=1");
          await db.rawUpdate(
              "UPDATE Categoria_Producto SET descripcion='Bebida' WHERE id=2");
          await db.rawUpdate(
              "UPDATE Categoria_Producto SET descripcion='Otro' WHERE id=3");
          await db.insert(
              'Categoria_Producto', {'id': 1, 'descripcion': 'Comida'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert(
              'Categoria_Producto', {'id': 2, 'descripcion': 'Bebida'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert(
              'Categoria_Producto', {'id': 3, 'descripcion': 'Otro'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          // Borrar categorías extra solo si no están referenciadas por products.
          await db.execute('DELETE FROM Categoria_Producto '
              'WHERE id NOT IN (1,2,3) '
              'AND id NOT IN (SELECT DISTINCT categoria_id FROM products WHERE categoria_id IS NOT NULL)');

          // punto_venta
          await db.rawUpdate(
              "UPDATE punto_venta SET nombre='Caja1' WHERE codigo='Caj01'");
          await db.rawUpdate(
              "UPDATE punto_venta SET nombre='Caja2' WHERE codigo='Caj02'");
          await db.rawUpdate(
              "UPDATE punto_venta SET nombre='Caja3' WHERE codigo='Caj03'");
          await db.rawUpdate(
              "UPDATE punto_venta SET nombre='Caja4' WHERE codigo='Caj04'");
          await db.execute(
              "DELETE FROM punto_venta WHERE codigo NOT IN ('Caj01','Caj02','Caj03','Caj04')");
          await db.insert('punto_venta', {'codigo': 'Caj01', 'nombre': 'Caja1'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('punto_venta', {'codigo': 'Caj02', 'nombre': 'Caja2'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('punto_venta', {'codigo': 'Caj03', 'nombre': 'Caja3'},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('punto_venta', {'codigo': 'Caj04', 'nombre': 'Caja4'},
              conflictAlgorithm: ConflictAlgorithm.ignore);

          // disciplinas (deprecated - mantener para compatibilidad)
          await db.delete('disciplinas');
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
            await db.insert('disciplinas', d,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          
          // unidades_gestion (nuevo concepto que reemplaza disciplinas)
          await _seedUnidadesGestion(db);
          
          // FASE 13.1: Seed de frecuencias (catálogo estático)
          await _seedFrecuencias(db);
          
          // Seed de categorías de movimientos
          await _seedCategoriasMovimiento(db);
          
          // FASE 17.1-17.2: Asegurar tabla entidades_plantel y columna en compromisos
          await ensureEntidadesPlantelTabla();

          // Deduplicar outbox pre-índice único (por si existía)
          await db.rawDelete(
              'DELETE FROM sync_outbox WHERE id NOT IN (SELECT MAX(id) FROM sync_outbox GROUP BY tipo, ref)');
        },
      ),
    );

    return _db!;
  }
  
  /// Seed de unidades de gestión (se ejecuta en onCreate y onUpgrade)
  /// para asegurar que siempre estén presentes
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
      await db.insert('unidades_gestion', u,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// FASE 13.5: Asegura que exista la columna modalidad en compromisos (idempotente)
  static Future<void> _ensureCompromisoModalidadColumn(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info(compromisos)');
      final hasModalidad = result.any((col) => col['name'] == 'modalidad');
      
      if (!hasModalidad) {
        await db.execute(
          "ALTER TABLE compromisos ADD COLUMN modalidad TEXT NOT NULL DEFAULT 'RECURRENTE' CHECK (modalidad IN ('PAGO_UNICO','MONTO_TOTAL_CUOTAS','RECURRENTE'))"
        );
      }
    } catch (e) {
      // Si la tabla no existe, no hacer nada (se creará después)
    }
  }

  /// FASE 18: Asegura que exista la columna acuerdo_id en compromisos (idempotente)
  static Future<void> _ensureCompromisoAcuerdoIdColumn(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info(compromisos)');
      final hasAcuerdoId = result.any((col) => col['name'] == 'acuerdo_id');
      
      if (!hasAcuerdoId) {
        await db.execute(
          'ALTER TABLE compromisos ADD COLUMN acuerdo_id INTEGER'
        );
        // Crear índice después de agregar la columna
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_compromisos_acuerdo ON compromisos(acuerdo_id) WHERE acuerdo_id IS NOT NULL'
        );
      }
    } catch (e) {
      // Si la tabla no existe, no hacer nada (se creará después)
    }
  }

  static Future<void> _ensureCompromisoCuotasObservacionColumn(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info(compromiso_cuotas)');
      final hasObservacion = result.any((col) => col['name'] == 'observacion_cancelacion');
      
      if (!hasObservacion) {
        await db.execute(
          'ALTER TABLE compromiso_cuotas ADD COLUMN observacion_cancelacion TEXT'
        );
      }
    } catch (e) {
      // Si la tabla no existe, no hacer nada (se creará después)
    }
  }

  /// FASE 13.1: Seed de frecuencias para compromisos (se ejecuta en onCreate y onUpgrade)
  /// Catálogo estático de frecuencias de pago/cobro
  static Future<void> _seedFrecuencias(Database db) async {
    const frecuencias = [
      {'codigo': 'MENSUAL', 'descripcion': 'Mensual', 'dias': 30},
      {'codigo': 'BIMESTRAL', 'descripcion': 'Bimestral', 'dias': 60},
      {'codigo': 'TRIMESTRAL', 'descripcion': 'Trimestral', 'dias': 90},
      {'codigo': 'CUATRIMESTRAL', 'descripcion': 'Cuatrimestral', 'dias': 120},
      {'codigo': 'SEMESTRAL', 'descripcion': 'Semestral', 'dias': 180},
      {'codigo': 'ANUAL', 'descripcion': 'Anual', 'dias': 365},
      {'codigo': 'UNICA_VEZ', 'descripcion': 'Única vez', 'dias': null},
    ];
    
    for (final f in frecuencias) {
      await db.insert('frecuencias', f,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Seed de categorías de movimientos de tesorería (se ejecuta en onCreate y onUpgrade)
  /// Catálogo inicial de categorías comunes
  static Future<void> _seedCategoriasMovimiento(Database db) async {
    const categorias = [
      // INGRESOS
      {'codigo': 'ENTR', 'nombre': 'ENTRADAS', 'tipo': 'INGRESO', 'icono': 'confirmation_number', 'observacion': 'Ingresos por venta de entradas a eventos', 'activa': 1},
      {'codigo': 'UTBP', 'nombre': 'UTILIDAD BAR Y PARRILLA', 'tipo': 'INGRESO', 'icono': 'restaurant', 'observacion': 'Ganancias netas del servicio de bar y parrilla', 'activa': 1},
      {'codigo': 'VENT', 'nombre': 'VENTA NÚMERO EN CANCHA', 'tipo': 'INGRESO', 'icono': 'sports_soccer', 'observacion': 'Venta de números para sorteos en partidos', 'activa': 1},
      {'codigo': 'TRIB', 'nombre': 'TRIBUNA', 'tipo': 'INGRESO', 'icono': 'stadium', 'observacion': 'Ingresos por uso de tribunas', 'activa': 1},
      {'codigo': 'PUBL', 'nombre': 'REC.PUBLICIDAD ESTÁTICA Y GASTO', 'tipo': 'INGRESO', 'icono': 'campaign', 'observacion': 'Ingresos por publicidad y gastos asociados', 'activa': 1},
      {'codigo': 'COLA', 'nombre': 'COLABORADORES PAGO DT Y JUG', 'tipo': 'INGRESO', 'icono': 'volunteer_activism', 'observacion': 'Aportes de colaboradores para pago de DT y jugadores', 'activa': 1},
      {'codigo': 'PEIN', 'nombre': 'PEÑAS E INGRESOS VARIOS', 'tipo': 'INGRESO', 'icono': 'groups', 'observacion': 'Ingresos de peñas y otros conceptos varios', 'activa': 1},
      {'codigo': 'COVE', 'nombre': 'COMISIONES VENTA RIFAS ETC.', 'tipo': 'INGRESO', 'icono': 'local_activity', 'observacion': 'Comisiones por venta de rifas y sorteos', 'activa': 1},
      {'codigo': 'INTE', 'nombre': 'INTERESES y GASTOS Cuenta', 'tipo': 'INGRESO', 'icono': 'account_balance', 'observacion': 'Intereses ganados y gastos bancarios', 'activa': 1},
      {'codigo': 'LIGA', 'nombre': 'LIGA - FICHAJES Y MULTAS', 'tipo': 'INGRESO', 'icono': 'gavel', 'observacion': 'Ingresos por fichajes de jugadores y multas de liga', 'activa': 1},
      {'codigo': 'COBR', 'nombre': 'COBROS Y PAGOS PASE JUGADOR', 'tipo': 'INGRESO', 'icono': 'swap_horiz', 'observacion': 'Transacciones por pases de jugadores', 'activa': 1},
      
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
      {'codigo': 'INDU', 'nombre': 'INDUMENTARIA', 'tipo': 'EGRESO', 'icono': 'checkroom', 'activa': 1},
      {'codigo': 'SEMA', 'nombre': 'SERVICIO MEDICO Y AMBULANCIA', 'tipo': 'EGRESO', 'icono': 'ambulance', 'activa': 1},
      {'codigo': 'GARE', 'nombre': 'GASTOS ATENCIÓN REFUERZOS', 'tipo': 'EGRESO', 'icono': 'dinner_dining', 'activa': 1},
      {'codigo': 'INGE', 'nombre': 'INGRESOS Y GASTOS SOCIOS', 'tipo': 'AMBOS', 'icono': 'card_membership', 'activa': 1},
      {'codigo': 'BINC', 'nombre': 'BINGO CLUB', 'tipo': 'AMBOS', 'icono': 'casino', 'activa': 1},
      {'codigo': 'DSAL', 'nombre': 'DIFERENCIA SALDO', 'tipo': 'AMBOS', 'icono': 'account_balance_wallet', 'activa': 1},
    ];
    
    for (final c in categorias) {
      await db.insert('categoria_movimiento', c,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
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
          // Guardar hora local del dispositivo para que el log sea consistente en UI.
          'created_ts': nowLocalSqlString(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      // Evitar ciclos de error; como último recurso, ignorar
    }
  }

  /// Devuelve los últimos [limit] errores almacenados localmente.
  static Future<List<Map<String, dynamic>>> ultimosErrores(
      {int limit = 50}) async {
    try {
      final db = await instance();
      final rows =
          await db.query('app_error_log', orderBy: 'id DESC', limit: limit);
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e, st) {
      // Si incluso esto falla, registramos en memoria (no persistente)
      await logLocalError(
          scope: 'app_error_log.read', error: e, stackTrace: st);
      return const [];
    }
  }

  /// Borra todos los registros del log de errores local.
  static Future<int> clearErrorLogs() async {
    try {
      final db = await instance();
      return await db.delete('app_error_log');
    } catch (e, st) {
      await logLocalError(
          scope: 'app_error_log.clear', error: e, stackTrace: st);
      return 0;
    }
  }

  /// Elimina logs locales antiguos (política de retención).
  ///
  /// - Borra de `app_error_log` y `sync_error_log` según `created_ts` (TEXT).
  /// - Limpia `sync_outbox` tipo='error' según `created_ts` (INTEGER epoch ms).
  ///
  /// Best-effort: si falla, registra en `app_error_log` y no rompe el flujo.
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
      final cutoff = DateTime(
        now.year,
        now.month - months,
        now.day,
        now.hour,
        now.minute,
        now.second,
      );
      final cutoffStr = toSqlString(cutoff);
      final cutoffMs = cutoff.millisecondsSinceEpoch;

      await db.transaction((txn) async {
        result['app_error_log'] = await txn.delete(
          'app_error_log',
          where: 'created_ts < ?',
          whereArgs: [cutoffStr],
        );
        result['sync_error_log'] = await txn.delete(
          'sync_error_log',
          where: 'created_ts < ?',
          whereArgs: [cutoffStr],
        );
        result['sync_outbox_error'] = await txn.delete(
          'sync_outbox',
          where: 'tipo=? AND created_ts < ?',
          whereArgs: ['error', cutoffMs],
        );
      });
    } catch (e, st) {
      await logLocalError(
        scope: 'db.purgeOldErrorLogs',
        error: e,
        stackTrace: st,
        payload: {'months': months},
      );
    }

    return result;
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
      await logLocalError(
          scope: 'db.ensureCajaDiariaColumn',
          error: e,
          stackTrace: st,
          payload: {'name': name, 'ddl': ddl});
      rethrow;
    }
  }

  /// Asegura en tiempo de ejecución que exista la tabla `caja_cierre_resumen`.
  /// Útil cuando la app ya estaba instalada y no se ejecuta onUpgrade.
  static Future<void> ensureCajaCierreResumenTable() async {
    try {
      final db = await instance();
      await db.execute('CREATE TABLE IF NOT EXISTS caja_cierre_resumen ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'evento_fecha TEXT NOT NULL, '
          'disciplina TEXT NOT NULL, '
          'codigo_caja TEXT NOT NULL, '
          'source_device TEXT, '
          'items_count INTEGER NOT NULL DEFAULT 0, '
          'payload TEXT NOT NULL, '
          'created_ts TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP'
          ')');
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS ux_caja_cierre_resumen_evento ON caja_cierre_resumen(evento_fecha, disciplina, codigo_caja)');
    } catch (e, st) {
      await logLocalError(
          scope: 'db.ensureCajaCierreResumenTable', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// FASE 13.1: Asegura que existan las tablas de compromisos y frecuencias.
  /// Útil cuando la app ya estaba instalada y no se ejecuta onUpgrade.
  static Future<void> ensureCompromisosTablas() async {
    try {
      final db = await instance();
      
      // Tabla frecuencias
      await db.execute('CREATE TABLE IF NOT EXISTS frecuencias ('
          'codigo TEXT PRIMARY KEY, '
          'descripcion TEXT NOT NULL, '
          'dias INTEGER'
          ')');
      await _seedFrecuencias(db);
      
      // FASE 13.5: Asegurar columna modalidad
      await _ensureCompromisoModalidadColumn(db);
      
      // Asegurar columna observacion_cancelacion en compromiso_cuotas
      await _ensureCompromisoCuotasObservacionColumn(db);
      
      // Tabla compromisos
      await db.execute(
          "CREATE TABLE IF NOT EXISTS compromisos (id INTEGER PRIMARY KEY AUTOINCREMENT, unidad_gestion_id INTEGER NOT NULL, nombre TEXT NOT NULL, tipo TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO')), modalidad TEXT NOT NULL DEFAULT 'RECURRENTE' CHECK (modalidad IN ('PAGO_UNICO','MONTO_TOTAL_CUOTAS','RECURRENTE')), monto REAL NOT NULL CHECK (monto > 0), frecuencia TEXT NOT NULL, frecuencia_dias INTEGER, cuotas INTEGER, cuotas_confirmadas INTEGER DEFAULT 0, fecha_inicio TEXT NOT NULL, fecha_fin TEXT, categoria TEXT NOT NULL, observaciones TEXT, activo INTEGER NOT NULL DEFAULT 1, archivo_local_path TEXT, archivo_remote_url TEXT, archivo_nombre TEXT, archivo_tipo TEXT, archivo_size INTEGER, dispositivo_id TEXT, eliminado INTEGER NOT NULL DEFAULT 0, sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR')), created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id), FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo), CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio))");
      
      await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_unidad ON compromisos(unidad_gestion_id, activo)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_tipo ON compromisos(tipo, activo)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_sync ON compromisos(sync_estado)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_eliminado ON compromisos(eliminado, activo)');
      
      // FASE 13.5: Tabla de cuotas
      await db.execute(
          "CREATE TABLE IF NOT EXISTS compromiso_cuotas (id INTEGER PRIMARY KEY AUTOINCREMENT, compromiso_id INTEGER NOT NULL, numero_cuota INTEGER NOT NULL, fecha_programada TEXT NOT NULL, monto_esperado REAL NOT NULL CHECK (monto_esperado > 0), estado TEXT NOT NULL DEFAULT 'ESPERADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO')), monto_real REAL, created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), FOREIGN KEY (compromiso_id) REFERENCES compromisos(id) ON DELETE CASCADE, UNIQUE(compromiso_id, numero_cuota))");
      
      await db.execute('CREATE INDEX IF NOT EXISTS idx_compromiso_cuotas_compromiso ON compromiso_cuotas(compromiso_id, numero_cuota)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_compromiso_cuotas_fecha ON compromiso_cuotas(fecha_programada, estado)');
    } catch (e, st) {
      await logLocalError(
          scope: 'db.ensureCompromisosTablas', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// FASE 13.1: Asegura columnas de compromisos en evento_movimiento.
  static Future<void> ensureEventoMovimientoCompromisosColumns() async {
    try {
      final db = await instance();
      final emColumnInfo = await db.rawQuery('PRAGMA table_info(evento_movimiento)');
      
      Future<void> ensureCol(String name, String ddl) async {
        final exists = emColumnInfo.any((c) => (c['name'] as String?) == name);
        if (!exists) {
          await db.execute('ALTER TABLE evento_movimiento ADD COLUMN $ddl');
        }
      }
      
      await ensureCol('compromiso_id', 'compromiso_id INTEGER');
      await ensureCol('estado', "estado TEXT NOT NULL DEFAULT 'CONFIRMADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO'))");
      
      // Índices
      await db.execute('CREATE INDEX IF NOT EXISTS idx_evento_mov_compromiso ON evento_movimiento(compromiso_id, estado)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_evento_mov_estado ON evento_movimiento(estado, created_ts)');
    } catch (e, st) {
      await logLocalError(
          scope: 'db.ensureEventoMovimientoCompromisosColumns', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// FASE 17.1-17.2: Asegura tabla entidades_plantel y columna en compromisos.
  static Future<void> ensureEntidadesPlantelTabla() async {
    try {
      final db = await instance();
      
      // Tabla entidades_plantel
      await db.execute('CREATE TABLE IF NOT EXISTS entidades_plantel ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'nombre TEXT NOT NULL, '
          "rol TEXT NOT NULL CHECK (rol IN ('JUGADOR','DT','AYUDANTE','PF','OTRO')), "
          'estado_activo INTEGER NOT NULL DEFAULT 1, '
          'observaciones TEXT, '
          'foto_url TEXT, '
          'contacto TEXT, '
          'dni TEXT, '
          'fecha_nacimiento TEXT, '
          "created_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000), "
          "updated_ts INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)"
          ')');
      
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entidades_plantel_rol ON entidades_plantel(rol, estado_activo)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entidades_plantel_activo ON entidades_plantel(estado_activo)');
      
      // Columna entidad_plantel_id en compromisos
      final compromisosInfo = await db.rawQuery('PRAGMA table_info(compromisos)');
      final existeEntidadPlantel = compromisosInfo.any((c) => (c['name'] as String?) == 'entidad_plantel_id');
      
      if (!existeEntidadPlantel) {
        await db.execute('ALTER TABLE compromisos ADD COLUMN entidad_plantel_id INTEGER');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_compromisos_entidad_plantel ON compromisos(entidad_plantel_id) WHERE entidad_plantel_id IS NOT NULL');
      }
    } catch (e, st) {
      await logLocalError(
          scope: 'db.ensureEntidadesPlantelTabla', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Devuelve cantidad total de cajas existentes.
  static Future<int> countCajas() async {
    try {
      final db = await instance();
      final v = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(1) FROM caja_diaria')) ??
          0;
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
        result['sync_outbox'] = await txn.delete('sync_outbox',
            where: "tipo IN (?,?,?,?,?)",
            whereArgs: [
              'venta',
              'venta_anulada',
              'cierre_caja',
              'ticket_anulado',
              'venta_item'
            ]);
      });
    } catch (e, st) {
      await logLocalError(
          scope: 'db.purgeCajasYAsociados', error: e, stackTrace: st);
      rethrow;
    }
    return result;
  }

  /// Crea un archivo físico de backup de la base de datos SQLite actual y devuelve la ruta.
  /// El archivo queda en el directorio de documentos de la app con nombre timestamp.
  static Future<String> crearBackupArchivo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = await _dbFilePath();
      final ts = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'backup_barcancha_${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}${two(ts.second)}.db';
      final backupPath = p.join(dir.path, name);
      await File(dbPath).copy(backupPath);
      return backupPath;
    } catch (e, st) {
      await logLocalError(
          scope: 'db.crearBackupArchivo', error: e, stackTrace: st);
      rethrow;
    }
  }

  // ========================================================================
  // SALDOS INICIALES - DAO
  // ========================================================================

  /// Inserta un nuevo saldo inicial.
  /// Retorna el ID del registro insertado.
  /// Lanza excepción si ya existe un saldo para esa unidad + período.
  static Future<int> insertSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo, // 'ANIO' | 'MES'
    required String periodoValor, // '2026' o '2026-01'
    required double monto,
    String? observacion,
  }) async {
    final db = await instance();
    final fechaCarga = nowLocalSqlString();

    return await db.insert('saldos_iniciales', {
      'unidad_gestion_id': unidadGestionId,
      'periodo_tipo': periodoTipo,
      'periodo_valor': periodoValor,
      'monto': monto,
      'observacion': observacion,
      'fecha_carga': fechaCarga,
    });
  }

  /// Obtiene el saldo inicial para una unidad y período específicos.
  /// Retorna null si no existe.
  static Future<Map<String, dynamic>?> obtenerSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final db = await instance();
    final result = await db.query(
      'saldos_iniciales',
      where: 'unidad_gestion_id = ? AND periodo_tipo = ? AND periodo_valor = ?',
      whereArgs: [unidadGestionId, periodoTipo, periodoValor],
      limit: 1,
    );

    return result.isNotEmpty ? result.first : null;
  }

  /// Verifica si ya existe un saldo inicial para la unidad y período.
  static Future<bool> existeSaldoInicial({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final db = await instance();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM saldos_iniciales '
      'WHERE unidad_gestion_id = ? AND periodo_tipo = ? AND periodo_valor = ?',
      [unidadGestionId, periodoTipo, periodoValor],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  /// Lista todos los saldos iniciales, opcionalmente filtrados por unidad.
  static Future<List<Map<String, dynamic>>> listarSaldosIniciales({
    int? unidadGestionId,
  }) async {
    final db = await instance();
    
    if (unidadGestionId != null) {
      return await db.query(
        'saldos_iniciales',
        where: 'unidad_gestion_id = ?',
        whereArgs: [unidadGestionId],
        orderBy: 'periodo_valor DESC',
      );
    }

    return await db.query(
      'saldos_iniciales',
      orderBy: 'unidad_gestion_id, periodo_valor DESC',
    );
  }

  /// Actualiza un saldo inicial existente.
  /// Retorna el número de filas afectadas (0 si no existe).
  static Future<int> actualizarSaldoInicial({
    required int id,
    required double monto,
    String? observacion,
  }) async {
    final db = await instance();
    
    return await db.update(
      'saldos_iniciales',
      {
        'monto': monto,
        'observacion': observacion,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina un saldo inicial.
  /// Retorna el número de filas afectadas (0 si no existe).
  static Future<int> eliminarSaldoInicial(int id) async {
    final db = await instance();
    
    return await db.delete(
      'saldos_iniciales',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========================================================================

  /// Cierra la conexión actual (si existe). Best-effort.
  static Future<void> close() async {
    try {
      final db = _db;
      _db = null;
      await db?.close();
    } catch (_) {
      _db = null;
    }
  }

  /// Restaura el estado "de fábrica": elimina el archivo SQLite y fuerza re-seed.
  ///
  /// Nota: esto borra TODO (cajas, ventas, tickets, movimientos, outbox, logs, catálogos locales)
  /// y los vuelve a crear desde `onCreate` + `_seedData`.
  static Future<void> factoryReset() async {
    await close();
    final dbPath = await _dbFilePath();
    await deleteDatabase(dbPath);
    // Limpieza extra por si quedan archivos de WAL/SHM (best-effort)
    try {
      await File('$dbPath-wal').delete();
    } catch (_) {}
    try {
      await File('$dbPath-shm').delete();
    } catch (_) {}
  }
}

Future<void> _seedData(Database db) async {
  final batch = db.batch();

  // Catálogos base (agrupar por tabla; ids/nombres/códigos estables)
  const metodosPago = [
    {'id': 1, 'descripcion': 'Efectivo'},
    {'id': 2, 'descripcion': 'Transferencia'},
  ];
  for (final mp in metodosPago) {
    batch.insert('metodos_pago', mp,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  const categorias = [
    {'id': 1, 'descripcion': 'Comida'},
    {'id': 2, 'descripcion': 'Bebida'},
    {'id': 3, 'descripcion': 'Otro'},
  ];
  for (final c in categorias) {
    batch.insert('Categoria_Producto', c,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  const puntosVenta = [
    {'codigo': 'Caj01', 'nombre': 'Caja1'},
    {'codigo': 'Caj02', 'nombre': 'Caja2'},
    {'codigo': 'Caj03', 'nombre': 'Caja3'},
    {'codigo': 'Caj04', 'nombre': 'Caja4'},
  ];
  for (final pv in puntosVenta) {
    batch.insert('punto_venta', pv,
        conflictAlgorithm: ConflictAlgorithm.ignore);
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
    batch.insert('disciplinas', d, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // Productos precargados
  const productos = [
    {
      'codigo_producto': 'HAMB',
      'nombre': 'Hamburguesa',
      'precio_venta': 3000,
      'precio_compra': 3000,
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
      'precio_compra': 3000,
      'stock_actual': 50,
      'stock_minimo': 3,
      'orden_visual': 2,
      'categoria_id': 1,
      'visible': 1,
    },
    {
      'codigo_producto': 'JARG',
      'nombre': 'Jarra gaseosa',
      'precio_venta': 2000,
      'precio_compra': 2000,
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
      'precio_compra': 1500,
      'stock_actual': 999,
      'stock_minimo': 5,
      'orden_visual': 4,
      'categoria_id': 2,
      'visible': 1,
    },
    {
      'codigo_producto': 'CERV',
      'nombre': 'Cerveza',
      'precio_venta': 3000,
      'precio_compra': 3000,
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
      'precio_compra': 5000,
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
      'precio_compra': 1000,
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
      'precio_compra': 1000,
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
      'precio_compra': 2000,
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
      'precio_compra': 1000,
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
      'precio_compra': 2500,
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
      'precio_compra': 2000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 12,
      'categoria_id': 1,
      'visible': 1,
    },
    {
      'codigo_producto': 'JARR',
      'nombre': 'Jarra',
      'precio_venta': 3000,
      'precio_compra': 3000,
      'stock_actual': 999,
      'stock_minimo': 3,
      'orden_visual': 13,
      'categoria_id': 3,
      'visible': 1,
    },
  ];
  for (final p in productos) {
    batch.insert('products', p, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  await batch.commit(noResult: true);
}
