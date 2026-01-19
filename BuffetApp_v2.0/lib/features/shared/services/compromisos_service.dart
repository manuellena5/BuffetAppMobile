import 'package:sqflite/sqflite.dart';

import '../../../data/dao/db.dart';

/// FASE 13.4: Servicio para gestionar compromisos financieros
/// (obligaciones recurrentes como sueldos, sponsors, seguros).
///
/// Responsabilidades:
/// - CRUD de compromisos
/// - Validaciones de negocio
/// - Cálculos de vencimientos y cuotas
///
/// Reglas:
/// - Solo soft delete (eliminado=1), nunca borrado físico
/// - No desactivar si tiene movimientos ESPERADOS pendientes
/// - fecha_inicio <= fecha_fin
/// - monto > 0
class CompromisosService {
  CompromisosService._();
  static final instance = CompromisosService._();

  /// Crea un nuevo compromiso con validaciones.
  ///
  /// Retorna el ID del compromiso creado.
  ///
  /// Lanza excepción si:
  /// - unidad_gestion_id no existe o está inactiva
  /// - fecha_fin < fecha_inicio
  /// - monto <= 0
  /// - frecuencia no existe en catálogo
  /// - modalidad inválida
  Future<int> crearCompromiso({
    required int unidadGestionId,
    required String nombre,
    required String tipo, // 'INGRESO' | 'EGRESO'
    required String modalidad, // 'PAGO_UNICO' | 'MONTO_TOTAL_CUOTAS' | 'RECURRENTE'
    required double monto,
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
    // Validaciones
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a cero');
    }

    if (!['INGRESO', 'EGRESO'].contains(tipo)) {
      throw ArgumentError('Tipo inválido. Debe ser INGRESO o EGRESO');
    }

    if (!['PAGO_UNICO', 'MONTO_TOTAL_CUOTAS', 'RECURRENTE'].contains(modalidad)) {
      throw ArgumentError('Modalidad inválida. Debe ser PAGO_UNICO, MONTO_TOTAL_CUOTAS o RECURRENTE');
    }

    if (fechaFin != null && fechaFin.compareTo(fechaInicio) < 0) {
      throw ArgumentError('La fecha de fin debe ser posterior a la fecha de inicio');
    }

    // Validación específica por modalidad
    if (modalidad == 'MONTO_TOTAL_CUOTAS' && (cuotas == null || cuotas <= 0)) {
      throw ArgumentError('La modalidad MONTO_TOTAL_CUOTAS requiere cantidad de cuotas válida');
    }

    final db = await AppDatabase.instance();

    // Validar que unidad_gestion existe y está activa
    final unidad = await db.query(
      'unidades_gestion',
      where: 'id = ? AND activo = 1',
      whereArgs: [unidadGestionId],
      limit: 1,
    );
    if (unidad.isEmpty) {
      throw ArgumentError('La unidad de gestión no existe o está inactiva');
    }

    // Validar que frecuencia existe
    final frec = await db.query(
      'frecuencias',
      where: 'codigo = ?',
      whereArgs: [frecuencia],
      limit: 1,
    );
    if (frec.isEmpty) {
      throw ArgumentError('Frecuencia inválida: $frecuencia');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insert('compromisos', {
      'unidad_gestion_id': unidadGestionId,
      'nombre': nombre,
      'tipo': tipo,
      'modalidad': modalidad,
      'monto': monto,
      'frecuencia': frecuencia,
      'frecuencia_dias': frecuenciaDias,
      'cuotas': cuotas,
      'cuotas_confirmadas': 0,
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
  }

  /// Obtiene un compromiso por ID.
  ///
  /// Retorna null si no existe o está eliminado.
  Future<Map<String, dynamic>?> obtenerCompromiso(int id) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      'compromisos',
      where: 'id = ? AND eliminado = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Lista compromisos con filtros opcionales.
  ///
  /// Parámetros:
  /// - [unidadGestionId]: filtrar por unidad de gestión
  /// - [tipo]: filtrar por INGRESO o EGRESO
  /// - [activo]: true = solo activos, false = solo pausados, null = todos
  /// - [incluirEliminados]: incluir compromisos con eliminado=1 (default false)
  ///
  /// Retorna lista ordenada por fecha_inicio DESC.
  Future<List<Map<String, dynamic>>> listarCompromisos({
    int? unidadGestionId,
    String? tipo,
    bool? activo,
    bool incluirEliminados = false,
  }) async {
    final db = await AppDatabase.instance();

    final whereConditions = <String>[];
    final whereArgs = <dynamic>[];

    if (!incluirEliminados) {
      whereConditions.add('eliminado = 0');
    }

    if (unidadGestionId != null) {
      whereConditions.add('unidad_gestion_id = ?');
      whereArgs.add(unidadGestionId);
    }

    if (tipo != null) {
      whereConditions.add('tipo = ?');
      whereArgs.add(tipo);
    }

    if (activo != null) {
      whereConditions.add('activo = ?');
      whereArgs.add(activo ? 1 : 0);
    }

    final where = whereConditions.isEmpty ? null : whereConditions.join(' AND ');

    final rows = await db.query(
      'compromisos',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'fecha_inicio DESC, created_ts DESC',
    );

    return rows;
  }

  /// Actualiza un compromiso existente.
  ///
  /// Solo actualiza los campos proporcionados (no nulls).
  /// Incrementa updated_ts y marca sync_estado como PENDIENTE.
  ///
  /// Retorna cantidad de filas actualizadas (0 o 1).
  Future<int> actualizarCompromiso(
    int id, {
    String? nombre,
    String? tipo,
    String? modalidad,
    double? monto,
    String? frecuencia,
    int? frecuenciaDias,
    int? cuotas,
    String? fechaInicio,
    String? fechaFin,
    String? categoria,
    String? observaciones,
    String? archivoLocalPath,
    String? archivoRemoteUrl,
    String? archivoNombre,
    String? archivoTipo,
    int? archivoSize,
  }) async {
    final db = await AppDatabase.instance();

    // Verificar que existe y no está eliminado
    final existe = await obtenerCompromiso(id);
    if (existe == null) {
      throw ArgumentError('Compromiso no encontrado o eliminado');
    }

    // Validaciones
    if (monto != null && monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a cero');
    }

    if (tipo != null && !['INGRESO', 'EGRESO'].contains(tipo)) {
      throw ArgumentError('Tipo inválido');
    }

    if (modalidad != null && !['PAGO_UNICO', 'MONTO_TOTAL_CUOTAS', 'RECURRENTE'].contains(modalidad)) {
      throw ArgumentError('Modalidad inválida');
    }

    // Validar fechas
    final finalFechaInicio = fechaInicio ?? existe['fecha_inicio'] as String?;
    final finalFechaFin = fechaFin ?? existe['fecha_fin'] as String?;
    if (finalFechaInicio != null &&
        finalFechaFin != null &&
        finalFechaFin.compareTo(finalFechaInicio) < 0) {
      throw ArgumentError('La fecha de fin debe ser posterior a la fecha de inicio');
    }

    // Validar frecuencia
    if (frecuencia != null) {
      final frec = await db.query(
        'frecuencias',
        where: 'codigo = ?',
        whereArgs: [frecuencia],
        limit: 1,
      );
      if (frec.isEmpty) {
        throw ArgumentError('Frecuencia inválida: $frecuencia');
      }
    }

    final updates = <String, dynamic>{
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
      'sync_estado': 'PENDIENTE',
    };

    if (nombre != null) updates['nombre'] = nombre;
    if (tipo != null) updates['tipo'] = tipo;
    if (modalidad != null) updates['modalidad'] = modalidad;
    if (monto != null) updates['monto'] = monto;
    if (frecuencia != null) updates['frecuencia'] = frecuencia;
    if (frecuenciaDias != null) updates['frecuencia_dias'] = frecuenciaDias;
    if (cuotas != null) updates['cuotas'] = cuotas;
    if (fechaInicio != null) updates['fecha_inicio'] = fechaInicio;
    if (fechaFin != null) updates['fecha_fin'] = fechaFin;
    if (categoria != null) updates['categoria'] = categoria;
    if (observaciones != null) updates['observaciones'] = observaciones;
    if (archivoLocalPath != null) updates['archivo_local_path'] = archivoLocalPath;
    if (archivoRemoteUrl != null) updates['archivo_remote_url'] = archivoRemoteUrl;
    if (archivoNombre != null) updates['archivo_nombre'] = archivoNombre;
    if (archivoTipo != null) updates['archivo_tipo'] = archivoTipo;
    if (archivoSize != null) updates['archivo_size'] = archivoSize;

    return await db.update(
      'compromisos',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Pausa un compromiso (activo=0).
  ///
  /// Los movimientos ESPERADOS futuros no se deben mostrar cuando está pausado.
  Future<int> pausarCompromiso(int id) async {
    final db = await AppDatabase.instance();
    return await db.update(
      'compromisos',
      {
        'activo': 0,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
        'sync_estado': 'PENDIENTE',
      },
      where: 'id = ? AND eliminado = 0',
      whereArgs: [id],
    );
  }

  /// Reactiva un compromiso pausado (activo=1).
  Future<int> reactivarCompromiso(int id) async {
    final db = await AppDatabase.instance();
    return await db.update(
      'compromisos',
      {
        'activo': 1,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
        'sync_estado': 'PENDIENTE',
      },
      where: 'id = ? AND eliminado = 0',
      whereArgs: [id],
    );
  }

  /// Desactiva (soft delete) un compromiso (eliminado=1).
  ///
  /// Regla: NO se puede desactivar si tiene movimientos ESPERADOS pendientes.
  ///
  /// Lanza excepción si tiene movimientos ESPERADOS asociados.
  Future<int> desactivarCompromiso(int id) async {
    final db = await AppDatabase.instance();

    // Validar que no tenga movimientos ESPERADOS
    final esperados = await db.query(
      'evento_movimiento',
      where: 'compromiso_id = ? AND estado = ? AND eliminado = 0',
      whereArgs: [id, 'ESPERADO'],
      limit: 1,
    );

    if (esperados.isNotEmpty) {
      throw StateError(
          'No se puede desactivar el compromiso porque tiene movimientos esperados pendientes');
    }

    return await db.update(
      'compromisos',
      {
        'eliminado': 1,
        'activo': 0,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
        'sync_estado': 'PENDIENTE',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Incrementa el contador de cuotas confirmadas.
  ///
  /// Se llama cuando se registra un movimiento CONFIRMADO asociado al compromiso.
  Future<int> incrementarCuotasConfirmadas(int compromisoId) async {
    final db = await AppDatabase.instance();
    return await db.rawUpdate(
      'UPDATE compromisos SET cuotas_confirmadas = cuotas_confirmadas + 1, '
      'updated_ts = ?, sync_estado = ? '
      'WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, 'PENDIENTE', compromisoId],
    );
  }

  /// Cuenta cuotas confirmadas de un compromiso.
  ///
  /// Consulta la cantidad de movimientos CONFIRMADO asociados.
  Future<int> contarCuotasConfirmadas(int compromisoId) async {
    final db = await AppDatabase.instance();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM evento_movimiento '
      'WHERE compromiso_id = ? AND estado = ? AND eliminado = 0',
      [compromisoId, 'CONFIRMADO'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Calcula cuotas restantes de un compromiso.
  ///
  /// Retorna:
  /// - Si tiene cuotas definidas: cuotas - cuotas_confirmadas
  /// - Si no tiene cuotas (null): null (infinitas)
  Future<int?> calcularCuotasRestantes(int compromisoId) async {
    final compromiso = await obtenerCompromiso(compromisoId);
    if (compromiso == null) return null;

    final cuotasTotales = compromiso['cuotas'] as int?;
    if (cuotasTotales == null) return null; // Infinitas

    final confirmadas = await contarCuotasConfirmadas(compromisoId);
    return (cuotasTotales - confirmadas).clamp(0, cuotasTotales);
  }

  /// Calcula el próximo vencimiento de un compromiso.
  ///
  /// Algoritmo:
  /// 1. Obtener último movimiento CONFIRMADO del compromiso
  /// 2. Si no hay, partir de fecha_inicio
  /// 3. Sumar días según frecuencia
  /// 4. Si se excede fecha_fin o cuotas, retornar null
  ///
  /// Retorna null si:
  /// - El compromiso ya está completo (todas las cuotas confirmadas)
  /// - Se excedió la fecha_fin
  /// - El compromiso está pausado o eliminado
  Future<DateTime?> calcularProximoVencimiento(int compromisoId) async {
    final compromiso = await obtenerCompromiso(compromisoId);
    if (compromiso == null) return null;

    // Si está pausado, no hay próximo vencimiento
    if (compromiso['activo'] != 1) return null;

    final cuotasTotales = compromiso['cuotas'] as int?;
    final confirmadas = await contarCuotasConfirmadas(compromisoId);

    // Si ya se completaron todas las cuotas
    if (cuotasTotales != null && confirmadas >= cuotasTotales) {
      return null;
    }

    final db = await AppDatabase.instance();

    // Obtener último movimiento CONFIRMADO
    final ultimoMovimiento = await db.query(
      'evento_movimiento',
      where: 'compromiso_id = ? AND estado = ? AND eliminado = 0',
      whereArgs: [compromisoId, 'CONFIRMADO'],
      orderBy: 'created_ts DESC',
      limit: 1,
    );

    DateTime fechaBase;
    if (ultimoMovimiento.isNotEmpty) {
      // Partir desde el último movimiento
      final createdTs = ultimoMovimiento.first['created_ts'] as int;
      fechaBase = DateTime.fromMillisecondsSinceEpoch(createdTs);
    } else {
      // Partir desde fecha_inicio
      final fechaInicioStr = compromiso['fecha_inicio'] as String;
      fechaBase = DateTime.parse(fechaInicioStr);
    }

    // Obtener días de la frecuencia
    final frecuenciaCodigo = compromiso['frecuencia'] as String;
    int? diasASumar;

    final frecuenciaData = await db.query(
      'frecuencias',
      where: 'codigo = ?',
      whereArgs: [frecuenciaCodigo],
      limit: 1,
    );
    if (frecuenciaData.isNotEmpty) {
      diasASumar = frecuenciaData.first['dias'] as int?;
    }

    if (diasASumar == null || diasASumar <= 0) {
      // Frecuencia UNICA_VEZ: solo un vencimiento (en fecha_inicio)
      if (confirmadas > 0) return null;
      return DateTime.parse(compromiso['fecha_inicio'] as String);
    }

    // Calcular próximo vencimiento
    final proximoVencimiento = fechaBase.add(Duration(days: diasASumar));

    // Validar contra fecha_fin
    final fechaFinStr = compromiso['fecha_fin'] as String?;
    if (fechaFinStr != null) {
      final fechaFin = DateTime.parse(fechaFinStr);
      if (proximoVencimiento.isAfter(fechaFin)) {
        return null; // Ya se excedió la fecha límite
      }
    }

    return proximoVencimiento;
  }

  /// Obtiene compromisos activos con próximo vencimiento en el rango de fechas.
  ///
  /// Útil para mostrar vencimientos del mes.
  Future<List<Map<String, dynamic>>> listarVencimientosEnRango({
    required DateTime desde,
    required DateTime hasta,
    int? unidadGestionId,
  }) async {
    final compromisos = await listarCompromisos(
      unidadGestionId: unidadGestionId,
      activo: true,
    );

    final vencimientos = <Map<String, dynamic>>[];

    for (final compromiso in compromisos) {
      final id = compromiso['id'] as int;
      final proximoVencimiento = await calcularProximoVencimiento(id);

      if (proximoVencimiento != null &&
          !proximoVencimiento.isBefore(desde) &&
          !proximoVencimiento.isAfter(hasta)) {
        vencimientos.add({
          ...compromiso,
          'proximo_vencimiento': proximoVencimiento.toIso8601String(),
        });
      }
    }

    // Ordenar por fecha de vencimiento
    vencimientos.sort((a, b) {
      final fechaA = DateTime.parse(a['proximo_vencimiento'] as String);
      final fechaB = DateTime.parse(b['proximo_vencimiento'] as String);
      return fechaA.compareTo(fechaB);
    });

    return vencimientos;
  }

  /// Sincroniza el contador de cuotas_confirmadas desde la base de datos.
  ///
  /// Útil para corregir inconsistencias.
  Future<int> sincronizarCuotasConfirmadas(int compromisoId) async {
    final confirmadas = await contarCuotasConfirmadas(compromisoId);
    final db = await AppDatabase.instance();
    return await db.update(
      'compromisos',
      {
        'cuotas_confirmadas': confirmadas,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [compromisoId],
    );
  }

  // ===================================================================
  // FASE 13.5: Gestión de cuotas de compromisos
  // ===================================================================

  /// Genera cuotas automáticamente según la modalidad del compromiso.
  ///
  /// Modalidades:
  /// - PAGO_UNICO: genera 1 sola cuota en fecha_inicio
  /// - MONTO_TOTAL_CUOTAS: divide monto total en N cuotas con distribución automática
  /// - RECURRENTE: genera cuotas con monto fijo por período (limitado al año actual)
  ///
  /// Parámetros:
  /// - [compromisoId]: ID del compromiso
  /// - [montosPersonalizados]: lista opcional de montos por cuota (solo para MONTO_TOTAL_CUOTAS)
  ///
  /// Retorna lista de mapas con estructura de cuota (sin insertar en DB).
  Future<List<Map<String, dynamic>>> generarCuotas(
    int compromisoId, {
    List<double>? montosPersonalizados,
    List<String>? fechasPersonalizadas,
  }) async {
    final compromiso = await obtenerCompromiso(compromisoId);
    if (compromiso == null) {
      throw ArgumentError('Compromiso no encontrado');
    }

    final modalidad = compromiso['modalidad'] as String? ?? 'RECURRENTE';
    final monto = compromiso['monto'] as double;
    final fechaInicioStr = compromiso['fecha_inicio'] as String;
    final fechaInicio = DateTime.parse(fechaInicioStr);
    final fechaFinStr = compromiso['fecha_fin'] as String?;
    final frecuencia = compromiso['frecuencia'] as String;
    final frecuenciaDias = compromiso['frecuencia_dias'] as int?;
    
    final cuotas = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final finDeAnioActual = DateTime(now.year, 12, 31, 23, 59, 59);

    switch (modalidad) {
      case 'PAGO_UNICO':
        // Una sola cuota en fecha_inicio
        cuotas.add({
          'numero_cuota': 1,
          'fecha_programada': fechaInicioStr,
          'monto_esperado': monto,
          'estado': 'ESPERADO',
        });
        break;

      case 'MONTO_TOTAL_CUOTAS':
        // Dividir monto total en cuotas
        final cantidadCuotas = compromiso['cuotas'] as int? ?? 1;
        if (cantidadCuotas <= 0) {
          throw ArgumentError('Cantidad de cuotas debe ser mayor a 0');
        }

        // Validar montos personalizados
        if (montosPersonalizados != null) {
          if (montosPersonalizados.length != cantidadCuotas) {
            throw ArgumentError(
                'La cantidad de montos personalizados debe coincidir con la cantidad de cuotas');
          }
          final sumaMontos = montosPersonalizados.reduce((a, b) => a + b);
          if ((sumaMontos - monto).abs() > 0.01) {
            throw ArgumentError(
                'La suma de montos personalizados (\$$sumaMontos) no coincide con el monto total (\$$monto)');
          }
        }
        
        // Validar fechas personalizadas
        if (fechasPersonalizadas != null) {
          if (fechasPersonalizadas.length != cantidadCuotas) {
            throw ArgumentError(
                'La cantidad de fechas personalizadas debe coincidir con la cantidad de cuotas');
          }
        }

        // Calcular monto por cuota (distribución automática)
        final montoPorCuota = monto / cantidadCuotas;

        for (int i = 0; i < cantidadCuotas; i++) {
          String fechaProgramada;
          
          if (fechasPersonalizadas != null && i < fechasPersonalizadas.length) {
            // Usar fecha personalizada
            fechaProgramada = fechasPersonalizadas[i];
          } else {
            // Calcular fecha automáticamente
            final fechaCuota = _calcularProximaFecha(
              fechaInicio,
              frecuencia,
              frecuenciaDias,
              i,
            );
            fechaProgramada = fechaCuota.toIso8601String().split('T')[0];
          }
          
          final montoFinal = montosPersonalizados != null
              ? montosPersonalizados[i]
              : montoPorCuota;

          cuotas.add({
            'numero_cuota': i + 1,
            'fecha_programada': fechaProgramada,
            'monto_esperado': montoFinal,
            'estado': 'ESPERADO',
          });
        }
        break;

      case 'RECURRENTE':
        // Monto fijo por período
        DateTime? fechaFin;
        if (fechaFinStr != null) {
          fechaFin = DateTime.parse(fechaFinStr);
        }

        // Generar cuotas hasta fecha_fin o fin del año actual (lo que sea antes)
        // Si no hay fecha_fin, generar hasta fin del año actual
        DateTime fechaLimite = finDeAnioActual;
        if (fechaFin != null && fechaFin.isBefore(finDeAnioActual)) {
          fechaLimite = fechaFin;
        }

        int numeroCuota = 1;
        DateTime fechaCuota = fechaInicio;

        // Generar cuotas mientras la fecha no supere el límite
        while (fechaCuota.isBefore(fechaLimite) || fechaCuota.isAtSameMomentAs(fechaLimite)) {
          cuotas.add({
            'numero_cuota': numeroCuota,
            'fecha_programada': fechaCuota.toIso8601String().split('T')[0],
            'monto_esperado': monto,
            'estado': 'ESPERADO',
          });

          fechaCuota = _calcularProximaFecha(
            fechaInicio,
            frecuencia,
            frecuenciaDias,
            numeroCuota,
          );
          numeroCuota++;
          
          // Evitar bucle infinito
          if (numeroCuota > 1000) {
            break;
          }
        }
        break;

      default:
        throw ArgumentError('Modalidad inválida: $modalidad');
    }

    return cuotas;
  }

  /// Calcula la próxima fecha según la frecuencia.
  ///
  /// Para frecuencia MENSUAL: suma meses correctamente (evita problema de 30 días)
  /// Para otras frecuencias: suma días según la tabla frecuencias
  ///
  /// [fechaBase]: fecha de inicio
  /// [frecuencia]: código de frecuencia (MENSUAL, SEMANAL, etc.)
  /// [frecuenciaDias]: días de frecuencia personalizada (si aplica)
  /// [iteracion]: número de iteración (0 para la primera, 1 para la segunda, etc.)
  DateTime _calcularProximaFecha(
    DateTime fechaBase,
    String frecuencia,
    int? frecuenciaDias,
    int iteracion,
  ) {
    // Si es la primera iteración, retornar la fecha base
    if (iteracion == 0) {
      return fechaBase;
    }

    // Para frecuencia MENSUAL, sumar meses correctamente
    if (frecuencia == 'MENSUAL') {
      return DateTime(
        fechaBase.year,
        fechaBase.month + iteracion,
        fechaBase.day,
        fechaBase.hour,
        fechaBase.minute,
        fechaBase.second,
      );
    }

    // Para otras frecuencias, calcular días y sumar
    int dias = 0;
    
    switch (frecuencia) {
      case 'DIARIA':
        dias = 1;
        break;
      case 'SEMANAL':
        dias = 7;
        break;
      case 'QUINCENAL':
        dias = 15;
        break;
      case 'BIMESTRAL':
        // 2 meses, aproximadamente
        return DateTime(
          fechaBase.year,
          fechaBase.month + (iteracion * 2),
          fechaBase.day,
        );
      case 'TRIMESTRAL':
        // 3 meses
        return DateTime(
          fechaBase.year,
          fechaBase.month + (iteracion * 3),
          fechaBase.day,
        );
      case 'CUATRIMESTRAL':
        // 4 meses
        return DateTime(
          fechaBase.year,
          fechaBase.month + (iteracion * 4),
          fechaBase.day,
        );
      case 'SEMESTRAL':
        // 6 meses
        return DateTime(
          fechaBase.year,
          fechaBase.month + (iteracion * 6),
          fechaBase.day,
        );
      case 'ANUAL':
        return DateTime(
          fechaBase.year + iteracion,
          fechaBase.month,
          fechaBase.day,
        );
      default:
        dias = 30; // Default mensual
    }

    return fechaBase.add(Duration(days: dias * iteracion));
  }

  /// Guarda cuotas en la base de datos.
  ///
  /// Elimina cuotas existentes del compromiso y guarda las nuevas.
  Future<void> guardarCuotas(
    int compromisoId,
    List<Map<String, dynamic>> cuotas,
  ) async {
    final db = await AppDatabase.instance();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Eliminar cuotas existentes
      await txn.delete(
        'compromiso_cuotas',
        where: 'compromiso_id = ?',
        whereArgs: [compromisoId],
      );

      // Insertar nuevas cuotas
      for (final cuota in cuotas) {
        await txn.insert('compromiso_cuotas', {
          'compromiso_id': compromisoId,
          'numero_cuota': cuota['numero_cuota'],
          'fecha_programada': cuota['fecha_programada'],
          'monto_esperado': cuota['monto_esperado'],
          'estado': cuota['estado'] ?? 'ESPERADO',
          'monto_real': cuota['monto_real'],
          'created_ts': now,
          'updated_ts': now,
        });
      }
    });
  }

  /// Obtiene cuotas de un compromiso.
  ///
  /// Retorna lista ordenada por numero_cuota.
  Future<List<Map<String, dynamic>>> obtenerCuotas(int compromisoId) async {
    final db = await AppDatabase.instance();
    return await db.query(
      'compromiso_cuotas',
      where: 'compromiso_id = ?',
      whereArgs: [compromisoId],
      orderBy: 'numero_cuota ASC',
    );
  }

  /// Actualiza el estado de una cuota.
  Future<int> actualizarEstadoCuota(
    int cuotaId,
    String nuevoEstado, {
    double? montoReal,
  }) async {
    if (!['ESPERADO', 'CONFIRMADO', 'CANCELADO'].contains(nuevoEstado)) {
      throw ArgumentError('Estado inválido: $nuevoEstado');
    }

    final db = await AppDatabase.instance();
    final updates = <String, dynamic>{
      'estado': nuevoEstado,
      'updated_ts': DateTime.now().millisecondsSinceEpoch,
    };

    if (montoReal != null) {
      updates['monto_real'] = montoReal;
    }

    return await db.update(
      'compromiso_cuotas',
      updates,
      where: 'id = ?',
      whereArgs: [cuotaId],
    );
  }

  /// Valida que la suma de montos personalizados coincida con el monto total.
  bool validarSumaMontos(List<double> montos, double montoTotal) {
    final suma = montos.reduce((a, b) => a + b);
    return (suma - montoTotal).abs() <= 0.01; // Tolerancia de 1 centavo
  }

  /// Calcula el monto total pagado de un compromiso (suma de cuotas CONFIRMADAS).
  ///
  /// Retorna la suma del monto_real de todas las cuotas confirmadas.
  /// Si una cuota confirmada no tiene monto_real, usa monto_esperado.
  Future<double> calcularMontoPagado(int compromisoId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      'compromiso_cuotas',
      columns: ['monto_real', 'monto_esperado'],
      where: 'compromiso_id = ? AND estado = ?',
      whereArgs: [compromisoId, 'CONFIRMADO'],
    );

    double total = 0.0;
    for (final row in rows) {
      final montoReal = (row['monto_real'] as num?)?.toDouble();
      final montoEsperado = (row['monto_esperado'] as num?)?.toDouble() ?? 0.0;
      total += (montoReal ?? montoEsperado);
    }

    return total;
  }

  /// Calcula el monto remanente de un compromiso.
  ///
  /// Para PAGO_UNICO y MONTO_TOTAL_CUOTAS: monto total - monto pagado
  /// Para RECURRENTE: suma de monto_esperado de cuotas ESPERADAS
  Future<double> calcularMontoRemanente(int compromisoId) async {
    final compromiso = await obtenerCompromiso(compromisoId);
    if (compromiso == null) return 0.0;

    final modalidad = compromiso['modalidad'] as String?;
    final montoTotal = (compromiso['monto'] as num?)?.toDouble() ?? 0.0;

    if (modalidad == 'RECURRENTE') {
      // Para recurrente, sumar cuotas esperadas
      final db = await AppDatabase.instance();
      final rows = await db.query(
        'compromiso_cuotas',
        columns: ['monto_esperado'],
        where: 'compromiso_id = ? AND estado = ?',
        whereArgs: [compromisoId, 'ESPERADO'],
      );

      double total = 0.0;
      for (final row in rows) {
        total += (row['monto_esperado'] as num?)?.toDouble() ?? 0.0;
      }
      return total;
    } else {
      // Para pago único y monto total en cuotas
      final pagado = await calcularMontoPagado(compromisoId);
      return montoTotal - pagado;
    }
  }
}

