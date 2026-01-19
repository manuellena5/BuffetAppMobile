import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart';
import '../../../data/dao/db.dart';

/// Servicio para sincronizar movimientos de Tesorería con Supabase
/// 
/// Características:
/// - Insert-only (no UPDATE, no DELETE)
/// - Soporta adjuntos de archivos en Storage
/// - Maneja estados de sincronización (PENDIENTE → SINCRONIZADA/ERROR)
/// - Usa sync_outbox para reintentos
class TesoreriaSyncService {
  static final TesoreriaSyncService _instance = TesoreriaSyncService._internal();
  factory TesoreriaSyncService() => _instance;
  TesoreriaSyncService._internal();

  final _supabase = Supabase.instance.client;
  final String _bucketName = 'movimientos-adjuntos';

  /// Sincroniza un movimiento individual
  /// 
  /// Retorna:
  /// - true: sincronizado exitosamente
  /// - false: error durante sincronización
  Future<bool> syncMovimiento(int movimientoId) async {
    try {
      final db = await AppDatabase.instance();
      
      // Obtener datos del movimiento
      final movs = await db.rawQuery('''
        SELECT 
          em.*,
          mp.descripcion as medio_pago_desc
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
        WHERE em.id = ?
      ''', [movimientoId]);

      if (movs.isEmpty) {
        throw Exception('Movimiento $movimientoId no encontrado');
      }

      final mov = movs.first;
      
      // Validar que no esté ya sincronizado
      final syncEstado = (mov['sync_estado'] ?? '').toString().toUpperCase();
      if (syncEstado == 'SINCRONIZADA') {
        throw Exception('El movimiento ya está sincronizado');
      }

      // Subir archivo adjunto si existe
      String? archivoUrl;
      final archivoPath = (mov['archivo_local_path'] ?? '').toString();
      if (archivoPath.isNotEmpty && File(archivoPath).existsSync()) {
        archivoUrl = await _uploadArchivo(movimientoId, archivoPath);
      }

      // Preparar payload para Supabase
      final payload = {
        'evento_id': mov['evento_id'],
        'disciplina_id': mov['disciplina_id'],
        'tipo': mov['tipo'],
        'categoria': mov['categoria'],
        'monto': (mov['monto'] as num?)?.toDouble() ?? 0.0,
        'medio_pago_id': mov['medio_pago_id'],
        'observacion': mov['observacion'],
        'archivo_local_path': mov['archivo_local_path'],
        'archivo_remote_url': archivoUrl,
        'archivo_nombre': mov['archivo_nombre'],
        'archivo_tipo': mov['archivo_tipo'],
        'archivo_size': mov['archivo_size'],
        'eliminado': mov['eliminado'] ?? 0,
        'dispositivo_id': mov['dispositivo_id'],
        'sync_estado': 'SINCRONIZADA',
        'created_ts': mov['created_ts'],
        'updated_ts': mov['updated_ts'],
      };

      // Insert en Supabase
      await _supabase
          .from('evento_movimiento')
          .insert(payload);

      // Marcar como sincronizado en local
      await db.update(
        'evento_movimiento',
        {
          'sync_estado': 'SINCRONIZADA',
          'archivo_remote_url': archivoUrl,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [movimientoId],
      );

      // Registrar en sync_outbox como completado
      await _registrarSyncOutbox(
        tipo: 'evento_movimiento',
        ref: movimientoId.toString(),
        estado: 'completed',
      );

      return true;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'tesoreria_sync.syncMovimiento',
        error: e,
        stackTrace: st,
        payload: {'movimientoId': movimientoId},
      );

      // Marcar como ERROR en local
      try {
        final db = await AppDatabase.instance();
        await db.update(
          'evento_movimiento',
          {
            'sync_estado': 'ERROR',
            'updated_ts': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [movimientoId],
        );

        // Registrar en sync_outbox para reintentos
        await _registrarSyncOutbox(
          tipo: 'evento_movimiento',
          ref: movimientoId.toString(),
          estado: 'error',
          error: e.toString(),
        );
      } catch (_) {}

      return false;
    }
  }

  /// Sube un archivo al bucket de Supabase Storage
  /// 
  /// Retorna la URL pública del archivo
  Future<String> _uploadArchivo(int movimientoId, String localPath) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw Exception('Archivo no encontrado: $localPath');
    }

    // Generar nombre único
    final extension = localPath.split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'mov_${movimientoId}_$timestamp.$extension';

    // Leer bytes del archivo
    final bytes = await file.readAsBytes();

    // Subir a Supabase Storage
    await _supabase.storage
        .from(_bucketName)
        .uploadBinary(fileName, bytes);

    // Obtener URL pública
    final publicUrl = _supabase.storage
        .from(_bucketName)
        .getPublicUrl(fileName);

    return publicUrl;
  }

  /// Sincroniza una unidad de gestión
  Future<bool> syncUnidadGestion(int unidadId) async {
    try {
      final db = await AppDatabase.instance();
      
      final unidades = await db.query(
        'unidades_gestion',
        where: 'id = ?',
        whereArgs: [unidadId],
      );

      if (unidades.isEmpty) {
        throw Exception('Unidad de gestión $unidadId no encontrada');
      }

      final unidad = unidades.first;

      // Preparar payload
      final payload = {
        'id': unidad['id'],
        'nombre': unidad['nombre'],
        'tipo': unidad['tipo'],
        'disciplina_ref': unidad['disciplina_ref'],
        'activo': unidad['activo'],
        'created_ts': unidad['created_ts'],
        'updated_ts': unidad['updated_ts'],
      };

      // Upsert en Supabase (por ID)
      await _supabase
          .from('unidades_gestion')
          .upsert(payload);

      return true;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'tesoreria_sync.syncUnidadGestion',
        error: e,
        stackTrace: st,
        payload: {'unidadId': unidadId},
      );
      return false;
    }
  }

  /// Sincroniza todos los movimientos pendientes
  /// 
  /// Retorna un mapa con estadísticas:
  /// - total: cantidad total de movimientos pendientes
  /// - exitosos: cantidad sincronizada correctamente
  /// - fallidos: cantidad con errores
  Future<Map<String, int>> syncMovimientosPendientes() async {
    int total = 0;
    int exitosos = 0;
    int fallidos = 0;

    try {
      final db = await AppDatabase.instance();
      
      // Obtener movimientos pendientes
      final pendientes = await db.query(
        'evento_movimiento',
        where: "sync_estado = 'PENDIENTE' AND eliminado = 0",
        orderBy: 'created_ts ASC',
      );

      total = pendientes.length;

      for (final mov in pendientes) {
        final id = mov['id'] as int?;
        if (id == null) continue;

        final success = await syncMovimiento(id);
        if (success) {
          exitosos++;
        } else {
          fallidos++;
        }
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'tesoreria_sync.syncPendientes',
        error: e,
        stackTrace: st,
      );
    }

    return {
      'total': total,
      'exitosos': exitosos,
      'fallidos': fallidos,
    };
  }

  /// Obtiene la cantidad de movimientos pendientes de sincronizar
  Future<int> contarPendientes() async {
    try {
      final db = await AppDatabase.instance();
      final result = await db.rawQuery(
        "SELECT COUNT(*) as count FROM evento_movimiento WHERE sync_estado = 'PENDIENTE' AND eliminado = 0",
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Registra operación en sync_outbox
  Future<void> _registrarSyncOutbox({
    required String tipo,
    required String ref,
    required String estado,
    String? error,
  }) async {
    try {
      final db = await AppDatabase.instance();
      await db.insert(
        'sync_outbox',
        {
          'tipo': tipo,
          'ref': ref,
          'payload': '',
          'estado': estado,
          'last_error': error,
          'created_ts': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Ignorar errores de logging
    }
  }

  /// Valida conectividad con Supabase
  Future<bool> verificarConexion() async {
    try {
      // Intentar una consulta simple
      await _supabase
          .from('metodos_pago')
          .select('id')
          .limit(1);
      return true;
    } catch (e) {
      return false;
    }
  }
}
