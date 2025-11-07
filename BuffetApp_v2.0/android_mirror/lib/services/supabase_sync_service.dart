import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:sqflite/sqflite.dart';
import '../data/dao/db.dart';
import '../env/supabase_env.dart';

class SupaSyncService {
  SupaSyncService._();
  static final SupaSyncService I = SupaSyncService._();
  static bool _initialized = false;

  SupabaseClient get _sb => Supabase.instance.client;
  Timer? _timer;
  bool _busy = false;
  DateTime? _lastSyncAt;
  // Progreso en vivo de sincronización
  final StreamController<SyncProgress> _progressCtrl = StreamController<SyncProgress>.broadcast();
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
    await Supabase.initialize(url: SupabaseEnv.url, anonKey: SupabaseEnv.anonKey);
    _initialized = true;
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
    final caja = await db.query('caja_diaria', columns: ['codigo_caja'], where: 'id=?', whereArgs: [cajaId], limit: 1);
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

  Future<void> syncNow() async {
    if (_busy) return;
    _busy = true;
    try {
      // Reiniciar métricas de última corrida
      _lastOkCaja = 0; _lastFailCaja = 0; _lastOkItem = 0; _lastFailItem = 0; _lastOkErrorRows = 0; _lastErrors.clear();
      final db = await AppDatabase.instance();
      // Calcular total inicial de pendientes (caja + items + errores)
      final totalPend = (Sqflite.firstIntValue(await db.rawQuery(
                "SELECT COUNT(1) FROM sync_outbox WHERE estado='pending' AND tipo IN ('caja','item','error')")) ?? 0);
      int procesados = 0;
      _progressCtrl.add(SyncProgress(processed: procesados, total: totalPend, stage: 'inicio'));
      // Ejecutar en lotes hasta agotar pendientes
      while (true) {
        int batch = 0;
        batch += await _pushTipo(db, 'caja', (rows) => _sb.from('cajas').upsert(rows, onConflict: 'codigo_caja'));
        if (batch == -1) { _lastErrors.add('sync abort: sin conectividad (cajas)'); break; }
        if (batch > 0) {
          procesados += batch;
          _progressCtrl.add(SyncProgress(processed: procesados, total: totalPend, stage: 'cajas'));
        }
        batch = 0;
        batch += await _pushTipo(db, 'item', (rows) => _sb.from('caja_items').upsert(rows, onConflict: 'codigo_caja,ticket_id,producto_id'));
        if (batch == -1) { _lastErrors.add('sync abort: sin conectividad (items)'); break; }
        if (batch > 0) {
          procesados += batch;
          _progressCtrl.add(SyncProgress(processed: procesados, total: totalPend, stage: 'items'));
        }
        batch = 0;
        batch += await _pushTipo(db, 'error', (rows) => _sb.from('sync_error_log').insert(rows));
        if (batch == -1) { _lastErrors.add('sync abort: sin conectividad (errores)'); break; }
        if (batch > 0) {
          procesados += batch;
          _progressCtrl.add(SyncProgress(processed: procesados, total: totalPend, stage: 'errores'));
        }
        if (batch == 0) {
          // Revisar si quedan pendientes; si no, terminamos
          final remaining = Sqflite.firstIntValue(await db.rawQuery(
              "SELECT COUNT(1) FROM sync_outbox WHERE estado='pending' AND tipo IN ('caja','item','error')")) ?? 0;
          if (remaining == 0) break;
        }
      }
      _lastSyncAt = DateTime.now();
    } finally {
      _busy = false;
    }
  }

  Future<int> _pushTipo(Database db, String tipo, Future<dynamic> Function(List<Map<String, dynamic>> rows) upsert) async {
    final pend = await db.query('sync_outbox', where: 'estado=? AND tipo=?', whereArgs: ['pending', tipo], orderBy: 'id ASC', limit: 100);
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
        final payload = jsonDecode(r['payload'] as String) as Map<String, dynamic>;
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
              throw Exception('No se encontró uuid en servidor para codigo_caja=$cc');
            }
            r['caja_uuid'] = uuid;
          }
        } catch (e) {
          final msg = e.toString();
          final isNetwork = msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('ClientException');
          if (isNetwork) {
            // Sin conectividad o DNS: no marcamos error ni tocamos la cola. Reintentará en la próxima sync.
            _lastErrors.add('item: uuid mapping pospuesto (sin red)');
            return -1; // abortar ciclo actual de sync
          }
          // Error real (p.ej., datos inexistentes en servidor): loguear y marcar error
          await _logError(db, scope: 'push:item:uuid', message: 'No se pudo mapear caja_uuid: $e', payload: jsonEncode(rows));
          for (final id in idsAll) {
            await db.update('sync_outbox', {
              'estado': 'error',
              'reintentos': (pend.first['reintentos'] as int) + 1,
              'last_error': 'No se pudo mapear caja_uuid: $e'
            }, where: 'id = ?', whereArgs: [id]);
          }
          _lastFailItem += rows.length;
          _lastErrors.add('item: no uuid mapping');
          return idsAll.length;
        }
      }
    }

    // enriquecer con enviado_en (hora local del dispositivo) al momento de sincronizar
    final nowIso = _nowLocalString();
    final enrichedForSend = rows
        .map((e) => {
              ...e,
              'enviado_en': nowIso,
            })
        .toList(growable: false);
    ids.addAll(idsAll);
    try {
      await upsert(enrichedForSend);
      await db.update('sync_outbox', {'estado': 'done'}, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
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
      if (tipo == 'item' && (msg.contains('PGRST204') || msg.contains('schema cache'))) {
        final optionalCols = <String>[
          // existentes
          'categoria_id','codigo_producto','updated_at','source_device','dispositivo','enviado_en',
          // nuevos campos conveniencia
          'fecha','fecha_hora','producto_nombre','product_nombre','categoria','cantidad','precio_unitario','total','total_ticket','metodo_pago','metodo_pago_id'
        ];
        final stripped = enrichedForSend
            .map((m) => Map<String, dynamic>.from(m)..removeWhere((k, v) => optionalCols.contains(k)))
            .toList(growable: false);
        try {
          await upsert(stripped);
          await db.update('sync_outbox', {'estado': 'done'}, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
          _lastOkItem += stripped.length;
          // Intentar extraer la(s) columna(s) que faltan del mensaje
          String detail = 'item: reintentado sin columnas opcionales por PGRST204';
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
      } else if (tipo == 'caja' && (msg.contains('PGRST204') || msg.contains('schema cache'))) {
        // Columnas opcionales/removibles si el esquema de Supabase no las tiene aún
        // (incluye claves de versiones previas como mov_ingresos_total/mov_retiros_total)
        final optionalColsCaja = <String>[
          'caja_local_id','tickets','tickets_anulados','entradas','updated_at','source_device','dispositivo','enviado_en',
          'ingresos','retiros'
        ];
        final stripped = enrichedForSend
            .map((m) => Map<String, dynamic>.from(m)..removeWhere((k, v) => optionalColsCaja.contains(k)))
            .toList(growable: false);
        try {
          await upsert(stripped);
          await db.update('sync_outbox', {'estado': 'done'}, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
          _lastOkCaja += stripped.length;
          _lastErrors.add('caja: reintentado sin columnas opcionales por PGRST204');
          retried = true;
        } catch (e2) {
          _lastErrors.add('caja: $e2');
        }
      }
      if (!retried) {
        await _logError(db, scope: 'push:$tipo', message: '$e', payload: jsonEncode(enrichedForSend));
        await db.update('sync_outbox', {
          'estado': 'error',
          'reintentos': (pend.first['reintentos'] as int) + 1,
          'last_error': '$e'
        }, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
        if (tipo == 'caja') _lastFailCaja += enrichedForSend.length;
        if (tipo == 'item') _lastFailItem += enrichedForSend.length;
        _lastErrors.add('$tipo: $e');
      }
      return ids.length; // contarlos como procesados (quedaron en done o error)
    }
  }

  // Enqueue helpers
  Future<void> enqueueCaja(Map<String, dynamic> row) async {
    final db = await AppDatabase.instance();
    final device = await _deviceInfoString();
    final enriched = {
      ...row,
      'updated_at': _nowLocalString(),
      'source_device': device,
      'dispositivo': 'Celular',
    };
    await db.insert(
      'sync_outbox',
      {
        'tipo': 'caja',
        'ref': enriched['codigo_caja'] as String,
        'payload': jsonEncode(enriched),
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
    final ref = '${enriched['codigo_caja']}#${enriched['ticket_id']}#${enriched['producto_id']}';
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

  Future<void> enqueueError({required String scope, required String message, String? payload}) async {
    final db = await AppDatabase.instance();
    await _logError(db, scope: scope, message: message, payload: payload);
  }

  Future<void> _logError(Database db, {required String scope, required String message, String? payload}) async {
    await db.insert('sync_error_log', {
      'scope': scope,
      'message': message,
      'payload': payload,
    });
    // También encolo para enviar a Supabase cuando haya conectividad
    await db.insert('sync_outbox', {
      'tipo': 'error',
      'ref': scope,
      'payload': jsonEncode({
        'scope': scope,
        'message': message,
        'payload': payload != null ? jsonDecode(payload) : null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
    });
  }

  // Estado de sincronización por caja
  Future<(int pending, int errors)> cajaOutboxCounts(String codigoCaja) async {
    final db = await AppDatabase.instance();
    final pendCaja = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(1) as c FROM sync_outbox WHERE estado='pending' AND tipo='caja' AND ref=?",
        [codigoCaja])) ?? 0;
  final pendItems = Sqflite.firstIntValue(await db.rawQuery(
    "SELECT COUNT(1) as c FROM sync_outbox WHERE estado='pending' AND tipo='item' AND ref LIKE ?",
    ['$codigoCaja#%'])) ?? 0;
    final errCaja = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(1) as c FROM sync_outbox WHERE estado='error' AND tipo='caja' AND ref=?",
        [codigoCaja])) ?? 0;
  final errItems = Sqflite.firstIntValue(await db.rawQuery(
    "SELECT COUNT(1) as c FROM sync_outbox WHERE estado='error' AND tipo='item' AND ref LIKE ?",
    ['$codigoCaja#%'])) ?? 0;
    return (pendCaja + pendItems, errCaja + errItems);
  }

  // Plan esperado vs estado de outbox para una caja
  Future<Map<String, int>> cajaSyncPlan({required int cajaId, required String codigoCaja}) async {
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
    )) ?? 0;
    final doneItems = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(1) FROM sync_outbox WHERE tipo='item' AND ref LIKE ? AND estado='done'",
      ["$codigoCaja#%"],
    )) ?? 0;
    // Nota: si quisieras ver pendientes del outbox estrictamente, podés usar estas consultas
    // finales (no utilizadas en el cálculo actual):
    // final pendCajaOb = ...; final pendItemsOb = ...;
    final errCaja = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(1) FROM sync_outbox WHERE tipo='caja' AND ref=? AND estado='error'",
      [codigoCaja],
    )) ?? 0;
    final errItems = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(1) FROM sync_outbox WHERE tipo='item' AND ref LIKE ? AND estado='error'",
      ["$codigoCaja#%"],
    )) ?? 0;

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
    final r = await db.query('sync_error_log', columns: ['message','created_ts'], orderBy: 'created_ts DESC', limit: 1);
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
  ({int cajasOk, int itemsOk, int cajasFail, int itemsFail, int errorRowsOk, List<String> errors}) lastSyncDetails() {
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
}

class SyncProgress {
  final int processed;
  final int total;
  final String stage; // 'inicio' | 'cajas' | 'items' | 'errores'
  SyncProgress({required this.processed, required this.total, required this.stage});
}
