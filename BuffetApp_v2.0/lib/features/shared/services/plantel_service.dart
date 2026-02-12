import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../../domain/paginated_result.dart';

/// FASE 17.3: Servicio para gestionar entidades del plantel (jugadores, cuerpo técnico)
/// y calcular su situación económica a partir de compromisos asociados.
class PlantelService {
  PlantelService._();
  static final PlantelService instance = PlantelService._();

  // =====================
  // CRUD de Entidades
  // =====================

  /// Crea una nueva entidad del plantel (jugador/técnico).
  /// Validaciones:
  /// - nombre requerido
  /// - rol requerido y válido
  /// - nombre único (no duplicados exactos)
  Future<int> crearEntidad({
    required String nombre,
    required String rol,
    String? observaciones,
    String? fotoUrl,
    String? contacto,
    String? dni,
    String? fechaNacimiento,
    String? alias,
    String? tipoContratacion,
    String? posicion,
  }) async {
    if (nombre.trim().isEmpty) {
      throw Exception('El nombre es requerido');
    }

    const rolesValidos = ['JUGADOR', 'DT', 'AYUDANTE', 'PF', 'OTRO'];
    if (!rolesValidos.contains(rol)) {
      throw Exception('Rol inválido: $rol');
    }

    final db = await AppDatabase.instance();

    // Validar nombre único (case-insensitive)
    final existente = await db.rawQuery(
      'SELECT id FROM entidades_plantel WHERE LOWER(nombre) = ? AND estado_activo = 1',
      [nombre.trim().toLowerCase()],
    );

    if (existente.isNotEmpty) {
      throw Exception('Ya existe una entidad activa con el nombre "$nombre"');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insert('entidades_plantel', {
      'nombre': nombre.trim(),
      'rol': rol,
      'estado_activo': 1,
      'observaciones': observaciones?.trim(),
      'foto_url': fotoUrl?.trim(),
      'contacto': contacto?.trim(),
      'dni': dni?.trim(),
      'fecha_nacimiento': fechaNacimiento,
      'alias': alias?.trim(),
      'tipo_contratacion': tipoContratacion,
      'posicion': posicion,
      'created_ts': now,
      'updated_ts': now,
    });

    return id;
  }

  /// Obtiene una entidad por su ID.
  Future<Map<String, dynamic>?> obtenerEntidad(int id) async {
    final db = await AppDatabase.instance();
    final result = await db.query(
      'entidades_plantel',
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isEmpty ? null : result.first;
  }

  /// Lista todas las entidades del plantel con filtros opcionales.
  /// Parámetros:
  /// - rol: filtra por rol (JUGADOR, DT, etc.)
  /// - soloActivos: si es true, solo trae entidades activas (default: true)
  Future<List<Map<String, dynamic>>> listarEntidades({
    String? rol,
    bool soloActivos = true,
  }) async {
    final db = await AppDatabase.instance();
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (rol != null) {
      where.add('rol = ?');
      whereArgs.add(rol);
    }

    if (soloActivos) {
      where.add('estado_activo = 1');
    }

    return await db.query(
      'entidades_plantel',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'nombre ASC',
    );
  }

  /// FASE 31: Obtener entidades de plantel con paginación
  /// 
  /// [unidadGestionId] - ID de la unidad de gestión (obligatorio)
  /// [page] - Número de página (base 1, default: 1)
  /// [pageSize] - Items por página (default: 50)
  /// [tipo] - Filtro opcional por tipo (JUGADOR/DT/OTRO)
  /// [activo] - Filtro opcional por estado activo (true/false)
  /// [searchText] - Búsqueda en nombre/apellido/DNI (opcional)
  Future<PaginatedResult<Map<String, dynamic>>> getEntidadesPaginadas({
    required int unidadGestionId,
    int page = 1,
    int pageSize = 50,
    String? tipo,
    bool? activo,
    String? searchText,
  }) async {
    try {
      final db = await AppDatabase.instance();
      
      // Construir WHERE clause
      final whereConditions = <String>['unidad_gestion_id = ?'];
      final whereArgs = <dynamic>[unidadGestionId];

      if (tipo != null && tipo.isNotEmpty) {
        whereConditions.add('tipo = ?');
        whereArgs.add(tipo);
      }

      if (activo != null) {
        whereConditions.add('activo = ?');
        whereArgs.add(activo ? 1 : 0);
      }

      if (searchText != null && searchText.isNotEmpty) {
        whereConditions.add('(nombre LIKE ? OR apellido LIKE ? OR dni LIKE ?)');
        final searchPattern = '%$searchText%';
        whereArgs.add(searchPattern);
        whereArgs.add(searchPattern);
        whereArgs.add(searchPattern);
      }

      final whereClause = whereConditions.join(' AND ');

      // Contar total de registros
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM entidades_plantel WHERE $whereClause',
        whereArgs,
      );
      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

      if (totalCount == 0) {
        return PaginatedResult.empty();
      }

      // Obtener items de la página actual
      final offset = (page - 1) * pageSize;
      final items = await db.query(
        'entidades_plantel',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'apellido ASC, nombre ASC',
        limit: pageSize,
        offset: offset,
      );

      final entidades = items.map((row) => Map<String, dynamic>.from(row)).toList();

      return PaginatedResult<Map<String, dynamic>>(
        items: entidades,
        totalCount: totalCount,
        pageSize: pageSize,
        currentPage: page,
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'plantel_service.get_paginadas',
        error: e.toString(),
        stackTrace: stack,
        payload: {
          'unidad_gestion_id': unidadGestionId,
          'page': page,
          'page_size': pageSize,
        },
      );
      return PaginatedResult.empty();
    }
  }

  /// Actualiza los datos de una entidad.
  /// Marca updated_ts automáticamente.
  Future<void> actualizarEntidad(
    int id,
    Map<String, dynamic> cambios,
  ) async {
    if (cambios.isEmpty) return;

    final db = await AppDatabase.instance();

    // Validar que la entidad exista
    final existe = await obtenerEntidad(id);
    if (existe == null) {
      throw Exception('Entidad con ID $id no encontrada');
    }

    // Validar nombre único si se está cambiando
    if (cambios.containsKey('nombre')) {
      final nuevoNombre = (cambios['nombre'] as String).trim();
      if (nuevoNombre.isEmpty) {
        throw Exception('El nombre no puede estar vacío');
      }

      final duplicado = await db.rawQuery(
        'SELECT id FROM entidades_plantel WHERE LOWER(nombre) = ? AND id != ? AND estado_activo = 1',
        [nuevoNombre.toLowerCase(), id],
      );

      if (duplicado.isNotEmpty) {
        throw Exception('Ya existe otra entidad activa con el nombre "$nuevoNombre"');
      }
    }

    // Validar rol si se está cambiando
    if (cambios.containsKey('rol')) {
      const rolesValidos = ['JUGADOR', 'DT', 'AYUDANTE', 'PF', 'OTRO'];
      if (!rolesValidos.contains(cambios['rol'])) {
        throw Exception('Rol inválido: ${cambios['rol']}');
      }
    }

    final mapa = Map<String, dynamic>.from(cambios);
    mapa['updated_ts'] = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'entidades_plantel',
      mapa,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Da de baja una entidad (soft delete).
  /// Validación: no se puede dar de baja si tiene compromisos activos con movimientos esperados.
  Future<void> darDeBajaEntidad(int id) async {
    final db = await AppDatabase.instance();

    // Validar que no tenga compromisos activos con movimientos esperados
    final compromisosActivos = await db.rawQuery(
      'SELECT c.id, c.nombre FROM compromisos c '
      'WHERE c.entidad_plantel_id = ? AND c.activo = 1 AND c.eliminado = 0',
      [id],
    );

    if (compromisosActivos.isNotEmpty) {
      final nombres = compromisosActivos.map((c) => c['nombre']).join(', ');
      throw Exception(
        'No se puede dar de baja porque tiene compromisos activos: $nombres. '
        'Primero pausa o elimina los compromisos asociados.',
      );
    }

    await db.update(
      'entidades_plantel',
      {
        'estado_activo': 0,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Reactiva una entidad dada de baja.
  Future<void> reactivarEntidad(int id) async {
    final db = await AppDatabase.instance();
    await db.update(
      'entidades_plantel',
      {
        'estado_activo': 1,
        'updated_ts': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =====================
  // Cálculos Económicos
  // =====================

  /// Calcula el total mensual comprometido de una entidad.
  /// Suma todos los compromisos activos (recurrentes mensuales) asociados a la entidad.
  /// Solo cuenta compromisos con estado activo=1 y eliminado=0.
  Future<double> calcularTotalMensualPorEntidad(int entidadId) async {
    final db = await AppDatabase.instance();

    final result = await db.rawQuery(
      '''
      SELECT SUM(c.monto) as total
      FROM compromisos c
      WHERE c.entidad_plantel_id = ?
        AND c.activo = 1
        AND c.eliminado = 0
      ''',
      [entidadId],
    );

    if (result.isEmpty || result.first['total'] == null) {
      return 0.0;
    }

    return (result.first['total'] as num).toDouble();
  }

  /// Calcula el estado mensual de una entidad para un mes específico.
  /// Retorna un mapa con:
  /// - totalEsperado: suma de cuotas ESPERADO con fecha_programada en el mes
  /// - pagado: suma de cuotas CONFIRMADO con fecha_programada en el mes
  /// - atrasado: cuotas ESPERADO con fecha_programada < hoy
  Future<Map<String, dynamic>> calcularEstadoMensualPorEntidad(
    int entidadId,
    int year,
    int month,
  ) async {
    final db = await AppDatabase.instance();

    // Primer y último día del mes
    final primerDia = DateTime(year, month, 1);
    final ultimoDia = DateTime(year, month + 1, 0);

    final fechaDesde = '${primerDia.year}-${primerDia.month.toString().padLeft(2, '0')}-${primerDia.day.toString().padLeft(2, '0')}';
    final fechaHasta = '${ultimoDia.year}-${ultimoDia.month.toString().padLeft(2, '0')}-${ultimoDia.day.toString().padLeft(2, '0')}';
    final hoy = DateTime.now();
    final fechaHoy = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';

    // Total ESPERADO del mes: suma de cuotas con fecha_programada en el mes y estado ESPERADO
    final esperadoResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(cc.monto_esperado), 0) as total
      FROM compromiso_cuotas cc
      INNER JOIN compromisos c ON cc.compromiso_id = c.id
      WHERE c.entidad_plantel_id = ?
        AND cc.estado = 'ESPERADO'
        AND cc.fecha_programada BETWEEN ? AND ?
      ''',
      [entidadId, fechaDesde, fechaHasta],
    );

    final esperado = (esperadoResult.first['total'] as num).toDouble();

    // Total PAGADO del mes: suma de cuotas CONFIRMADO con fecha_programada en el mes
    final pagadoResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(cc.monto_real), 0) as total
      FROM compromiso_cuotas cc
      INNER JOIN compromisos c ON cc.compromiso_id = c.id
      WHERE c.entidad_plantel_id = ?
        AND cc.estado = 'CONFIRMADO'
        AND cc.fecha_programada BETWEEN ? AND ?
      ''',
      [entidadId, fechaDesde, fechaHasta],
    );

    final pagado = (pagadoResult.first['total'] as num).toDouble();

    // Total ATRASADO: cuotas ESPERADO con fecha_programada < hoy
    final atrasadoResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(cc.monto_esperado), 0) as total
      FROM compromiso_cuotas cc
      INNER JOIN compromisos c ON cc.compromiso_id = c.id
      WHERE c.entidad_plantel_id = ?
        AND cc.estado = 'ESPERADO'
        AND cc.fecha_programada < ?
      ''',
      [entidadId, fechaHoy],
    );

    final atrasado = (atrasadoResult.first['total'] as num).toDouble();

    // Total comprometido para el mes (esperado + pagado)
    final totalComprometido = esperado + pagado;

    return {
      'totalComprometido': totalComprometido,
      'pagado': pagado,
      'esperado': esperado,
      'atrasado': atrasado,
    };
  }

  /// Lista todos los compromisos asociados a una entidad.
  /// Incluye activos, pausados y eliminados (para historial completo).
  Future<List<Map<String, dynamic>>> listarCompromisosDeEntidad(
    int entidadId,
  ) async {
    final db = await AppDatabase.instance();
    return await db.query(
      'compromisos',
      where: 'entidad_plantel_id = ?',
      whereArgs: [entidadId],
      orderBy: 'activo DESC, created_ts DESC',
    );
  }

  /// Obtiene el historial de pagos confirmados de una entidad en un rango de fechas.
  /// Retorna movimientos CONFIRMADO asociados a compromisos de esta entidad.
  Future<List<Map<String, dynamic>>> obtenerHistorialPagosPorEntidad(
    int entidadId, {
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await AppDatabase.instance();

    final where = <String>['c.entidad_plantel_id = ?', 'em.estado = ?'];
    final whereArgs = <dynamic>[entidadId, 'CONFIRMADO'];

    if (desde != null) {
      final fechaDesde = '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
      where.add('date(em.created_ts / 1000, \'unixepoch\') >= ?');
      whereArgs.add(fechaDesde);
    }

    if (hasta != null) {
      final fechaHasta = '${hasta.year}-${hasta.month.toString().padLeft(2, '0')}-${hasta.day.toString().padLeft(2, '0')}';
      where.add('date(em.created_ts / 1000, \'unixepoch\') <= ?');
      whereArgs.add(fechaHasta);
    }

    return await db.rawQuery(
      '''
      SELECT 
        em.*,
        c.nombre as compromiso_nombre,
        c.categoria,
        c.tipo
      FROM evento_movimiento em
      INNER JOIN compromisos c ON em.compromiso_id = c.id
      WHERE ${where.join(' AND ')}
      ORDER BY em.created_ts DESC
      ''',
      whereArgs,
    );
  }

  /// Obtiene todos los movimientos asociados a una entidad del plantel.
  /// Incluye:
  /// - Movimientos directamente asociados (entidad_plantel_id)
  /// - Movimientos vinculados a través de compromisos
  Future<List<Map<String, dynamic>>> obtenerMovimientosPorEntidad(
    int entidadId, {
    DateTime? desde,
    DateTime? hasta,
    int limit = 100,
  }) async {
    final db = await AppDatabase.instance();

    final where = <String>[];
    final whereArgs = <dynamic>[];

    // Condición: movimientos directos O movimientos de compromisos de esta entidad
    where.add('(em.entidad_plantel_id = ? OR c.entidad_plantel_id = ?)');
    whereArgs.add(entidadId);
    whereArgs.add(entidadId);

    // Solo confirmados (no esperados ni cancelados)
    where.add('em.estado = ?');
    whereArgs.add('CONFIRMADO');

    // No eliminados
    where.add('(em.eliminado IS NULL OR em.eliminado = 0)');

    if (desde != null) {
      final fechaDesde = '${desde.year}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';
      where.add('em.fecha >= ?');
      whereArgs.add(fechaDesde);
    }

    if (hasta != null) {
      final fechaHasta = '${hasta.year}-${hasta.month.toString().padLeft(2, '0')}-${hasta.day.toString().padLeft(2, '0')}';
      where.add('em.fecha <= ?');
      whereArgs.add(fechaHasta);
    }

    return await db.rawQuery(
      '''
      SELECT 
        em.*,
        c.nombre as compromiso_nombre,
        c.categoria as compromiso_categoria,
        c.tipo as compromiso_tipo,
        mp.descripcion as medio_pago_desc
      FROM evento_movimiento em
      LEFT JOIN compromisos c ON em.compromiso_id = c.id
      LEFT JOIN metodos_pago mp ON em.medio_pago_id = mp.id
      WHERE ${where.join(' AND ')}
      ORDER BY em.fecha DESC, em.created_ts DESC
      LIMIT ?
      ''',
      [...whereArgs, limit],
    );
  }

  /// Calcula los montos de movimientos directamente asociados a una entidad en un mes específico.
  /// Retorna un mapa con ingresos y egresos totales.
  Future<Map<String, double>> calcularMovimientosAsociadosPorEntidad(
    int entidadId,
    int year,
    int month,
  ) async {
    final db = await AppDatabase.instance();

    final primerDia = DateTime(year, month, 1);
    final ultimoDia = DateTime(year, month + 1, 0, 23, 59, 59);
    final fechaInicio = DateFormat('yyyy-MM-dd').format(primerDia);
    final fechaFin = DateFormat('yyyy-MM-dd').format(ultimoDia);

    final rows = await db.rawQuery(
      '''
      SELECT 
        tipo,
        SUM(monto) as total
      FROM evento_movimiento
      WHERE entidad_plantel_id = ?
        AND fecha BETWEEN ? AND ?
        AND estado = 'CONFIRMADO'
        AND (eliminado IS NULL OR eliminado = 0)
      GROUP BY tipo
      ''',
      [entidadId, fechaInicio, fechaFin],
    );

    double ingresos = 0.0;
    double egresos = 0.0;

    for (final row in rows) {
      final tipo = row['tipo']?.toString() ?? '';
      final total = (row['total'] as num?)?.toDouble() ?? 0.0;

      if (tipo == 'INGRESO') {
        ingresos = total;
      } else if (tipo == 'EGRESO') {
        egresos = total;
      }
    }

    return {
      'ingresos': ingresos,
      'egresos': egresos,
      'neto': ingresos - egresos,
    };
  }

  /// Calcula un resumen general del plantel completo para un mes específico.
  /// Retorna:
  /// - totalMensualComprometido: suma de todos los compromisos activos
  /// - pagadoEsteMes: suma de movimientos CONFIRMADO del mes
  /// - pendienteEsteMes: diferencia entre comprometido y pagado
  /// - cantidadJugadores: total de jugadores activos
  /// - jugadoresAlDia: cantidad de jugadores que tienen todos sus pagos al día
  /// - cantidadTecnicos: total de DT + AYUDANTE + PF activos
  Future<Map<String, dynamic>> calcularResumenGeneral(
    int year,
    int month,
  ) async {
    // Entidades activas del plantel
    final entidades = await listarEntidades(soloActivos: true);

    double totalComprometido = 0.0;
    double totalPagado = 0.0;
    int jugadoresAlDia = 0;
    int cantidadJugadores = 0;
    int cantidadTecnicos = 0;

    for (final entidad in entidades) {
      final entidadId = entidad['id'] as int;
      final rol = entidad['rol'] as String;

      // Contar por rol
      if (rol == 'JUGADOR') {
        cantidadJugadores++;
      } else if (rol == 'DT' || rol == 'AYUDANTE' || rol == 'PF') {
        cantidadTecnicos++;
      }

      final estado = await calcularEstadoMensualPorEntidad(entidadId, year, month);
      totalComprometido += estado['totalComprometido'] as double;
      totalPagado += estado['pagado'] as double;

      // Considerar "al día" si no tiene pendiente ni atrasado
      if ((estado['esperado'] as double) == 0.0 && (estado['atrasado'] as double) == 0.0) {
        if (rol == 'JUGADOR') {
          jugadoresAlDia++;
        }
      }
    }

    return {
      'totalMensualComprometido': totalComprometido,
      'pagadoEsteMes': totalPagado,
      'pendienteEsteMes': totalComprometido - totalPagado,
      'cantidadJugadores': cantidadJugadores,
      'jugadoresAlDia': jugadoresAlDia,
      'cantidadTecnicos': cantidadTecnicos,
      'totalEntidades': entidades.length,
    };
  }
}
