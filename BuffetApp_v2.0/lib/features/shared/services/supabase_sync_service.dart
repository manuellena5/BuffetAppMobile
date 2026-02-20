import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress, Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../data/dao/db.dart';
import '../../../env/supabase_env.dart';

class SupaSyncService {
  SupaSyncService._();
  static final SupaSyncService I = SupaSyncService._();
  static bool _initialized = false;

  SupabaseClient get _sb => Supabase.instance.client;
  Timer? _timer;
  bool _busy = false;
  DateTime? _lastSyncAt;
  // Progreso en vivo de sincronización
  final StreamController<SyncProgress> _progressCtrl =
      StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progress$ => _progressCtrl.stream;
  // Último reporte
  int _lastOkCaja = 0;
  int _lastOkItem = 0;
  int _lastOkErrorRows = 0; // filas insertadas a sync_error_log
  int _lastFailCaja = 0;
  int _lastFailItem = 0;
  final List<String> _lastErrors = [];

  static Future<void> init() async {
    if (_initialized) return;
    await Supabase.initialize(
        url: SupabaseEnv.url, anonKey: SupabaseEnv.anonKey);
    _initialized = true;
  }

  Future<bool> hasInternet(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final r =
          await InternetAddress.lookup('one.one.one.one').timeout(timeout);
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Determina si un error es transitorio de red (DNS, socket, timeout, client)
  bool _isTransientNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('clientexception') ||
        msg.contains('network is unreachable') ||
        msg.contains('timed out');
  }

  /// Inserta (best-effort) un error en la tabla remota `sync_error_log`.
  ///
  /// - No rompe el flujo offline.
  /// - Si la tabla no existe en Supabase, falla silenciosamente.
  Future<void> tryInsertRemoteSyncErrorLog({
    required String scope,
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? payload,
  }) async {
    try {
      final hasNet = await hasInternet();
      if (!hasNet) return;

      final row = <String, dynamic>{
        'scope': scope,
        'message': error.toString(),
        'payload': payload == null
            ? null
            : _jsonSafe({
                ...payload,
                if (stackTrace != null) 'stacktrace': stackTrace.toString(),
              }),
      };

      try {
        await _sb.from('sync_error_log').insert(row);
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('does not exist') ||
            msg.contains('schema cache') ||
            msg.contains('could not find the table') ||
            msg.contains('pgrst')) {
          return;
        }
        // Intento mínimo sin payload.
        try {
          await _sb.from('sync_error_log').insert({
            'scope': scope,
            'message': error.toString(),
          });
        } catch (_) {}
      }
    } catch (_) {
      // nunca romper por logging remoto
    }
  }

  Future<void> start({Duration every = const Duration(seconds: 45)}) async {
    // Evitar timers en tests automatizados
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest) return;
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => syncNow());
  }

  Future<void> stop() async => _timer?.cancel();

  // Prepara outbox de items para una caja específica (incluye anulados con su status)
  Future<int> enqueueItemsForCajaId(int cajaId) async {
    final db = await AppDatabase.instance();
    final caja = await db.query('caja_diaria',
        columns: ['codigo_caja'], where: 'id=?', whereArgs: [cajaId], limit: 1);
    if (caja.isEmpty) return 0;
    final codigo = (caja.first['codigo_caja'] as String?) ?? '';
    if (codigo.isEmpty) return 0;
    final rows = await db.rawQuery('''
      SELECT
        t.id AS ticket_id,
        t.producto_id,
        t.categoria_id,
        t.total_ticket,
        t.fecha_hora,
        t.status,
        p.codigo_producto,
        p.nombre AS producto_nombre,
        c.descripcion AS categoria,
        v.metodo_pago_id,
        mp.descripcion AS metodo_pago
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      LEFT JOIN products p ON p.id = t.producto_id
      LEFT JOIN Categoria_Producto c ON c.id = t.categoria_id
      LEFT JOIN metodos_pago mp ON mp.id = v.metodo_pago_id
      WHERE v.caja_id = ? AND v.activo = 1
      ORDER BY t.id ASC
    ''', [cajaId]);
    int c = 0;
    for (final r in rows) {
      await enqueueItem({
        'codigo_caja': codigo,
        'ticket_id': r['ticket_id'],
        'producto_id': r['producto_id'],
        'codigo_producto': r['codigo_producto'],
        'categoria_id': r['categoria_id'],
        // Campos solicitados por servidor
        'fecha': r['fecha_hora'],
        'fecha_hora': r['fecha_hora'],
        'producto_nombre': r['producto_nombre'],
        'categoria': r['categoria'],
        'cantidad': 1,
        'precio_unitario': r['total_ticket'],
        'total': r['total_ticket'],
        'total_ticket': r['total_ticket'],
        'metodo_pago': r['metodo_pago'],
        'metodo_pago_id': r['metodo_pago_id'],
        'status': r['status'],
      });
      c++;
    }
    return c;
  }

  /// [DEPRECATED] Auto-sync legacy.
  /// El flujo principal de sync es `syncEventoCompleto()` (manual, por evento).
  /// Este método se mantiene como no-op para no romper llamadas existentes.
  Future<void> syncNow() async {
    // No-op: la tabla legacy caja_cierre_resumen ya no existe en Supabase.
    // Usar syncEventoCompleto() para sincronizar eventos/cajas.
  }

  /// Busca cajas de OTRO dispositivo para el mismo evento (fecha + disciplina).
  /// Usa tabla `caja_diaria` en Supabase.
  Future<List<Map<String, dynamic>>> findOtherCajasSameEvent({
    required String fecha,
    required String disciplina,
    String? descripcionEvento,
    required String excludeCodigoCaja,
  }) async {
    var q = _sb
        .from('caja_diaria')
        .select('*')
        .eq('disciplina', disciplina)
        .eq('fecha', fecha)
        .neq('codigo_caja', excludeCodigoCaja);
    final desc = (descripcionEvento ?? '').trim();
    if (desc.isNotEmpty) {
      q = q.eq('descripcion_evento', desc);
    }

    final res = await q.order('codigo_caja', ascending: true);
    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Busca una caja en Supabase por su código. Usa tabla `caja_diaria`.
  Future<Map<String, dynamic>?> fetchCajaCierreResumenByCodigo(
      String codigoCaja) async {
    final codigo = codigoCaja.trim();
    if (codigo.isEmpty) return null;

    final res = await _sb
        .from('caja_diaria')
        .select('*')
        .eq('codigo_caja', codigo)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res as Map);
  }

  /// Lista cajas cerradas disponibles en Supabase para una fecha (YYYY-MM-DD).
  /// La validación se hace por `fecha` (derivada de la fecha de apertura).
  ///
  /// Importante: en este flujo NUEVO la fuente remota es `caja_diaria`.
  /// `caja_cierre_resumen` era una tabla legacy (puede no existir en Supabase).
  Future<List<Map<String, dynamic>>> fetchCajasByFecha(String fecha) async {
    final f = fecha.trim();
    if (f.isEmpty) return const [];

    final res = await _sb
        .from('caja_diaria')
        .select('*')
        .eq('fecha', f)
        .eq('estado', 'CERRADA')
        .order('disciplina', ascending: true)
        .order('codigo_caja', ascending: true);

    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Lista cajas cerradas disponibles en Supabase para un rango de fechas
  /// inclusivo (YYYY-MM-DD).
  ///
  /// - `desde` y `hasta` deben venir como fecha ISO (sin hora).
  /// - Devuelve filas de `caja_diaria`.
  Future<List<Map<String, dynamic>>> fetchCajasByRango({
    required String desde,
    required String hasta,
  }) async {
    final d = desde.trim();
    final h = hasta.trim();
    if (d.isEmpty || h.isEmpty) return const [];

    final res = await _sb
        .from('caja_diaria')
        .select('*')
        .gte('fecha', d)
        .lte('fecha', h)
        .eq('estado', 'CERRADA')
        .order('fecha', ascending: true)
        .order('disciplina', ascending: true)
        .order('codigo_caja', ascending: true);

    return (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Descarga una caja desde Supabase (tablas core) y la inserta en SQLite.
  ///
  /// Trae y guarda:
  /// - `caja_diaria`
  /// - `ventas`
  /// - `venta_items`
  /// - `tickets`
  /// - `caja_movimiento`
  ///
  /// Además resuelve `producto_id` local por `codigo_producto` para evitar
  /// inconsistencias entre IDs remotos vs locales.
  Future<void> importRemoteCajaDiariaFullToLocal({
    required Map<String, dynamic> cajaRemote,
  }) async {
    final codigo = (cajaRemote['codigo_caja'] ?? '').toString().trim();
    if (codigo.isEmpty) {
      throw ArgumentError('cajaRemote.codigo_caja vacío');
    }

    final remoteCajaId = _toInt(cajaRemote['id']);
    if (remoteCajaId == null) {
      throw ArgumentError('cajaRemote.id inválido');
    }

    final ventas = await _sb
        .from('ventas')
        .select('*')
        .eq('caja_id', remoteCajaId)
        .order('id', ascending: true);
    final ventasList = (ventas as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);

    final ventaIds = ventasList
        .map((v) => _toInt(v['id']))
        .whereType<int>()
        .toList(growable: false);

    final itemsList = ventaIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _sb
                .from('venta_items')
                .select('*')
                .inFilter('venta_id', ventaIds)
                .order('id', ascending: true) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);

    final ticketsList = ventaIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _sb
                .from('tickets')
                .select('*')
                .inFilter('venta_id', ventaIds)
                .order('id', ascending: true) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);

    final movs = await _sb
        .from('caja_movimiento')
        .select('*')
        .eq('caja_id', remoteCajaId)
        .order('id', ascending: true);
    final movsList = (movs as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);

    // Resolver productos: ids remotos -> ids locales por codigo_producto.
    final remoteProductIds = <int>{};
    for (final it in itemsList) {
      final pid = _toInt(it['producto_id']);
      if (pid != null) remoteProductIds.add(pid);
    }
    for (final t in ticketsList) {
      final pid = _toInt(t['producto_id']);
      if (pid != null) remoteProductIds.add(pid);
    }

    final remoteProducts = remoteProductIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _sb.from('productos').select('*').inFilter(
                'id', remoteProductIds.toList(growable: false)) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);

    final db = await AppDatabase.instance();
    await AppDatabase.ensureCajaDiariaColumn(
        'visible', 'visible INTEGER NOT NULL DEFAULT 1');
    await AppDatabase.ensureCajaDiariaColumn(
        'sync_estado', 'sync_estado TEXT DEFAULT "PENDIENTE"');

    // Map remoto product.id -> local product.id
    final productIdMap = <int, int>{};

    await db.transaction((txn) async {
      // Asegurar productos en SQLite
      for (final rp in remoteProducts) {
        final rid = _toInt(rp['id']);
        if (rid == null) continue;
        final codigoProducto = (rp['codigo_producto'] ?? '').toString().trim();
        if (codigoProducto.isEmpty) continue;

        final existing = await txn.query(
          'products',
          columns: ['id'],
          where: 'codigo_producto=?',
          whereArgs: [codigoProducto],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          productIdMap[rid] = _toInt(existing.first['id'])!;
          continue;
        }

        final localId = await txn.insert('products', {
          'codigo_producto': codigoProducto,
          'nombre': (rp['nombre'] ?? '').toString(),
          // Mantener compat: sqlite guarda entero; si viene num, normalizar.
          'precio_venta': _toInt(rp['precio_venta']) ??
              _toInt(rp['precio']) ??
              _toInt(rp['precio_unitario']) ??
              0,
          // Evitar alertas de stock bajo para productos creados por import
          'stock_actual': 999,
          'stock_minimo': 3,
          'categoria_id': _toInt(rp['categoria_id']),
          'visible': 1,
          'color': rp['color'],
          'imagen': rp['imagen'],
        });
        productIdMap[rid] = localId;
      }

      // Insertar caja
      final cajaRow = <String, Object?>{
        'codigo_caja': codigo,
        'disciplina': cajaRemote['disciplina'],
        'fecha': cajaRemote['fecha'],
        'usuario_apertura': cajaRemote['usuario_apertura'],
        'cajero_apertura': cajaRemote['cajero_apertura'],
        'hora_apertura': cajaRemote['hora_apertura'],
        'apertura_dt': cajaRemote['apertura_dt'],
        'fondo_inicial': _toDouble(cajaRemote['fondo_inicial']),
        'conteo_efectivo_final': _toDouble(cajaRemote['conteo_efectivo_final']),
        'conteo_transferencias_final':
            _toDouble(cajaRemote['conteo_transferencias_final']),
        'estado': (cajaRemote['estado'] ?? 'CERRADA').toString(),
        'ingresos': _toDouble(cajaRemote['ingresos']) ?? 0,
        'retiros': _toDouble(cajaRemote['retiros']) ?? 0,
        'diferencia': _toDouble(cajaRemote['diferencia']),
        'total_tickets': _toInt(cajaRemote['total_tickets']),
        'tickets_anulados': _toInt(cajaRemote['tickets_anulados']),
        'entradas': _toInt(cajaRemote['entradas']),
        'hora_cierre': cajaRemote['hora_cierre'],
        'cierre_dt': cajaRemote['cierre_dt'],
        'usuario_cierre': cajaRemote['usuario_cierre'],
        'cajero_cierre': cajaRemote['cajero_cierre'],
        'descripcion_evento': cajaRemote['descripcion_evento'],
        'observaciones_apertura': cajaRemote['observaciones_apertura'],
        'obs_cierre': cajaRemote['obs_cierre'],
        'visible': 1,
        // Como proviene de Supabase, la consideramos ya sincronizada.
        'sync_estado': 'SINCRONIZADA',
      };

      final localCajaId = await txn.insert('caja_diaria', cajaRow);

      // Insertar ventas y mapear IDs
      final ventaIdMap = <int, int>{};
      for (final rv in ventasList) {
        final rid = _toInt(rv['id']);
        if (rid == null) continue;
        final row = <String, Object?>{
          'uuid': (rv['uuid'] ?? '').toString(),
          'fecha_hora': rv['fecha_hora'],
          'total_venta': _toDouble(rv['total_venta']) ?? 0,
          'status': rv['status'],
          'activo': _toInt(rv['activo']) ?? 1,
          'metodo_pago_id': _toInt(rv['metodo_pago_id']),
          'caja_id': localCajaId,
        };
        final localVentaId = await txn.insert('ventas', row);
        ventaIdMap[rid] = localVentaId;
      }

      // Insertar items
      for (final it in itemsList) {
        final remoteVentaId = _toInt(it['venta_id']);
        final localVentaId =
            remoteVentaId == null ? null : ventaIdMap[remoteVentaId];
        if (localVentaId == null) continue;

        final remoteProdId = _toInt(it['producto_id']);
        final localProdId =
            remoteProdId == null ? null : productIdMap[remoteProdId];
        if (localProdId == null) continue;

        await txn.insert('venta_items', {
          'venta_id': localVentaId,
          'producto_id': localProdId,
          'cantidad': _toInt(it['cantidad']) ?? 1,
          'precio_unitario': _toDouble(it['precio_unitario']) ?? 0,
          'subtotal': _toDouble(it['subtotal']) ?? 0,
        });
      }

      // Insertar tickets
      for (final t in ticketsList) {
        final remoteVentaId = _toInt(t['venta_id']);
        final localVentaId =
            remoteVentaId == null ? null : ventaIdMap[remoteVentaId];
        if (localVentaId == null) continue;

        final remoteProdId = _toInt(t['producto_id']);
        final localProdId =
            remoteProdId == null ? null : productIdMap[remoteProdId];

        await txn.insert('tickets', {
          'venta_id': localVentaId,
          'categoria_id': _toInt(t['categoria_id']),
          'producto_id': localProdId,
          'fecha_hora': t['fecha_hora'],
          'status': t['status'],
          'total_ticket': _toDouble(t['total_ticket']) ?? 0,
          'identificador_ticket': t['identificador_ticket'],
        });
      }

      // Insertar movimientos
      for (final m in movsList) {
        await txn.insert('caja_movimiento', {
          'caja_id': localCajaId,
          'tipo': m['tipo'],
          'monto': _toDouble(m['monto']) ?? 0,
          'observacion': m['observacion'],
          'medio_pago_id': (m['medio_pago_id'] as num?)?.toInt() ?? 1,
        });
      }
    });
  }

  /// [DEPRECATED] La tabla `caja_items` ya no existe en Supabase.
  /// Para obtener items, usar las tablas `ventas`, `venta_items`, `tickets`.
  Future<List<Map<String, dynamic>>> fetchCajaItemsByCodigo(
      String codigoCaja) async {
    // Tabla legacy caja_items ya no existe. Retornamos vacío.
    return const [];
  }

  /// Guarda localmente (SQLite) un cierre descargado desde Supabase para consulta offline.
  /// No modifica `caja_diaria`/`ventas`/`tickets`.
  Future<int> saveRemoteCajaCierreResumen({
    required Map<String, dynamic> caja,
    required List<Map<String, dynamic>> items,
  }) async {
    await AppDatabase.ensureCajaCierreResumenTable();
    final db = await AppDatabase.instance();

    final codigoCaja = (caja['codigo_caja'] ?? '').toString();
    final disciplina = (caja['disciplina'] ?? '').toString();
    final fechaApertura = (caja['fecha_apertura'] ?? '').toString();
    final eventoFecha = fechaApertura.length >= 10
        ? fechaApertura.substring(0, 10)
        : (caja['fecha'] ?? '').toString();
    if (codigoCaja.isEmpty || disciplina.isEmpty || eventoFecha.isEmpty) {
      throw Exception(
          'Datos insuficientes para guardar cierre: codigo_caja/disciplina/fecha');
    }

    final payload = jsonEncode({
      'caja': caja,
      'items': items,
    });

    final id = await db.insert(
      'caja_cierre_resumen',
      {
        'evento_fecha': eventoFecha,
        'disciplina': disciplina,
        'codigo_caja': codigoCaja,
        'source_device': (caja['source_device'] ?? '').toString(),
        'items_count': items.length,
        'payload': payload,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  /// Importa una caja + items desde Supabase a SQLite para poder verla offline.
  /// Inserta en `caja_diaria` y crea `ventas`+`tickets` mínimos (sin `venta_items`).
  Future<int> importRemoteCajaToLocal({
    required Map<String, dynamic> caja,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await AppDatabase.instance();
    final uuid = const Uuid();
    final codigoCaja = (caja['codigo_caja'] ?? '').toString();
    if (codigoCaja.isEmpty) {
      throw Exception('Caja remota inválida: codigo_caja vacío');
    }

    return await db.transaction<int>((txn) async {
      final existing = await txn.query('caja_diaria',
          columns: ['id'],
          where: 'codigo_caja=?',
          whereArgs: [codigoCaja],
          limit: 1);
      int cajaId;
      if (existing.isNotEmpty) {
        cajaId = existing.first['id'] as int;
      } else {
        final fechaApertura = (caja['fecha_apertura'] ?? '').toString();
        final fecha = fechaApertura.length >= 10
            ? fechaApertura.substring(0, 10)
            : (caja['fecha'] ?? '').toString();
        final hora =
            fechaApertura.length >= 16 ? fechaApertura.substring(11, 16) : '';
        final cierre = (caja['fecha_cierre'] ?? '').toString();
        final horaCierre = cierre.length >= 16 ? cierre.substring(11, 16) : '';

        cajaId = await txn.insert('caja_diaria', {
          'codigo_caja': codigoCaja,
          'disciplina': caja['disciplina'],
          'fecha': fecha,
          'usuario_apertura': (caja['usuario_apertura'] ?? 'import').toString(),
          'cajero_apertura': (caja['cajero_apertura'] ?? 'import').toString(),
          'visible': 1,
          'hora_apertura': hora,
          'apertura_dt': fechaApertura.isNotEmpty ? fechaApertura : null,
          'fondo_inicial': (caja['fondo_inicial'] as num?)?.toDouble() ?? 0.0,
          'conteo_efectivo_final':
              (caja['conteo_efectivo_final'] as num?)?.toDouble(),
          'estado': (caja['estado'] ?? 'CERRADA').toString(),
          'ingresos': (caja['ingresos'] as num?)?.toDouble() ?? 0.0,
          'retiros': (caja['retiros'] as num?)?.toDouble() ?? 0.0,
          'diferencia': (caja['diferencia'] as num?)?.toDouble(),
          'total_tickets': (caja['total_tickets'] as num?)?.toInt(),
          'tickets_anulados': (caja['tickets_anulados'] as num?)?.toInt(),
          'entradas': (caja['entradas'] as num?)?.toInt(),
          'hora_cierre': horaCierre,
          'cierre_dt': cierre.isNotEmpty ? cierre : null,
          'usuario_cierre': (caja['usuario_cierre'] ?? 'import').toString(),
          'cajero_cierre': (caja['cajero_cierre'] ?? 'import').toString(),
          'descripcion_evento': (caja['descripcion_evento'] ?? '').toString(),
          'observaciones_apertura':
              (caja['observaciones_apertura'] ?? '').toString(),
          'obs_cierre': (caja['obs_cierre'] ?? '').toString(),
        });
      }

      final ventaIdByTicket = <String, int>{};
      for (final it in items) {
        final ticketIdRaw = (it['ticket_id'] ?? '').toString();
        final prodId = it['producto_id'];
        final catId = it['categoria_id'];
        final mpId = it['metodo_pago_id'];
        final totalTicket = (it['total_ticket'] as num?)?.toDouble() ??
            (it['total'] as num?)?.toDouble() ??
            0.0;
        final fechaHora =
            (it['fecha_hora'] ?? it['fecha'] ?? caja['fecha_apertura'] ?? '')
                .toString();
        final status = (it['status'] ?? 'No impreso').toString();

        final ident =
            'remote:$codigoCaja#$ticketIdRaw#${(prodId ?? '').toString()}';
        final existsTk = await txn.query('tickets',
            columns: ['id'],
            where: 'identificador_ticket=?',
            whereArgs: [ident],
            limit: 1);
        if (existsTk.isNotEmpty) continue;

        if (mpId is num) {
          final mp = await txn.query('metodos_pago',
              columns: ['id'],
              where: 'id=?',
              whereArgs: [mpId.toInt()],
              limit: 1);
          if (mp.isEmpty) {
            await txn.insert('metodos_pago', {
              'id': mpId.toInt(),
              'descripcion':
                  (it['metodo_pago'] ?? 'MP ${mpId.toInt()}').toString(),
            });
          }
        }
        if (catId is num) {
          final cat = await txn.query('Categoria_Producto',
              columns: ['id'],
              where: 'id=?',
              whereArgs: [catId.toInt()],
              limit: 1);
          if (cat.isEmpty) {
            await txn.insert('Categoria_Producto', {
              'id': catId.toInt(),
              'descripcion':
                  (it['categoria'] ?? 'Categoria ${catId.toInt()}').toString(),
            });
          }
        }
        if (prodId is num) {
          final p = await txn.query('products',
              columns: ['id'],
              where: 'id=?',
              whereArgs: [prodId.toInt()],
              limit: 1);
          if (p.isEmpty) {
            final precio =
                (it['precio_unitario'] as num?)?.toDouble() ?? totalTicket;
            await txn.insert('products', {
              'id': prodId.toInt(),
              'codigo_producto': (it['codigo_producto'] ?? '').toString(),
              'nombre': (it['producto_nombre'] ?? '(Importado)').toString(),
              'precio_venta': precio.round(),
              'categoria_id': catId is num ? catId.toInt() : null,
              'visible': 0,
              'stock_actual': 0,
              'stock_minimo': 0,
            });
          }
        }

        final ticketKey = ticketIdRaw.isEmpty ? ident : ticketIdRaw;
        int ventaId;
        final cached = ventaIdByTicket[ticketKey];
        if (cached != null) {
          ventaId = cached;
        } else {
          final vUuid =
              uuid.v5(Uuid.NAMESPACE_URL, 'remote:$codigoCaja:$ticketKey');
          try {
            ventaId = await txn.insert('ventas', {
              'uuid': vUuid,
              'fecha_hora': fechaHora.isEmpty
                  ? DateTime.now().toIso8601String()
                  : fechaHora,
              'total_venta': totalTicket,
              'status': 'Importado',
              'activo': 1,
              'metodo_pago_id': mpId is num ? mpId.toInt() : null,
              'caja_id': cajaId,
            });
          } catch (_) {
            final v = await txn.query('ventas',
                columns: ['id'], where: 'uuid=?', whereArgs: [vUuid], limit: 1);
            if (v.isEmpty) rethrow;
            ventaId = v.first['id'] as int;
          }
          ventaIdByTicket[ticketKey] = ventaId;
        }

        await txn.insert('tickets', {
          'venta_id': ventaId,
          'categoria_id': catId is num ? catId.toInt() : null,
          'producto_id': prodId is num ? prodId.toInt() : null,
          'fecha_hora':
              fechaHora.isEmpty ? DateTime.now().toIso8601String() : fechaHora,
          'status': status,
          'total_ticket': totalTicket,
          'identificador_ticket': ident,
        });
      }

      return cajaId;
    });
  }

  Future<int> _pushTipo(Database db, String tipo,
      Future<dynamic> Function(List<Map<String, dynamic>> rows) upsert) async {
    final pend = await db.query('sync_outbox',
        where: 'estado=? AND tipo=?',
        whereArgs: ['pending', tipo],
        orderBy: 'id ASC',
        limit: 100);
    if (pend.isEmpty) return 0;
    final ids = <int>[];
    final idsAll = <int>[];
    // Deduplicar por clave de conflicto para evitar error 21000 de PostgREST (solo para upserts con conflicto)
    final List<Map<String, dynamic>> rows;
    if (tipo == 'error') {
      // Para 'error' enviamos todos tal cual (insert sin conflicto)
      rows = [];
      for (final r in pend) {
        rows.add(jsonDecode(r['payload'] as String) as Map<String, dynamic>);
        idsAll.add(r['id'] as int);
      }
    } else {
      String keyFor(Map<String, dynamic> row) {
        if (tipo == 'caja') return (row['codigo_caja'] ?? '').toString();
        // tipo == 'item'
        return [row['codigo_caja'], row['ticket_id'], row['producto_id']]
            .map((e) => (e ?? '').toString())
            .join('|');
      }

      final dedup = <String, Map<String, dynamic>>{};
      for (final r in pend) {
        final payload =
            jsonDecode(r['payload'] as String) as Map<String, dynamic>;
        final k = keyFor(payload);
        // Al recorrer en orden ASC, si aparece nuevamente la misma clave:
        // - Para 'caja': merge (conserva campos de apertura como usuario_apertura y suma los de cierre)
        // - Para 'item': preferimos el último (override)
        if (tipo == 'caja' && dedup.containsKey(k)) {
          dedup[k] = {
            ...dedup[k]!,
            ...payload,
          };
        } else {
          dedup[k] = payload;
        }
        idsAll.add(r['id'] as int);
      }
      rows = dedup.values.toList(growable: false);
    }
    // Para items: asegurar caja_uuid consultando Supabase por codigo_caja
    if (tipo == 'item') {
      // Recolectar códigos
      final codes = <String>{};
      for (final r in rows) {
        final cc = (r['codigo_caja'] ?? '').toString();
        if (cc.isNotEmpty) codes.add(cc);
      }
      if (codes.isNotEmpty) {
        try {
          final res = await _sb
              .from('cajas')
              .select('uuid,codigo_caja')
              .inFilter('codigo_caja', codes.toList());
          final map = <String, String>{};
          for (final e in (res as List)) {
            final m = Map<String, dynamic>.from(e as Map);
            final cc = (m['codigo_caja'] ?? '').toString();
            final uuid = (m['uuid'] ?? '').toString();
            if (cc.isNotEmpty && uuid.isNotEmpty) map[cc] = uuid;
          }
          // Enriquecer cada row con caja_uuid
          for (final r in rows) {
            final cc = (r['codigo_caja'] ?? '').toString();
            final uuid = map[cc];
            if (uuid == null || uuid.isEmpty) {
              throw Exception(
                  'No se encontró uuid en servidor para codigo_caja=$cc');
            }
            r['caja_uuid'] = uuid;
          }
        } catch (e) {
          final msg = e.toString();
          final isNetwork = msg.contains('SocketException') ||
              msg.contains('Failed host lookup') ||
              msg.contains('ClientException');
          if (isNetwork) {
            // Sin conectividad o DNS: no marcamos error ni tocamos la cola. Reintentará en la próxima sync.
            _lastErrors.add('item: uuid mapping pospuesto (sin red)');
            return -1; // abortar ciclo actual de sync
          }
          // Error real (p.ej., datos inexistentes en servidor): loguear y marcar error
          await _logError(db,
              scope: 'push:item:uuid',
              message: 'No se pudo mapear caja_uuid: $e',
              payload: jsonEncode(rows));
          for (final id in idsAll) {
            await db.update(
                'sync_outbox',
                {
                  'estado': 'error',
                  'reintentos': (pend.first['reintentos'] as int) + 1,
                  'last_error': 'No se pudo mapear caja_uuid: $e'
                },
                where: 'id = ?',
                whereArgs: [id]);
          }
          _lastFailItem += rows.length;
          _lastErrors.add('item: no uuid mapping');
          return idsAll.length;
        }
      }
    }

    // Solo enriquecemos con 'enviado_en' para tipos que lo soporten.
    final nowIso = _nowLocalString();
    final enrichedForSend = rows
        .map((e) => tipo == 'item'
            ? {
                ...e,
                'enviado_en': nowIso,
              }
            : e)
        .toList(growable: false);
    ids.addAll(idsAll);
    try {
      await upsert(enrichedForSend);
      await db.update('sync_outbox', {'estado': 'done'},
          where: 'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids);
      if (tipo == 'caja') _lastOkCaja += enrichedForSend.length;
      if (tipo == 'item') _lastOkItem += enrichedForSend.length;
      if (tipo == 'error') _lastOkErrorRows += enrichedForSend.length;
      _lastSyncAt = DateTime.now();
      return ids.length;
    } catch (e) {
      // Si es error transitorio de red, no marcamos error ni modificamos estado; aborta sync actual.
      if (_isTransientNetworkError(e)) {
        _lastErrors.add('$tipo: sin conectividad (pospuesto)');
        return -1; // señal para abortar ciclo
      }
      // Fallback para columnas faltantes en caja_items/cajas (PGRST204): reintentar removiendo columnas opcionales detectadas
      final msg = e.toString();
      bool retried = false;
      if (tipo == 'item' &&
          (msg.contains('PGRST204') || msg.contains('schema cache'))) {
        final optionalCols = <String>[
          // existentes
          'categoria_id', 'codigo_producto', 'updated_at', 'source_device',
          'dispositivo', 'enviado_en',
          // nuevos campos conveniencia
          'fecha',
          'fecha_hora',
          'producto_nombre',
          'product_nombre',
          'categoria',
          'cantidad',
          'precio_unitario',
          'total',
          'total_ticket',
          'metodo_pago',
          'metodo_pago_id'
        ];
        final stripped = enrichedForSend
            .map((m) => Map<String, dynamic>.from(m)
              ..removeWhere((k, v) => optionalCols.contains(k)))
            .toList(growable: false);
        try {
          await upsert(stripped);
          await db.update('sync_outbox', {'estado': 'done'},
              where: 'id IN (${List.filled(ids.length, '?').join(',')})',
              whereArgs: ids);
          _lastOkItem += stripped.length;
          // Intentar extraer la(s) columna(s) que faltan del mensaje
          String detail =
              'item: reintentado sin columnas opcionales por PGRST204';
          try {
            final text = msg;
            final cols = <String>[];
            int idx = 0;
            while (true) {
              final i = text.indexOf('column "', idx);
              if (i < 0) break;
              final j = text.indexOf('"', i + 8);
              if (j < 0) break;
              final name = text.substring(i + 8, j);
              if (name.isNotEmpty) cols.add(name);
              idx = j + 1;
            }
            if (cols.isNotEmpty) {
              detail += ' (faltan: ${cols.join(', ')})';
            }
          } catch (_) {}
          _lastErrors.add(detail);
          retried = true;
        } catch (e2) {
          _lastErrors.add('item: $e2');
        }
      } else if (tipo == 'caja' &&
          (msg.contains('PGRST204') ||
              msg.contains('schema cache') ||
              msg.contains('does not exist') ||
              msg.contains('42703'))) {
        // Columnas opcionales/removibles si el esquema de Supabase no las tiene aún
        // (incluye claves de versiones previas como mov_ingresos_total/mov_retiros_total)
        final optionalColsCaja = <String>[
          'caja_local_id',
          'tickets',
          'total_tickets',
          'tickets_anulados',
          'entradas',
          'updated_at',
          'source_device',
          'dispositivo',
          'enviado_en',
          'ingresos',
          'retiros'
        ];
        final stripped = enrichedForSend
            .map((m) => Map<String, dynamic>.from(m)
              ..removeWhere((k, v) => optionalColsCaja.contains(k)))
            .toList(growable: false);
        try {
          await upsert(stripped);
          await db.update('sync_outbox', {'estado': 'done'},
              where: 'id IN (${List.filled(ids.length, '?').join(',')})',
              whereArgs: ids);
          _lastOkCaja += stripped.length;
          _lastErrors
              .add('caja: reintentado sin columnas opcionales por PGRST204');
          retried = true;
        } catch (e2) {
          _lastErrors.add('caja: $e2');
        }
      }
      if (!retried) {
        await _logError(db,
            scope: 'push:$tipo',
            message: '$e',
            payload: jsonEncode(enrichedForSend));
        await db.update(
            'sync_outbox',
            {
              'estado': 'error',
              'reintentos': (pend.first['reintentos'] as int) + 1,
              'last_error': '$e'
            },
            where: 'id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: ids);
        if (tipo == 'caja') _lastFailCaja += enrichedForSend.length;
        if (tipo == 'item') _lastFailItem += enrichedForSend.length;
        _lastErrors.add('$tipo: $e');
      }
      return ids.length; // contarlos como procesados (quedaron en done o error)
    }
  }

  // Enqueue helpers
  Future<Map<String, dynamic>?> buildCajaCierreResumenPayload(
      Map<String, dynamic> row) async {
    // La tabla remota es un cierre resumido: requiere fecha_cierre NOT NULL.
    final estado = (row['estado'] ?? '').toString().toUpperCase();
    final fechaCierreRaw =
        ((row['fecha_cierre'] ?? row['cierre_dt']) ?? '').toString().trim();
    if (estado != 'CERRADA' || fechaCierreRaw.isEmpty) {
      return null;
    }

    final device = await _deviceInfoString();

    final sp = await SharedPreferences.getInstance();
    final alias = (sp.getString('alias_dispositivo') ?? '').trim();
    final pv = (sp.getString('punto_venta_codigo') ?? '').trim();

    final codigoCaja = (row['codigo_caja'] ?? '').toString();
    final puntoVentaCodigo = pv.isNotEmpty
        ? pv
        : (codigoCaja.contains('-') ? codigoCaja.split('-').first : codigoCaja);
    final aliasDispositivo = alias.isNotEmpty
        ? alias
        : (puntoVentaCodigo.isNotEmpty ? puntoVentaCodigo : 'device');

    final disciplina = (row['disciplina'] ?? '').toString();
    final descripcionEvento = (row['descripcion_evento'] ?? '').toString();

    final fechaAperturaRaw =
        ((row['fecha_apertura'] ?? row['apertura_dt']) ?? '').toString().trim();
    final fecha = (row['fecha'] ?? '').toString().trim();
    final fechaEvento = (fecha.isNotEmpty
            ? fecha
            : (fechaAperturaRaw.length >= 10
                ? fechaAperturaRaw.substring(0, 10)
                : ''))
        .trim();

    String? horaFromDateTimeString(String s) {
      if (s.length < 16) return null;
      // "YYYY-MM-DD HH:MM" o "YYYY-MM-DDTHH:MM"
      final idx = s.indexOf('T') >= 0 ? s.indexOf('T') : s.indexOf(' ');
      if (idx < 0 || idx + 6 > s.length) return null;
      return s.substring(idx + 1, idx + 6);
    }

    String? toLocalTimestampOrNull(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      // Si viene como ISO, puede traer 'Z' o offset. Parseamos y guardamos como timestamp local.
      final dt =
          DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceFirst(' ', 'T'));
      if (dt == null) {
        // último recurso: enviar lo que vino pero sin 'T'
        return s.replaceFirst('T', ' ');
      }
      final l = dt.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
    }

    final fechaAperturaTsLocal = toLocalTimestampOrNull(fechaAperturaRaw);
    final fechaCierreTsLocal = toLocalTimestampOrNull(fechaCierreRaw);

    final totalVentas = (row['total_ventas'] as num?)?.toDouble() ??
        (row['total_venta'] as num?)?.toDouble() ??
        0.0;
    final conteoTransferenciasFinal =
        (row['conteo_transferencias_final'] as num?)?.toDouble() ??
            (row['transferencias_final'] as num?)?.toDouble() ??
            (row['ventas_transferencia'] as num?)?.toDouble() ??
            0.0;
    final ventasTransferencia = conteoTransferenciasFinal;
    final ventasEfectivo = (totalVentas - ventasTransferencia) < 0
        ? 0.0
        : (totalVentas - ventasTransferencia);

    final ticketsEmitidos = (row['tickets'] as num?)?.toInt() ??
        (row['tickets_emitidos'] as num?)?.toInt() ??
        (row['total_tickets'] as num?)?.toInt() ??
        0;
    final ticketsAnulados = (row['tickets_anulados'] as num?)?.toInt() ?? 0;
    final entradasVendidas = (row['entradas'] as num?)?.toInt() ??
        (row['entradas_vendidas'] as num?)?.toInt() ??
        0;
    final ticketPromedio =
        ticketsEmitidos <= 0 ? 0.0 : (totalVentas / ticketsEmitidos);

    return <String, dynamic>{
      'codigo_caja': codigoCaja,
      'estado': 'CERRADA',
      'punto_venta_codigo': puntoVentaCodigo,
      'alias_dispositivo': aliasDispositivo,
      'device_info': device,
      'fecha': fechaEvento,
      'disciplina': disciplina,
      'descripcion_evento': descripcionEvento,
      'hora_apertura': (row['hora_apertura'] ?? '').toString().isNotEmpty
          ? (row['hora_apertura'] ?? '').toString()
          : (horaFromDateTimeString(fechaAperturaRaw) ?? ''),
      // timestamp (sin tz): enviar hora local del dispositivo.
      'fecha_apertura': fechaAperturaTsLocal,
      'cajero_apertura': (row['cajero_apertura'] ?? '').toString(),
      'usuario_apertura': (row['usuario_apertura'] ?? 'admin').toString(),
      'observaciones_apertura':
          (row['observaciones_apertura'] ?? '').toString(),
      'hora_cierre': (row['hora_cierre'] ?? '').toString().isNotEmpty
          ? (row['hora_cierre'] ?? '').toString()
          : (horaFromDateTimeString(fechaCierreRaw) ?? ''),
      // timestamp (sin tz): enviar hora local del dispositivo.
      'fecha_cierre': fechaCierreTsLocal ?? fechaCierreRaw,
      'cajero_cierre': (row['cajero_cierre'] ?? '').toString(),
      'usuario_cierre': (row['usuario_cierre'] ?? 'admin').toString(),
      'obs_cierre': (row['obs_cierre'] ?? '').toString(),
      'fondo_inicial': (row['fondo_inicial'] as num?)?.toDouble() ?? 0.0,
      'conteo_efectivo_final':
          (row['conteo_efectivo_final'] as num?)?.toDouble() ?? 0.0,
      'conteo_transferencias_final': conteoTransferenciasFinal,
      'diferencia': (row['diferencia'] as num?)?.toDouble() ?? 0.0,
      'total_ventas': totalVentas,
      'ventas_efectivo': ventasEfectivo,
      'ventas_transferencia': ventasTransferencia,
      'ingresos': (row['ingresos'] as num?)?.toDouble() ?? 0.0,
      'retiros': (row['retiros'] as num?)?.toDouble() ?? 0.0,
      'tickets_emitidos': ticketsEmitidos,
      'tickets_anulados': ticketsAnulados,
      'entradas_vendidas': entradasVendidas,
      'ticket_promedio': ticketPromedio,
      // Guardar el payload original para auditoría/depuración
      'payload': row,
    };
  }

  Future<void> enqueueCaja(Map<String, dynamic> row) async {
    final payloadForRemote = await buildCajaCierreResumenPayload(row);
    if (payloadForRemote == null) return;

    await enqueueCajaPayload(payloadForRemote);
  }

  Future<void> enqueueCajaPayload(Map<String, dynamic> payloadForRemote) async {
    final db = await AppDatabase.instance();
    final codigoCaja = (payloadForRemote['codigo_caja'] ?? '').toString();
    if (codigoCaja.isEmpty) return;

    await db.insert(
      'sync_outbox',
      {
        'tipo': 'caja',
        'ref': codigoCaja,
        'payload': jsonEncode(payloadForRemote),
        'estado': 'pending',
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> enqueueItem(Map<String, dynamic> row) async {
    final db = await AppDatabase.instance();
    final device = await _deviceInfoString();
    final enriched = {
      ...row,
      'updated_at': _nowLocalString(),
      'source_device': device,
      'dispositivo': 'Celular',
    };
    final ref =
        '${enriched['codigo_caja']}#${enriched['ticket_id']}#${enriched['producto_id']}';
    await db.insert(
      'sync_outbox',
      {
        'tipo': 'item',
        'ref': ref,
        'payload': jsonEncode(enriched),
        'estado': 'pending',
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> enqueueError(
      {required String scope, required String message, String? payload}) async {
    final db = await AppDatabase.instance();
    await _logError(db, scope: scope, message: message, payload: payload);
  }

  Future<void> _logError(Database db,
      {required String scope, required String message, String? payload}) async {
    await db.insert('sync_error_log', {
      'scope': scope,
      'message': message,
      'payload': payload,
      // Guardar hora local del dispositivo para que el log coincida con UI.
      'created_ts': AppDatabase.nowLocalSqlString(),
    });
    // También encolo para enviar a Supabase cuando haya conectividad
    Object? payloadJson;
    if (payload != null) {
      try {
        payloadJson = jsonDecode(payload);
      } catch (_) {
        // Si no es JSON válido, lo mandamos como string (jsonb acepta strings).
        payloadJson = payload;
      }
    }
    await db.insert('sync_outbox', {
      'tipo': 'error',
      'ref': scope,
      'payload': jsonEncode({
        'scope': scope,
        'message': message,
        // En Supabase esto es jsonb.
        'payload': payloadJson,
      }),
    });
  }

  // Estado de sincronización por caja
  Future<({int pending, int errors})> cajaOutboxCounts(
      String codigoCaja) async {
    final db = await AppDatabase.instance();
    final pendCaja = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(1) as c FROM sync_outbox WHERE estado='pending' AND tipo='caja' AND ref=?",
            [codigoCaja])) ??
        0;
    final errCaja = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(1) as c FROM sync_outbox WHERE estado='error' AND tipo='caja' AND ref=?",
            [codigoCaja])) ??
        0;
    return (
      pending: pendCaja,
      errors: errCaja,
    );
  }

  // Plan esperado vs estado de outbox para una caja
  Future<Map<String, int>> cajaSyncPlan(
      {required int cajaId, required String codigoCaja}) async {
    final db = await AppDatabase.instance();
    final expItems = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(1)
      FROM tickets t
      JOIN ventas v ON v.id = t.venta_id
      WHERE v.caja_id = ?
    ''', [cajaId])) ?? 0;

    // Estado del outbox
    final doneCaja = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(1) FROM sync_outbox WHERE tipo='caja' AND ref=? AND estado='done'",
          [codigoCaja],
        )) ??
        0;
    final doneItems = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(1) FROM sync_outbox WHERE tipo='item' AND ref LIKE ? AND estado='done'",
          ["$codigoCaja#%"],
        )) ??
        0;
    // Nota: si quisieras ver pendientes del outbox estrictamente, podés usar estas consultas
    // finales (no utilizadas en el cálculo actual):
    // final pendCajaOb = ...; final pendItemsOb = ...;
    final errCaja = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(1) FROM sync_outbox WHERE tipo='caja' AND ref=? AND estado='error'",
          [codigoCaja],
        )) ??
        0;
    final errItems = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(1) FROM sync_outbox WHERE tipo='item' AND ref LIKE ? AND estado='error'",
          ["$codigoCaja#%"],
        )) ??
        0;

    // Pendientes mostrados = esperados - hechos; si aún no encolamos, se verá todo pendiente.
    final pendingCaja = (1 - doneCaja).clamp(0, 1);
    final pendingItems = (expItems - doneItems);

    return {
      'expectedCaja': 1,
      'expectedItems': expItems,
      'pendingCaja': pendingCaja,
      'pendingItems': pendingItems,
      'errorCaja': errCaja,
      'errorItems': errItems,
      'doneCaja': doneCaja,
      'doneItems': doneItems,
    };
  }

  DateTime? get lastSyncAt => _lastSyncAt;

  Future<String?> lastErrorMessage() async {
    final db = await AppDatabase.instance();
    final r = await db.query('sync_error_log',
        columns: ['message', 'created_ts'],
        orderBy: 'created_ts DESC',
        limit: 1);
    if (r.isEmpty) return null;
    return r.first['message'] as String?;
  }

  Future<String?> cajaLastError(String codigoCaja) async {
    final db = await AppDatabase.instance();
    final r = await db.rawQuery(
      "SELECT last_error FROM sync_outbox WHERE estado='error' AND ((tipo='caja' AND ref=?) OR (tipo='item' AND ref LIKE ?)) ORDER BY id DESC LIMIT 1",
      [codigoCaja, '$codigoCaja#%'],
    );
    if (r.isEmpty) return null;
    return r.first['last_error'] as String?;
  }

  // Resumen de la última corrida de sync
  ({
    int cajasOk,
    int itemsOk,
    int cajasFail,
    int itemsFail,
    int errorRowsOk,
    List<String> errors
  }) lastSyncDetails() {
    return (
      cajasOk: _lastOkCaja,
      itemsOk: _lastOkItem,
      cajasFail: _lastFailCaja,
      itemsFail: _lastFailItem,
      errorRowsOk: _lastOkErrorRows,
      errors: List.unmodifiable(_lastErrors),
    );
  }

  String _nowLocalString() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  // Genera una cadena identificando el dispositivo usando device_info_plus con fallback
  Future<String> _deviceInfoString() async {
    try {
      final info = DeviceInfoPlugin();
      final pkg = await PackageInfo.fromPlatform();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final brand = a.brand;
        final model = a.model;
        final sdk = a.version.sdkInt.toString();
        return 'Android $brand $model (SDK $sdk) • app ${pkg.version}+${pkg.buildNumber}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        final name = i.name;
        final model = i.utsname.machine;
        final sys = i.systemVersion;
        return 'iOS $name $model ($sys) • app ${pkg.version}+${pkg.buildNumber}';
      } else {
        final os = Platform.operatingSystem;
        final osv = Platform.operatingSystemVersion;
        return '$os $osv • app ${pkg.version}+${pkg.buildNumber}';
      }
    } catch (_) {
      final os = Platform.operatingSystem;
      return os;
    }
  }

  /// Sincroniza manualmente un evento (fecha+disciplina) con Supabase.
  ///
  /// Sube (en orden): evento, caja (caja_diaria), ventas, venta_items, tickets, caja_movimiento.
  ///
  /// Reglas:
  /// - NO sincroniza cajas ABIERTAS.
  /// - Si la caja ya existe en Supabase (por `codigo_caja`), se considera "ya subida" y no se re-sube.
  /// - Ante errores: registra en `sync_error_log` y en `app_error_log`.
  Future<EventoSyncReport> syncEventoCompleto({
    required String fecha,
    required String disciplina,
  }) async {
    if (_busy) {
      return EventoSyncReport.failure(
        userMessage:
            'Ya hay una sincronización en curso. Esperá a que termine e intentá de nuevo.',
      );
    }
    _busy = true;

    final nowTs = DateTime.now().millisecondsSinceEpoch;
    try {
      // Asegurar columnas locales de tracking (sin romper instalaciones viejas)
      await AppDatabase.ensureCajaDiariaColumn(
          'sync_estado', "sync_estado TEXT DEFAULT 'PENDIENTE'");
      await AppDatabase.ensureCajaDiariaColumn(
          'sync_last_error', 'sync_last_error TEXT');
      await AppDatabase.ensureCajaDiariaColumn(
          'sync_last_ts', 'sync_last_ts INTEGER');
    } catch (_) {
      // Si falla el ensure, seguimos igual (no debe bloquear la sync)
    }

    // Política: limpiar logs locales antiguos (best-effort, no bloquea).
    try {
      await AppDatabase.purgeOldErrorLogs(months: 6);
    } catch (_) {
      // no-op
    }
    try {
      final hasNet = await hasInternet();
      if (!hasNet) {
        return EventoSyncReport.failure(
          userMessage:
              'No hay conexión a internet. Intentá de nuevo cuando tengas señal.',
        );
      }

      final db = await AppDatabase.instance();
      final cajas = await db.query(
        'caja_diaria',
        where: 'fecha=? AND disciplina=? AND COALESCE(visible,1)=1',
        whereArgs: [fecha, disciplina],
        orderBy: 'apertura_dt ASC, id ASC',
      );

      const stepsPerCaja = 6;
      final cajasCerradas = cajas
          .where(
              (c) => (c['estado'] ?? '').toString().toUpperCase() == 'CERRADA')
          .length;
      final totalSteps = 1 + (cajasCerradas * stepsPerCaja);
      var processed = 0;
      void emit(String stage) {
        final p = processed.clamp(0, totalSteps);
        _progressCtrl
            .add(SyncProgress(processed: p, total: totalSteps, stage: stage));
      }

      emit('inicio');

      final report = EventoSyncReport(
        fecha: fecha,
        disciplina: disciplina,
        cajasEncontradas: cajas.length,
      );

      // 1) Evento (best-effort; si falla, igual intentamos subir cajas)
      final disciplinaIdLocal =
          await _resolveDisciplinaIdLocalByNombre(disciplina);
      final disciplinaIdRemote = disciplinaIdLocal ??
          await _resolveDisciplinaIdRemoteByNombre(disciplina);

      final eventoId = (disciplinaIdRemote == null)
          ? null
          : _eventoIdDeterministico(
              disciplinaId: disciplinaIdRemote, fecha: fecha);
      try {
        if (eventoId != null && disciplinaIdRemote != null) {
          await _ensureEventoRemote(
            eventoId: eventoId,
            disciplinaId: disciplinaIdRemote,
            fechaEvento: fecha,
          );
          report.eventoOk = true;
        } else {
          report.eventoOk = false;
        }
      } catch (e, st) {
        report.eventoOk = false;
        report.errors.add('Evento: $e');
        await _logSyncAndLocalError(
          scope: 'sync.evento.insert',
          error: e,
          stackTrace: st,
          payload: {
            'fecha': fecha,
            'disciplina': disciplina,
            'disciplina_id': disciplinaIdRemote,
            'evento_id': eventoId
          },
          sendRemoteLogs: true,
        );
        // Si no se pudo registrar el evento, seguimos intentando cajas igualmente.
        // (Si la tabla `eventos` no existe aún, esto permitirá igual subir cajas/datos.)
      } finally {
        processed += 1;
        emit('evento');
      }

      // 2) Cajas + dependencias
      for (final caja in cajas) {
        final cajaId = (caja['id'] as num?)?.toInt();
        final codigoCaja = (caja['codigo_caja'] ?? '').toString();
        final estado = (caja['estado'] ?? '').toString().toUpperCase();
        if (cajaId == null || codigoCaja.isEmpty) continue;

        if (estado != 'CERRADA') {
          report.cajasAbiertasOmitidas++;
          continue;
        }

        report.cajasCerradas++;

        final processedBeforeCaja = processed;

        try {
          // Regla: no re-subir si ya existe la caja en Supabase.
          final existingRef = await _fetchRemoteCajaRefByCodigo(codigoCaja);
          if (existingRef != null) {
            report.cajasYaSubidas++;
            await _setCajaSyncStateLocal(
              db,
              cajaId: cajaId,
              estado: 'SINCRONIZADA',
              lastError: null,
              ts: nowTs,
            );
            processed += stepsPerCaja;
            emit('caja_ya_subida');
            continue;
          }

          final cajaRef = await _insertRemoteCajaAndReturnRef(
            caja: caja,
            eventoId: eventoId,
            disciplinaId: disciplinaIdRemote,
          );
          processed += 1;
          emit('caja');

          // Ventas
          final ventas = await db.query(
            'ventas',
            where: 'caja_id=?',
            whereArgs: [cajaId],
            orderBy: 'id ASC',
          );
          final ventasPayload = <Map<String, dynamic>>[];
          for (final v in ventas) {
            final vUuid = (v['uuid'] ?? '').toString();
            if (vUuid.isEmpty) continue;
            ventasPayload.add({
              'uuid': vUuid,
              'caja_id': cajaRef.id,
              'fecha_hora': (v['fecha_hora'] ?? '').toString(),
              'total_venta': (v['total_venta'] as num?)?.toDouble() ?? 0.0,
              'status': (v['status'] ?? '').toString(),
              'activo': (v['activo'] as num?)?.toInt() ?? 1,
              'metodo_pago_id': (v['metodo_pago_id'] as num?)?.toInt(),
            });
          }
          await _insertChunkedWithFallback(
            table: 'ventas',
            rows: ventasPayload,
            optionalCols: const [
              'codigo_caja',
              'caja_id',
              'caja_uuid',
              'status',
              'activo',
              'metodo_pago_id'
            ],
          );
          report.ventasSubidas += ventasPayload.length;
          processed += 1;
          emit('ventas');

          // Mapear ids remotos de ventas (para schemas que usan venta_id int)
          final ventaUuids = ventasPayload
              .map((e) => (e['uuid'] ?? '').toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false);
          final ventaIdByUuid = ventaUuids.isEmpty
              ? <String, int>{}
              : await _ensureRemoteVentaIdByUuid(ventaUuids);

          // Asegurar que los productos referenciados existan en Supabase
          // (previene FK violation al insertar venta_items y tickets)
          final allProductIds = <int>{};
          final prodIdRows = await db.rawQuery('''
            SELECT DISTINCT vi.producto_id
            FROM venta_items vi
            JOIN ventas v ON v.id = vi.venta_id
            WHERE v.caja_id = ? AND vi.producto_id IS NOT NULL
            UNION
            SELECT DISTINCT t.producto_id
            FROM tickets t
            JOIN ventas v ON v.id = t.venta_id
            WHERE v.caja_id = ? AND t.producto_id IS NOT NULL
          ''', [cajaId, cajaId]);
          for (final r in prodIdRows) {
            final pid = (r['producto_id'] as num?)?.toInt();
            if (pid != null) allProductIds.add(pid);
          }
          await _ensureProductosRemote(db, allProductIds);

          // venta_items
          final vItems = await db.rawQuery('''
          SELECT
            vi.id AS local_id,
            vi.venta_id,
            vi.producto_id,
            vi.cantidad,
            vi.precio_unitario,
            vi.subtotal,
            v.uuid AS venta_uuid
          FROM venta_items vi
          JOIN ventas v ON v.id = vi.venta_id
          WHERE v.caja_id = ?
          ORDER BY vi.id ASC
        ''', [cajaId]);
          final itemPayload = <Map<String, dynamic>>[];
          var missingVentaIdForItems = 0;
          for (final it in vItems) {
            final ventaUuid = (it['venta_uuid'] ?? '').toString();
            final localId = (it['local_id'] as num?)?.toInt();
            if (ventaUuid.isEmpty || localId == null) continue;
            final ventaIdRemote = ventaIdByUuid[ventaUuid];
            if (ventaIdRemote == null) {
              missingVentaIdForItems += 1;
              continue;
            }
            itemPayload.add({
              'venta_id': ventaIdRemote,
              'producto_id': (it['producto_id'] as num?)?.toInt(),
              'cantidad': (it['cantidad'] as num?)?.toInt() ?? 0,
              'precio_unitario':
                  (it['precio_unitario'] as num?)?.toDouble() ?? 0.0,
              'subtotal': (it['subtotal'] as num?)?.toDouble() ?? 0.0,
            });
          }
          if (missingVentaIdForItems > 0) {
            throw Exception(
                'No se pudieron resolver ${missingVentaIdForItems} venta_id(s) remotos para venta_items. Verificá policies/RLS de SELECT en tabla ventas (necesario para leer id por uuid).');
          }
          await _insertChunkedWithFallback(
            table: 'venta_items',
            rows: itemPayload,
          );
          report.ventaItemsSubidos += itemPayload.length;
          processed += 1;
          emit('items');

          // tickets
          final tickets = await db.rawQuery('''
          SELECT
            t.id AS local_id,
            t.venta_id,
            t.categoria_id,
            t.producto_id,
            t.fecha_hora,
            t.status,
            t.total_ticket,
            t.identificador_ticket,
            v.uuid AS venta_uuid
          FROM tickets t
          JOIN ventas v ON v.id = t.venta_id
          WHERE v.caja_id = ?
          ORDER BY t.id ASC
        ''', [cajaId]);
          final ticketsPayload = <Map<String, dynamic>>[];
          var missingVentaIdForTickets = 0;
          for (final t in tickets) {
            final ventaUuid = (t['venta_uuid'] ?? '').toString();
            final localId = (t['local_id'] as num?)?.toInt();
            if (ventaUuid.isEmpty || localId == null) continue;
            final ventaIdRemote = ventaIdByUuid[ventaUuid];
            if (ventaIdRemote == null) {
              missingVentaIdForTickets += 1;
              continue;
            }
            ticketsPayload.add({
              'venta_id': ventaIdRemote,
              'categoria_id': (t['categoria_id'] as num?)?.toInt(),
              'producto_id': (t['producto_id'] as num?)?.toInt(),
              'fecha_hora': (t['fecha_hora'] ?? '').toString(),
              'status': (t['status'] ?? '').toString(),
              'total_ticket': (t['total_ticket'] as num?)?.toDouble() ?? 0.0,
              'identificador_ticket':
                  (t['identificador_ticket'] ?? '').toString(),
            });
          }
          if (missingVentaIdForTickets > 0) {
            throw Exception(
                'No se pudieron resolver ${missingVentaIdForTickets} venta_id(s) remotos para tickets. Verificá policies/RLS de SELECT en tabla ventas (necesario para leer id por uuid).');
          }
          await _insertChunkedWithFallback(
            table: 'tickets',
            rows: ticketsPayload,
          );
          report.ticketsSubidos += ticketsPayload.length;
          processed += 1;
          emit('tickets');

          // movimientos
          final movimientos = await db.query(
            'caja_movimiento',
            where: 'caja_id=?',
            whereArgs: [cajaId],
            orderBy: 'id ASC',
          );
          final movPayload = <Map<String, dynamic>>[];
          for (final m in movimientos) {
            final localId = (m['id'] as num?)?.toInt();
            if (localId == null) continue;
            movPayload.add({
              'caja_id': cajaRef.id,
              'tipo': (m['tipo'] ?? '').toString(),
              'monto': (m['monto'] as num?)?.toDouble() ?? 0.0,
              'observacion': (m['observacion'] ?? '').toString(),
              'medio_pago_id': (m['medio_pago_id'] as num?)?.toInt() ?? 1,
              'created_ts': (m['created_ts'] ?? '').toString(),
              'updated_ts': (m['updated_ts'] ?? '').toString(),
            });
          }
          await _insertChunkedWithFallback(
            table: 'caja_movimiento',
            rows: movPayload,
            optionalCols: const ['observacion', 'medio_pago_id', 'created_ts', 'updated_ts'],
          );
          report.movimientosSubidos += movPayload.length;
          processed += 1;
          emit('movimientos');

          await _setCajaSyncStateLocal(
            db,
            cajaId: cajaId,
            estado: 'SINCRONIZADA',
            lastError: null,
            ts: nowTs,
          );
          processed += 1;
          emit('finalizando');
          report.cajasOk++;
        } catch (e, st) {
          report.cajasError++;
          report.errors.add('Caja $codigoCaja: $e');
          await _logSyncAndLocalError(
            scope: 'sync.evento.caja',
            error: e,
            stackTrace: st,
            payload: {
              'fecha': fecha,
              'disciplina': disciplina,
              'caja_id': cajaId,
              'codigo_caja': codigoCaja,
            },
            sendRemoteLogs: true,
          );
          try {
            await _setCajaSyncStateLocal(
              db,
              cajaId: cajaId,
              estado: 'ERROR',
              lastError: e.toString(),
              ts: nowTs,
            );
          } catch (_) {}

          // Para que el progreso no quede “trabado”, avanzamos el bloque de esta caja.
          processed = processedBeforeCaja + stepsPerCaja;
          emit('error');
        }
      }

      report.ok = report.cajasError == 0;
      report.userMessage = report.ok
          ? 'Sincronización completa. Cajas: ${report.cajasOk}/${report.cajasCerradas}.'
          : 'Sincronización incompleta: ${report.cajasError} caja(s) con error.';

      // Política: enviar errores de sync a Supabase SOLO en este flujo manual.
      await _flushPendingSyncErrorLogsToSupabase(db);

      processed = totalSteps;
      emit('final');
      return report;
    } catch (e, st) {
      await _logSyncAndLocalError(
        scope: 'sync.evento.fatal',
        error: e,
        stackTrace: st,
        payload: {'fecha': fecha, 'disciplina': disciplina},
        sendRemoteLogs: true,
      );
      return EventoSyncReport.failure(
        userMessage:
            'No se pudo sincronizar el evento. Revisá el log de errores si persiste.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _ensureEventoRemote({
    required String eventoId,
    required int disciplinaId,
    required String fechaEvento,
  }) async {
    // Evitar insert repetido: intentamos buscar por unique (disciplina_id+fecha_evento)
    try {
      final existing = await _sb
          .from('eventos')
          .select('evento_id')
          .eq('disciplina_id', disciplinaId)
          .eq('fecha_evento', fechaEvento)
          .maybeSingle();
      if (existing != null) return;
    } catch (_) {
      // Si falla el select (tabla/col no existe), intentamos insert igual.
    }

    final payload = <String, dynamic>{
      'evento_id': eventoId,
      'disciplina_id': disciplinaId,
      'fecha_evento': fechaEvento,
    };

    try {
      await _sb.from('eventos').insert(payload);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('23505') || msg.toLowerCase().contains('duplicate')) {
        return;
      }
      rethrow;
    }
  }

  /// Asegura que los productos referenciados por ventas/tickets de una caja
  /// existan en Supabase (tabla `productos`). Si faltan, los sube desde SQLite local.
  /// Esto previene errores de FK al insertar venta_items y tickets.
  Future<void> _ensureProductosRemote(Database db, Set<int> productoIds) async {
    if (productoIds.isEmpty) return;

    final ids = productoIds.toList(growable: false);
    // Verificar cuáles ya existen en Supabase
    final existing = await _sb
        .from('productos')
        .select('id')
        .inFilter('id', ids);
    final existingIds = (existing as List)
        .map((e) => ((e as Map)['id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();

    final missing = ids.where((id) => !existingIds.contains(id)).toList();
    if (missing.isEmpty) return;

    // Leer productos faltantes desde SQLite local
    final localProducts = await db.query(
      'products',
      where: 'id IN (${List.filled(missing.length, '?').join(',')})',
      whereArgs: missing,
    );

    final payload = <Map<String, dynamic>>[];
    for (final p in localProducts) {
      payload.add({
        'id': (p['id'] as num).toInt(),
        'codigo_producto': (p['codigo_producto'] ?? '').toString(),
        'nombre': (p['nombre'] ?? '').toString(),
        'precio_compra': (p['precio_compra'] as num?)?.toInt(),
        'precio_venta': (p['precio_venta'] as num?)?.toInt() ?? 0,
        'stock_actual': (p['stock_actual'] as num?)?.toInt() ?? 0,
        'stock_minimo': (p['stock_minimo'] as num?)?.toInt() ?? 3,
        'orden_visual': (p['orden_visual'] as num?)?.toInt(),
        'categoria_id': (p['categoria_id'] as num?)?.toInt(),
        'visible': (p['visible'] as num?)?.toInt() ?? 1,
        'color': p['color'],
        'imagen': p['imagen'],
      });
    }

    if (payload.isNotEmpty) {
      await _insertChunkedWithFallback(
        table: 'productos',
        rows: payload,
        optionalCols: const [
          'color', 'imagen', 'orden_visual', 'precio_compra',
          'stock_actual', 'stock_minimo',
        ],
      );
    }
  }

  Future<RemoteCajaRef?> _fetchRemoteCajaRefByCodigo(String codigoCaja) async {
    try {
      final res = await _sb
          .from('caja_diaria')
          .select('id')
          .eq('codigo_caja', codigoCaja)
          .maybeSingle();
      if (res == null) return null;
      final m = Map<String, dynamic>.from(res as Map);
      final id = (m['id'] as num?)?.toInt();
      if (id != null) return RemoteCajaRef(id: id);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<RemoteCajaRef> _insertRemoteCajaAndReturnRef({
    required Map<String, dynamic> caja,
    required String? eventoId,
    required int? disciplinaId,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final pv = (sp.getString('punto_venta_codigo') ?? '').trim();
    final aliasCajaDb = pv.isEmpty ? null : await _readAliasCajaFromDb(pv);
    final aliasDispositivo = (sp.getString('alias_dispositivo') ?? '').trim();
    final aliasCaja = ((aliasCajaDb ?? '').trim().isNotEmpty
            ? (aliasCajaDb ?? '').trim()
            : aliasDispositivo)
        .trim();
    final dispositivoId = await _ensureDispositivoId();

    // Totales de movimientos: la fuente canónica es `caja_movimiento`.
    // (En algunas versiones, caja_diaria.ingresos/retiros puede no estar actualizado.)
    var ingresos = 0.0;
    var retiros = 0.0;
    try {
      final localCajaId = (caja['id'] as num?)?.toInt();
      if (localCajaId != null) {
        final db = await AppDatabase.instance();
        final rows = await db.rawQuery('''
          SELECT 
            COALESCE(SUM(CASE WHEN tipo='INGRESO' THEN monto END),0) as ingresos,
            COALESCE(SUM(CASE WHEN tipo='RETIRO' THEN monto END),0) as retiros
          FROM caja_movimiento
          WHERE caja_id = ?
        ''', [localCajaId]);
        final r = rows.first;
        ingresos = (r['ingresos'] as num?)?.toDouble() ?? 0.0;
        retiros = (r['retiros'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {
      // best-effort
    }

    final codigoCaja = (caja['codigo_caja'] ?? '').toString();
    final payload = <String, dynamic>{
      'codigo_caja': codigoCaja,
      'disciplina': (caja['disciplina'] ?? '').toString(),
      'disciplina_id': disciplinaId,
      'fecha': (caja['fecha'] ?? '').toString(),
      'evento_id': eventoId,
      'estado': (caja['estado'] ?? '').toString(),
      // Dispositivo / POS (obligatorio en Supabase vNext)
      'dispositivo_id': dispositivoId,
      'alias_caja': aliasCaja.isNotEmpty ? aliasCaja : null,
      // En vNext este dato viene precargado y no se modifica por el usuario.
      // No derivamos desde codigo_caja para evitar inconsistencias.
      'punto_venta_codigo': pv.isNotEmpty ? pv : null,
      // Campos existentes
      'usuario_apertura': (caja['usuario_apertura'] ?? '').toString(),
      'cajero_apertura': (caja['cajero_apertura'] ?? '').toString(),
      'usuario_cierre': (caja['usuario_cierre'] ?? '').toString(),
      'cajero_cierre': (caja['cajero_cierre'] ?? '').toString(),
      'hora_apertura': (caja['hora_apertura'] ?? '').toString(),
      'apertura_dt': (caja['apertura_dt'] ?? '').toString(),
      'hora_cierre': (caja['hora_cierre'] ?? '').toString(),
      'cierre_dt': (caja['cierre_dt'] ?? '').toString(),
      'descripcion_evento': (caja['descripcion_evento'] ?? '').toString(),
      'observaciones_apertura':
          (caja['observaciones_apertura'] ?? '').toString(),
      'obs_cierre': (caja['obs_cierre'] ?? '').toString(),
      'fondo_inicial': (caja['fondo_inicial'] as num?)?.toDouble() ?? 0.0,
      'conteo_efectivo_final':
          (caja['conteo_efectivo_final'] as num?)?.toDouble(),
      'conteo_transferencias_final':
          (caja['conteo_transferencias_final'] as num?)?.toDouble(),
      'ingresos': ingresos,
      'retiros': retiros,
      'diferencia': (caja['diferencia'] as num?)?.toDouble() ?? 0.0,
      'total_tickets': (caja['total_tickets'] as num?)?.toInt(),
      'tickets_anulados': (caja['tickets_anulados'] as num?)?.toInt(),
      'entradas': (caja['entradas'] as num?)?.toInt(),
    };

    // Insert sin upsert
    try {
      // Preferimos que devuelva uuid si existe.
      final inserted =
          await _sb.from('caja_diaria').insert(payload).select('id').single();
      final m = Map<String, dynamic>.from(inserted as Map);
      final id = (m['id'] as num?)?.toInt();
      if (id != null) return RemoteCajaRef(id: id);
      // fallback: consultar
      final fetched = await _fetchRemoteCajaRefByCodigo(codigoCaja);
      if (fetched == null) {
        throw Exception(
            'No se pudo obtener id/uuid remoto para caja $codigoCaja');
      }
      return fetched;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('23505') || msg.toLowerCase().contains('duplicate')) {
        final fetched = await _fetchRemoteCajaRefByCodigo(codigoCaja);
        if (fetched == null) {
          throw Exception(
              'La caja ya existe en Supabase pero no se pudo leer su clave: $codigoCaja');
        }
        return fetched;
      }
      // Fallback por columnas faltantes
      if (msg.contains('PGRST204') ||
          msg.contains('schema cache') ||
          msg.contains('does not exist') ||
          msg.contains('42703')) {
        final optionalColsCaja = <String>[
          // En caso de que el schema remoto sea más viejo
          'disciplina_id',
          'evento_id',
          'dispositivo_id',
          'alias_caja',
          'punto_venta_codigo',
          'conteo_efectivo_final',
          'conteo_transferencias_final',
          'tickets_anulados',
          'entradas',
        ];
        final stripped = Map<String, dynamic>.from(payload)
          ..removeWhere((k, v) => optionalColsCaja.contains(k));
        final inserted = await _sb
            .from('caja_diaria')
            .insert(stripped)
            .select('id')
            .single();
        final m = Map<String, dynamic>.from(inserted as Map);
        final id = (m['id'] as num?)?.toInt();
        if (id != null) return RemoteCajaRef(id: id);

        final fetched = await _fetchRemoteCajaRefByCodigo(codigoCaja);
        if (fetched == null) {
          throw Exception(
              'No se pudo obtener id/uuid remoto para caja $codigoCaja (fallback)');
        }
        return fetched;
      }
      rethrow;
    }
  }

  Future<Map<String, int>> _fetchRemoteVentaIdByUuids(
      List<String> uuids) async {
    final u = uuids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (u.isEmpty) return {};
    try {
      final res =
          await _sb.from('ventas').select('id,uuid').inFilter('uuid', u);
      final map = <String, int>{};
      for (final e in (res as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final uuid = (m['uuid'] ?? '').toString();
        final id = (m['id'] as num?)?.toInt();
        if (uuid.isNotEmpty && id != null) map[uuid] = id;
      }
      return map;
    } catch (_) {
      // Si la tabla/columna id no existe, devolvemos vacío.
      return {};
    }
  }

  Future<Map<String, int>> _ensureRemoteVentaIdByUuid(
      List<String> uuids) async {
    final u = uuids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (u.isEmpty) return {};

    // 1) Intento batch
    final map = await _fetchRemoteVentaIdByUuids(u);
    if (map.length == u.length) return map;

    // 2) Fallback por uuid (mejor diagnóstico cuando falla el IN/permiso)
    for (final uuid in u) {
      if (map.containsKey(uuid)) continue;
      try {
        final row = await _sb
            .from('ventas')
            .select('id,uuid')
            .eq('uuid', uuid)
            .maybeSingle();
        if (row == null) continue;
        final m = Map<String, dynamic>.from(row as Map);
        final id = (m['id'] as num?)?.toInt();
        final ru = (m['uuid'] ?? '').toString();
        if (id != null && ru.isNotEmpty) map[ru] = id;
      } catch (_) {
        // best-effort
      }
    }

    if (map.isEmpty) {
      // Este mensaje es intencionalmente explícito para diagnóstico en campo.
      throw Exception(
          'No se pudieron leer IDs de ventas en Supabase. Si ves ventas insertadas pero no se pueden SELECTear desde la app, revisá las policies/RLS de SELECT para tabla ventas (o permisos de la API).');
    }

    return map;
  }

  Future<void> _insertChunkedWithFallback({
    required String table,
    required List<Map<String, dynamic>> rows,
    List<String> optionalCols = const [],
    int chunkSize = 200,
  }) async {
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.sublist(i, (i + chunkSize).clamp(0, rows.length));
      try {
        await _sb.from(table).insert(chunk);
      } catch (e) {
        final msg = e.toString();
        // Conflicto por duplicado: interpretamos como ya existente (sin reintentar)
        if (msg.contains('23505') || msg.toLowerCase().contains('duplicate')) {
          continue;
        }
        if (msg.contains('PGRST204') ||
            msg.contains('schema cache') ||
            msg.contains('does not exist') ||
            msg.contains('42703')) {
          // Reintento quitando columnas opcionales
          final stripped = chunk
              .map((m) => Map<String, dynamic>.from(m)
                ..removeWhere((k, v) => optionalCols.contains(k)))
              .toList(growable: false);
          await _sb.from(table).insert(stripped);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _setCajaSyncStateLocal(
    Database db, {
    required int cajaId,
    required String estado,
    required String? lastError,
    required int ts,
  }) async {
    // Si no existe la columna, el update va a fallar; lo capturamos arriba.
    await db.update(
      'caja_diaria',
      {
        'sync_estado': estado,
        'sync_last_error': lastError,
        'sync_last_ts': ts,
      },
      where: 'id=?',
      whereArgs: [cajaId],
    );
  }

  Future<void> _logSyncAndLocalError({
    required String scope,
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?>? payload,
    bool sendRemoteLogs = false,
  }) async {
    try {
      final db = await AppDatabase.instance();
      await _logError(
        db,
        scope: scope,
        message: error.toString(),
        payload: payload == null ? null : jsonEncode(payload),
      );
    } catch (_) {
      // evitar loops
    }
    await AppDatabase.logLocalError(
      scope: scope,
      error: error,
      stackTrace: stackTrace,
      payload: payload,
    );

    // Por decisión de producto: enviar logs remotos SOLO en sync manual.
    if (sendRemoteLogs) {
      await _tryInsertRemoteAppErrorLog(
        scope: scope,
        error: error,
        stackTrace: stackTrace,
        payload: payload,
      );
    }
  }

  Future<void> _flushPendingSyncErrorLogsToSupabase(Database db) async {
    // Envía en batch los errores de sync encolados (tipo='error') a `public.sync_error_log`.
    // Esto se ejecuta SOLO desde el sync manual.
    try {
      await _pushTipo(
          db, 'error', (rows) => _sb.from('sync_error_log').insert(rows));
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _tryInsertRemoteAppErrorLog({
    required String scope,
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?>? payload,
  }) async {
    try {
      // Si no hay conectividad, no insistimos.
      final hasNet = await hasInternet();
      if (!hasNet) return;

      // Supabase schema confirmado:
      // app_error_log(scope text, message text, stacktrace text, payload jsonb, created_ts default now())
      final safePayload = payload == null ? null : _jsonSafe(payload);
      final row = <String, dynamic>{
        'scope': scope,
        'message': error.toString(),
        'stacktrace': stackTrace.toString(),
        'payload': safePayload,
      };

      try {
        await _sb.from('app_error_log').insert(row);
      } catch (e) {
        final msg = e.toString();

        // Si no existe la tabla o el schema cache no está listo, abortamos silenciosamente.
        if (msg.contains('PGRST') ||
            msg.toLowerCase().contains('schema cache') ||
            msg.toLowerCase().contains('does not exist')) {
          return;
        }

        // Intento mínimo (sin payload) por si el problema es el contenido jsonb.
        try {
          await _sb.from('app_error_log').insert({
            'scope': scope,
            'message': error.toString(),
            'stacktrace': stackTrace.toString(),
          });
        } catch (_) {}
      }
    } catch (_) {
      // nunca romper por logging remoto
    }
  }

  Object? _jsonSafe(Object? v) {
    if (v == null) return null;
    if (v is String || v is num || v is bool) return v;
    if (v is DateTime) return v.toIso8601String();
    if (v is Map) {
      final out = <String, Object?>{};
      v.forEach((k, value) {
        out[k.toString()] = _jsonSafe(value);
      });
      return out;
    }
    if (v is Iterable) {
      return v.map(_jsonSafe).toList(growable: false);
    }
    return v.toString();
  }

  String _eventoIdDeterministico(
      {required int disciplinaId, required String fecha}) {
    // UUID v5 determinístico, estable en todos los dispositivos.
    // Usamos namespace fijo (Uuid.NAMESPACE_URL) y una key estable.
    return const Uuid().v5(Uuid.NAMESPACE_URL, 'evento:$disciplinaId:$fecha');
  }

  Future<int?> _resolveDisciplinaIdLocalByNombre(
      String disciplinaNombre) async {
    try {
      final db = await AppDatabase.instance();
      final r = await db.query(
        'disciplinas',
        columns: ['id'],
        where: 'LOWER(nombre)=LOWER(?)',
        whereArgs: [disciplinaNombre.trim()],
        limit: 1,
      );
      if (r.isEmpty) return null;
      return (r.first['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<int?> _resolveDisciplinaIdRemoteByNombre(
      String disciplinaNombre) async {
    try {
      final res = await _sb
          .from('disciplinas')
          .select('id')
          .eq('nombre', disciplinaNombre.trim())
          .maybeSingle();
      if (res == null) return null;
      final m = Map<String, dynamic>.from(res as Map);
      return (m['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<String> _ensureDispositivoId() async {
    final sp = await SharedPreferences.getInstance();
    final existing = (sp.getString('dispositivo_id') ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await sp.setString('dispositivo_id', id);
    return id;
  }

  Future<String?> _readAliasCajaFromDb(String puntoVentaCodigo) async {
    try {
      final db = await AppDatabase.instance();
      final r = await db.query(
        'punto_venta',
        columns: ['alias_caja'],
        where: 'codigo = ?',
        whereArgs: [puntoVentaCodigo],
        limit: 1,
      );
      if (r.isEmpty) return null;
      return (r.first['alias_caja'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }
}

class EventoSyncReport {
  EventoSyncReport({
    required this.fecha,
    required this.disciplina,
    required this.cajasEncontradas,
  });

  final String fecha;
  final String disciplina;

  bool ok = false;
  String userMessage = '';

  bool eventoOk = false;

  final int cajasEncontradas;
  int cajasCerradas = 0;
  int cajasAbiertasOmitidas = 0;
  int cajasOk = 0;
  int cajasError = 0;
  int cajasYaSubidas = 0;

  int ventasSubidas = 0;
  int ventaItemsSubidos = 0;
  int ticketsSubidos = 0;
  int movimientosSubidos = 0;

  final List<String> errors = [];

  static EventoSyncReport failure({required String userMessage}) {
    final r = EventoSyncReport(fecha: '', disciplina: '', cajasEncontradas: 0);
    r.ok = false;
    r.userMessage = userMessage;
    return r;
  }
}

class RemoteCajaRef {
  const RemoteCajaRef({this.uuid, this.id});
  final String? uuid;
  final int? id;
}

class SyncProgress {
  final int processed;
  final int total;
  final String stage; // 'inicio' | 'cajas' | 'items' | 'errores'
  SyncProgress(
      {required this.processed, required this.total, required this.stage});
}
