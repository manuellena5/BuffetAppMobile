import 'package:sqflite/sqflite.dart';
import '../../../data/dao/db.dart';

/// FASE 18.3: Servicio para gestión de Acuerdos (reglas/contratos que generan compromisos)
/// 
/// Un acuerdo representa una regla o contrato económico que genera compromisos automáticamente.
/// Ej: Sueldo mensual de un DT, cuota de un jugador, etc.
/// 
/// Jerarquía conceptual:
/// - Acuerdo = regla / contrato / condición repetitiva
/// - Compromiso = expectativa futura concreta
/// - Movimiento = hecho real confirmado
class AcuerdosService {
  /// CRUD BÁSICO
  
  /// Crear un nuevo acuerdo
  /// 
  /// Validaciones:
  /// - unidad_gestion_id debe existir
  /// - fecha_inicio <= fecha_fin (si fecha_fin != null)
  /// - Si modalidad = MONTO_TOTAL_CUOTAS → monto_total y cuotas requeridos
  /// - Si modalidad = RECURRENTE → monto_periodico requerido
  /// - frecuencia debe existir en tabla frecuencias
  /// 
  /// Retorna: id del acuerdo creado
  static Future<int> crearAcuerdo({
    required int unidadGestionId,
    int? entidadPlantelId,
    required String nombre,
    required String tipo, // 'INGRESO' | 'EGRESO'
    required String modalidad, // 'MONTO_TOTAL_CUOTAS' | 'RECURRENTE'
    double? montoTotal,
    double? montoPeriodico,
    required String frecuencia,
    int? frecuenciaDias,
    int? cuotas,
    required String fechaInicio, // YYYY-MM-DD
    String? fechaFin, // YYYY-MM-DD
    required String categoria,
    String? observaciones,
    String? archivoLocalPath,
    String? archivoRemoteUrl,
    String? archivoNombre,
    String? archivoTipo,
    int? archivoSize,
    String? dispositivoId,
  }) async {
    try {
      // Validaciones previas
      if (!['INGRESO', 'EGRESO'].contains(tipo)) {
        throw ArgumentError('Tipo debe ser INGRESO o EGRESO');
      }
      
      if (!['MONTO_TOTAL_CUOTAS', 'RECURRENTE'].contains(modalidad)) {
        throw ArgumentError('Modalidad debe ser MONTO_TOTAL_CUOTAS o RECURRENTE');
      }
      
      if (modalidad == 'MONTO_TOTAL_CUOTAS') {
        if (montoTotal == null || cuotas == null) {
          throw ArgumentError('MONTO_TOTAL_CUOTAS requiere monto_total y cuotas');
        }
        if (montoTotal <= 0 || cuotas <= 0) {
          throw ArgumentError('monto_total y cuotas deben ser mayores a 0');
        }
      }
      
      if (modalidad == 'RECURRENTE') {
        if (montoPeriodico == null) {
          throw ArgumentError('RECURRENTE requiere monto_periodico');
        }
        if (montoPeriodico <= 0) {
          throw ArgumentError('monto_periodico debe ser mayor a 0');
        }
      }
      
      if (fechaFin != null) {
        final inicio = DateTime.parse(fechaInicio);
        final fin = DateTime.parse(fechaFin);
        if (fin.isBefore(inicio)) {
          throw ArgumentError('fecha_fin debe ser >= fecha_inicio');
        }
      }
      
      final db = await AppDatabase.instance();
      
      // Validar que unidad_gestion_id existe
      final unidadExists = await db.query(
        'unidades_gestion',
        where: 'id = ?',
        whereArgs: [unidadGestionId],
      );
      if (unidadExists.isEmpty) {
        throw ArgumentError('unidad_gestion_id $unidadGestionId no existe');
      }
      
      // Validar que entidad_plantel_id existe (si se proporciona)
      if (entidadPlantelId != null) {
        final entidadExists = await db.query(
          'entidades_plantel',
          where: 'id = ?',
          whereArgs: [entidadPlantelId],
        );
        if (entidadExists.isEmpty) {
          throw ArgumentError('entidad_plantel_id $entidadPlantelId no existe');
        }
      }
      
      // Validar que frecuencia existe
      final frecuenciaExists = await db.query(
        'frecuencias',
        where: 'codigo = ?',
        whereArgs: [frecuencia],
      );
      if (frecuenciaExists.isEmpty) {
        throw ArgumentError('frecuencia $frecuencia no existe');
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final id = await db.insert('acuerdos', {
        'unidad_gestion_id': unidadGestionId,
        'entidad_plantel_id': entidadPlantelId,
        'nombre': nombre,
        'tipo': tipo,
        'modalidad': modalidad,
        'monto_total': montoTotal,
        'monto_periodico': montoPeriodico,
        'frecuencia': frecuencia,
        'frecuencia_dias': frecuenciaDias,
        'cuotas': cuotas,
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
        'categoria': categoria,
        'observaciones': observaciones,
        'activo': 1,
        'archivo_local_path': archivoLocalPath,
        'archivo_remote_url': archivoRemoteUrl,
        'archivo_nombre': archivoNombre,
        'archivo_tipo': archivoTipo,
        'archivo_size': archivoSize,
        'dispositivo_id': dispositivoId,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });
      
      return id;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.crear_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'nombre': nombre, 'unidad_gestion_id': unidadGestionId},
      );
      rethrow;
    }
  }
  
  /// Obtener un acuerdo por ID
  static Future<Map<String, dynamic>?> obtenerAcuerdo(int id) async {
    try {
      final db = await AppDatabase.instance();
      final result = await db.query(
        'acuerdos',
        where: 'id = ? AND eliminado = 0',
        whereArgs: [id],
      );
      
      if (result.isEmpty) return null;
      
      return result.first;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.obtener_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      rethrow;
    }
  }
  
  /// Listar acuerdos con filtros opcionales
  static Future<List<Map<String, dynamic>>> listarAcuerdos({
    int? unidadGestionId,
    int? entidadPlantelId,
    String? tipo,
    bool? activo,
    bool incluirEliminados = false,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      final where = <String>[];
      final whereArgs = <dynamic>[];
      
      if (unidadGestionId != null) {
        where.add('unidad_gestion_id = ?');
        whereArgs.add(unidadGestionId);
      }
      
      if (entidadPlantelId != null) {
        where.add('entidad_plantel_id = ?');
        whereArgs.add(entidadPlantelId);
      }
      
      if (tipo != null) {
        where.add('tipo = ?');
        whereArgs.add(tipo);
      }
      
      if (activo != null) {
        where.add('activo = ?');
        whereArgs.add(activo ? 1 : 0);
      }
      
      if (!incluirEliminados) {
        where.add('eliminado = 0');
      }
      
      final result = await db.query(
        'acuerdos',
        where: where.isNotEmpty ? where.join(' AND ') : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'created_ts DESC',
      );
      
      return result;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.listar_acuerdos',
        error: e.toString(),
        stackTrace: stack,
        payload: {
          'unidad_gestion_id': unidadGestionId,
          'tipo': tipo,
          'activo': activo,
        },
      );
      rethrow;
    }
  }
  
  /// Actualizar un acuerdo existente
  /// 
  /// Validación crítica: NO permite editar si el acuerdo tiene compromisos CONFIRMADO
  static Future<void> actualizarAcuerdo({
    required int id,
    String? nombre,
    String? fechaFin,
    String? observaciones,
    String? archivoLocalPath,
    String? archivoRemoteUrl,
    String? archivoNombre,
    String? archivoTipo,
    int? archivoSize,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Validar que el acuerdo existe
      final acuerdo = await obtenerAcuerdo(id);
      if (acuerdo == null) {
        throw ArgumentError('Acuerdo $id no existe');
      }
      
      // REGLA NO NEGOCIABLE: No editar acuerdos con compromisos confirmados
      final compromisosConfirmados = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM compromisos c
        INNER JOIN compromiso_cuotas cc ON cc.compromiso_id = c.id
        WHERE c.acuerdo_id = ? AND cc.estado = 'CONFIRMADO'
      ''', [id]);
      
      final count = (compromisosConfirmados.first['count'] as int?) ?? 0;
      if (count > 0) {
        throw StateError(
          'No se puede editar un acuerdo con compromisos confirmados. '
          'Use finalizar() para cerrar el acuerdo.'
        );
      }
      
      final updates = <String, dynamic>{};
      
      if (nombre != null) updates['nombre'] = nombre;
      if (fechaFin != null) {
        // Validar fecha_fin >= fecha_inicio
        final fechaInicio = DateTime.parse(acuerdo['fecha_inicio'] as String);
        final fechaFinDate = DateTime.parse(fechaFin);
        if (fechaFinDate.isBefore(fechaInicio)) {
          throw ArgumentError('fecha_fin debe ser >= fecha_inicio');
        }
        updates['fecha_fin'] = fechaFin;
      }
      if (observaciones != null) updates['observaciones'] = observaciones;
      if (archivoLocalPath != null) updates['archivo_local_path'] = archivoLocalPath;
      if (archivoRemoteUrl != null) updates['archivo_remote_url'] = archivoRemoteUrl;
      if (archivoNombre != null) updates['archivo_nombre'] = archivoNombre;
      if (archivoTipo != null) updates['archivo_tipo'] = archivoTipo;
      if (archivoSize != null) updates['archivo_size'] = archivoSize;
      
      if (updates.isEmpty) return;
      
      updates['updated_ts'] = DateTime.now().millisecondsSinceEpoch;
      updates['sync_estado'] = 'PENDIENTE';
      
      await db.update(
        'acuerdos',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.actualizar_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      rethrow;
    }
  }
  
  /// Finalizar un acuerdo (marcar como inactivo con fecha_fin = hoy)
  /// 
  /// Útil cuando el acuerdo ya tiene compromisos confirmados y no puede editarse.
  /// Marca activo=0 y establece fecha_fin si no existe.
  static Future<void> finalizarAcuerdo(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      final acuerdo = await obtenerAcuerdo(id);
      if (acuerdo == null) {
        throw ArgumentError('Acuerdo $id no existe');
      }
      
      final now = DateTime.now();
      final today = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      
      await db.update(
        'acuerdos',
        {
          'activo': 0,
          'fecha_fin': acuerdo['fecha_fin'] ?? today,
          'updated_ts': now.millisecondsSinceEpoch,
          'sync_estado': 'PENDIENTE',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.finalizar_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      rethrow;
    }
  }
  
  /// Desactivar un acuerdo (soft delete)
  /// 
  /// Marca eliminado=1 y activo=0.
  /// NO elimina físicamente de la base de datos (política de auditoría).
  static Future<void> desactivarAcuerdo(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      final acuerdo = await obtenerAcuerdo(id);
      if (acuerdo == null) {
        throw ArgumentError('Acuerdo $id no existe');
      }
      
      await db.update(
        'acuerdos',
        {
          'eliminado': 1,
          'activo': 0,
          'updated_ts': DateTime.now().millisecondsSinceEpoch,
          'sync_estado': 'PENDIENTE',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.desactivar_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'id': id},
      );
      rethrow;
    }
  }
  
  /// GENERACIÓN DE COMPROMISOS
  
  /// Generar preview de compromisos que se crearían desde un acuerdo
  /// 
  /// NO inserta en base de datos, solo retorna lista de compromisos simulados.
  /// Útil para mostrar al usuario antes de confirmar.
  /// 
  /// Retorna: Lista de maps con estructura de compromiso
  static Future<List<Map<String, dynamic>>> previewCompromisos(int acuerdoId) async {
    try {
      final acuerdo = await obtenerAcuerdo(acuerdoId);
      if (acuerdo == null) {
        throw ArgumentError('Acuerdo $acuerdoId no existe');
      }
      
      final modalidad = acuerdo['modalidad'] as String;
      final fechaInicio = DateTime.parse(acuerdo['fecha_inicio'] as String);
      final fechaFin = acuerdo['fecha_fin'] != null 
          ? DateTime.parse(acuerdo['fecha_fin'] as String) 
          : null;
      
      final db = await AppDatabase.instance();
      final frecuenciaData = await db.query(
        'frecuencias',
        where: 'codigo = ?',
        whereArgs: [acuerdo['frecuencia']],
      );
      
      if (frecuenciaData.isEmpty) {
        throw StateError('Frecuencia ${acuerdo['frecuencia']} no encontrada');
      }
      
      final frecuenciaDias = frecuenciaData.first['dias'] as int?;
      if (frecuenciaDias == null) {
        throw StateError('Frecuencia ${acuerdo['frecuencia']} no tiene días definidos');
      }
      
      final compromisos = <Map<String, dynamic>>[];
      
      if (modalidad == 'MONTO_TOTAL_CUOTAS') {
        final montoTotal = (acuerdo['monto_total'] as num).toDouble();
        final cuotas = acuerdo['cuotas'] as int;
        final montoCuota = montoTotal / cuotas;
        
        for (int i = 0; i < cuotas; i++) {
          final fechaProgramada = fechaInicio.add(Duration(days: frecuenciaDias * i));
          
          // Si hay fecha_fin, no generar compromisos posteriores
          if (fechaFin != null && fechaProgramada.isAfter(fechaFin)) {
            break;
          }
          
          compromisos.add({
            'numero_cuota': i + 1,
            'fecha_programada': _formatDate(fechaProgramada),
            'monto': montoCuota,
            'nombre': '${acuerdo['nombre']} - Cuota ${i + 1}/$cuotas',
          });
        }
      } else if (modalidad == 'RECURRENTE') {
        final montoPeriodico = (acuerdo['monto_periodico'] as num).toDouble();
        
        var fechaActual = fechaInicio;
        var cuotaNum = 1;
        
        // Generar hasta fecha_fin o máximo 120 cuotas (10 años para prevenir loops infinitos)
        while (cuotaNum <= 120) {
          if (fechaFin != null && fechaActual.isAfter(fechaFin)) {
            break;
          }
          
          compromisos.add({
            'numero_cuota': cuotaNum,
            'fecha_programada': _formatDate(fechaActual),
            'monto': montoPeriodico,
            'nombre': '${acuerdo['nombre']} - ${_formatDate(fechaActual)}',
          });
          
          fechaActual = fechaActual.add(Duration(days: frecuenciaDias));
          cuotaNum++;
        }
      }
      
      return compromisos;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.preview_compromisos',
        error: e.toString(),
        stackTrace: stack,
        payload: {'acuerdo_id': acuerdoId},
      );
      rethrow;
    }
  }
  
  /// Generar compromisos reales en base de datos desde un acuerdo
  /// 
  /// IMPORTANTE: Solo genera compromisos que NO existan aún.
  /// No duplica compromisos ya creados.
  /// 
  /// Retorna: cantidad de compromisos generados
  static Future<int> generarCompromisos(int acuerdoId) async {
    try {
      final db = await AppDatabase.instance();
      final acuerdo = await obtenerAcuerdo(acuerdoId);
      
      if (acuerdo == null) {
        throw ArgumentError('Acuerdo $acuerdoId no existe');
      }
      
      final preview = await previewCompromisos(acuerdoId);
      
      if (preview.isEmpty) {
        return 0;
      }
      
      // Crear el compromiso padre (uno solo para todo el acuerdo)
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final compromisoId = await db.insert('compromisos', {
        'acuerdo_id': acuerdoId,
        'unidad_gestion_id': acuerdo['unidad_gestion_id'],
        'entidad_plantel_id': acuerdo['entidad_plantel_id'],
        'nombre': acuerdo['nombre'],
        'tipo': acuerdo['tipo'],
        'modalidad': acuerdo['modalidad'],
        'monto': acuerdo['modalidad'] == 'MONTO_TOTAL_CUOTAS' 
            ? acuerdo['monto_total'] 
            : acuerdo['monto_periodico'],
        'frecuencia': acuerdo['frecuencia'],
        'frecuencia_dias': acuerdo['frecuencia_dias'],
        'cuotas': preview.length,
        'cuotas_confirmadas': 0,
        'fecha_inicio': acuerdo['fecha_inicio'],
        'fecha_fin': acuerdo['fecha_fin'],
        'categoria': acuerdo['categoria'],
        'observaciones': acuerdo['observaciones'],
        'activo': 1,
        'dispositivo_id': acuerdo['dispositivo_id'],
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });
      
      // Insertar cuotas
      final batch = db.batch();
      
      for (final item in preview) {
        batch.insert('compromiso_cuotas', {
          'compromiso_id': compromisoId,
          'numero_cuota': item['numero_cuota'],
          'fecha_programada': item['fecha_programada'],
          'monto_esperado': item['monto'],
          'estado': 'ESPERADO',
          'created_ts': now,
          'updated_ts': now,
        });
      }
      
      await batch.commit(noResult: true);
      
      return preview.length;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.generar_compromisos',
        error: e.toString(),
        stackTrace: stack,
        payload: {'acuerdo_id': acuerdoId},
      );
      rethrow;
    }
  }
  
  /// Obtener estadísticas de un acuerdo
  /// 
  /// Retorna: {
  ///   'compromisos_generados': int,
  ///   'cuotas_esperadas': int,
  ///   'cuotas_confirmadas': int,
  ///   'cuotas_canceladas': int,
  ///   'monto_total_esperado': double,
  ///   'monto_total_confirmado': double,
  /// }
  static Future<Map<String, dynamic>> obtenerEstadisticasAcuerdo(int acuerdoId) async {
    try {
      final db = await AppDatabase.instance();
      
      final compromisosGenerados = await db.rawQuery('''
        SELECT COUNT(DISTINCT c.id) as count
        FROM compromisos c
        WHERE c.acuerdo_id = ? AND c.eliminado = 0
      ''', [acuerdoId]);
      
      final cuotasStats = await db.rawQuery('''
        SELECT 
          COUNT(*) as total,
          SUM(CASE WHEN estado = 'ESPERADO' THEN 1 ELSE 0 END) as esperadas,
          SUM(CASE WHEN estado = 'CONFIRMADO' THEN 1 ELSE 0 END) as confirmadas,
          SUM(CASE WHEN estado = 'CANCELADO' THEN 1 ELSE 0 END) as canceladas,
          SUM(monto_esperado) as monto_esperado,
          SUM(CASE WHEN estado = 'CONFIRMADO' THEN COALESCE(monto_real, monto_esperado) ELSE 0 END) as monto_confirmado
        FROM compromiso_cuotas cc
        INNER JOIN compromisos c ON c.id = cc.compromiso_id
        WHERE c.acuerdo_id = ?
      ''', [acuerdoId]);
      
      final stats = cuotasStats.first;
      
      return {
        'compromisos_generados': (compromisosGenerados.first['count'] as int?) ?? 0,
        'cuotas_esperadas': (stats['esperadas'] as int?) ?? 0,
        'cuotas_confirmadas': (stats['confirmadas'] as int?) ?? 0,
        'cuotas_canceladas': (stats['canceladas'] as int?) ?? 0,
        'monto_total_esperado': (stats['monto_esperado'] as num?)?.toDouble() ?? 0.0,
        'monto_total_confirmado': (stats['monto_confirmado'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_service.obtener_estadisticas_acuerdo',
        error: e.toString(),
        stackTrace: stack,
        payload: {'acuerdo_id': acuerdoId},
      );
      rethrow;
    }
  }
  
  /// Helper: formatear fecha como YYYY-MM-DD
  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
