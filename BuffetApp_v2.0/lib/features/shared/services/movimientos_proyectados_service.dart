import '../../../data/dao/db.dart';
import 'compromisos_service.dart';

/// FASE 13.5: Servicio para calcular movimientos esperados dinámicamente.
///
/// Responsabilidades:
/// - Calcular movimientos proyectados a partir de compromisos activos
/// - Generar vencimientos según frecuencia
/// - Filtrar por rango de fechas
/// - Excluir vencimientos ya confirmados o cancelados
/// - Retornar objetos en memoria (NO insertar en DB)
///
/// Reglas:
/// - Solo compromisos activos (activo=1, eliminado=0)
/// - Respetar fecha_fin y cuotas
/// - No duplicar vencimientos ya confirmados
/// - Los movimientos ESPERADOS son transitorios (no se persisten)
class MovimientosProyectadosService {
  MovimientosProyectadosService._();
  static final instance = MovimientosProyectadosService._();

  final _compromisosService = CompromisosService.instance;

  /// Calcula todos los movimientos esperados de un compromiso en un rango de fechas.
  ///
  /// FASE 13.5: Ahora lee desde la tabla compromiso_cuotas en lugar de calcular on-the-fly.
  ///
  /// Parámetros:
  /// - [compromisoId]: ID del compromiso
  /// - [fechaDesde]: fecha inicial del rango (inclusive)
  /// - [fechaHasta]: fecha final del rango (inclusive)
  ///
  /// Retorna lista de movimientos proyectados (objetos en memoria).
  ///
  /// Lógica:
  /// 1. Obtener datos del compromiso
  /// 2. Validar que esté activo
  /// 3. Leer cuotas desde compromiso_cuotas
  /// 4. Filtrar por rango de fechas
  /// 5. Solo mostrar cuotas con estado 'ESPERADO'
  ///
  /// Retorna lista vacía si:
  /// - Compromiso no existe o está pausado/eliminado
  /// - No hay cuotas en el rango
  /// - Todas las cuotas están confirmadas o canceladas
  Future<List<MovimientoProyectado>> calcularMovimientosEsperados({
    required int compromisoId,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
  }) async {
    final compromiso = await _compromisosService.obtenerCompromiso(compromisoId);
    if (compromiso == null || compromiso['activo'] != 1) {
      return [];
    }

    final db = await AppDatabase.instance();

    // Obtener datos del compromiso
    final tipo = compromiso['tipo'] as String;
    final categoria = compromiso['categoria'] as String;
    final nombre = compromiso['nombre'] as String;
    final observaciones = compromiso['observaciones'] as String?;
    final unidadGestionId = compromiso['unidad_gestion_id'] as int;
    final totalCuotas = compromiso['cuotas'] as int?;
    final entidadNombre = compromiso['entidad_nombre'] as String?;

    // Leer cuotas desde la tabla compromiso_cuotas
    final cuotas = await db.query(
      'compromiso_cuotas',
      where: 'compromiso_id = ? AND estado = ?',
      whereArgs: [compromisoId, 'ESPERADO'],
      orderBy: 'numero_cuota',
    );

    // Filtrar por rango de fechas y convertir a MovimientoProyectado
    final vencimientos = <MovimientoProyectado>[];
    
    for (final cuota in cuotas) {
      final fechaStr = cuota['fecha_programada'] as String;
      final fechaVencimiento = DateTime.parse(fechaStr);
      
      // Filtrar por rango
      if (fechaVencimiento.isBefore(fechaDesde) || fechaVencimiento.isAfter(fechaHasta)) {
        continue;
      }
      
      vencimientos.add(MovimientoProyectado(
        compromisoId: compromisoId,
        fechaVencimiento: fechaVencimiento,
        monto: (cuota['monto_esperado'] as num).toDouble(),
        numeroCuota: cuota['numero_cuota'] as int,
        totalCuotas: totalCuotas,
        tipo: tipo,
        categoria: categoria,
        nombre: nombre,
        observaciones: observaciones,
        unidadGestionId: unidadGestionId,
        entidadNombre: entidadNombre,
      ));
    }

    return vencimientos;
  }

  /// Calcula movimientos esperados de todos los compromisos activos en un rango.
  ///
  /// Parámetros:
  /// - [fechaDesde]: fecha inicial (inclusive)
  /// - [fechaHasta]: fecha final (inclusive)
  /// - [unidadGestionId]: filtrar por unidad de gestión (opcional)
  /// - [tipo]: filtrar por INGRESO o EGRESO (opcional)
  ///
  /// Retorna lista de movimientos proyectados ordenados por fecha.
  Future<List<MovimientoProyectado>> calcularMovimientosEsperadosGlobal({
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    int? unidadGestionId,
    String? tipo,
  }) async {
    // Obtener compromisos activos
    final compromisos = await _compromisosService.listarCompromisos(
      unidadGestionId: unidadGestionId,
      tipo: tipo,
      activo: true,
    );

    final todosMovimientos = <MovimientoProyectado>[];

    for (final compromiso in compromisos) {
      final id = compromiso['id'] as int;
      final movimientos = await calcularMovimientosEsperados(
        compromisoId: id,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
      );
      todosMovimientos.addAll(movimientos);
    }

    // Ordenar por fecha
    todosMovimientos.sort((a, b) => a.fechaVencimiento.compareTo(b.fechaVencimiento));

    return todosMovimientos;
  }

  /// Calcula movimientos esperados para un mes específico.
  ///
  /// Parámetros:
  /// - [year]: año
  /// - [month]: mes (1-12)
  /// - [unidadGestionId]: filtrar por unidad (opcional)
  /// - [tipo]: filtrar por INGRESO/EGRESO (opcional)
  ///
  /// Retorna movimientos esperados del mes.
  Future<List<MovimientoProyectado>> calcularMovimientosEsperadosMes({
    required int year,
    required int month,
    int? unidadGestionId,
    String? tipo,
  }) async {
    final fechaDesde = DateTime(year, month, 1);
    final fechaHasta = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));

    return await calcularMovimientosEsperadosGlobal(
      fechaDesde: fechaDesde,
      fechaHasta: fechaHasta,
      unidadGestionId: unidadGestionId,
      tipo: tipo,
    );
  }

  /// Calcula movimientos cancelados para un mes específico.
  ///
  /// Parámetros:
  /// - [year]: año
  /// - [month]: mes (1-12)
  /// - [unidadGestionId]: filtrar por unidad (opcional)
  /// - [tipo]: filtrar por INGRESO/EGRESO (opcional)
  ///
  /// Retorna movimientos cancelados del mes (según su fecha programada original).
  Future<List<MovimientoProyectado>> calcularMovimientosCanceladosMes({
    required int year,
    required int month,
    int? unidadGestionId,
    String? tipo,
  }) async {
    final fechaDesde = DateTime(year, month, 1);
    final fechaHasta = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));

    // Obtener compromisos activos
    final compromisos = await _compromisosService.listarCompromisos(
      unidadGestionId: unidadGestionId,
      tipo: tipo,
      activo: true,
    );

    final db = await AppDatabase.instance();
    final todosCancelados = <MovimientoProyectado>[];

    for (final compromiso in compromisos) {
      final compromisoId = compromiso['id'] as int;
      final tipoComp = compromiso['tipo'] as String;
      final categoria = compromiso['categoria'] as String;
      final nombre = compromiso['nombre'] as String;
      final observaciones = compromiso['observaciones'] as String?;
      final unidadGestionIdComp = compromiso['unidad_gestion_id'] as int;
      final totalCuotas = compromiso['cuotas'] as int?;
      final entidadNombre = compromiso['entidad_nombre'] as String?;

      // Leer cuotas CANCELADAS del compromiso
      final cuotas = await db.query(
        'compromiso_cuotas',
        where: 'compromiso_id = ? AND estado = ?',
        whereArgs: [compromisoId, 'CANCELADO'],
        orderBy: 'numero_cuota',
      );

      for (final cuota in cuotas) {
        final fechaStr = cuota['fecha_programada'] as String;
        final fechaVencimiento = DateTime.parse(fechaStr);
        
        // Filtrar por rango (según fecha programada original, no fecha de cancelación)
        if (fechaVencimiento.isBefore(fechaDesde) || fechaVencimiento.isAfter(fechaHasta)) {
          continue;
        }
        
        todosCancelados.add(MovimientoProyectado(
          compromisoId: compromisoId,
          fechaVencimiento: fechaVencimiento,
          monto: (cuota['monto_esperado'] as num).toDouble(),
          numeroCuota: cuota['numero_cuota'] as int,
          totalCuotas: totalCuotas,
          tipo: tipoComp,
          categoria: categoria,
          nombre: nombre,
          observaciones: observaciones,
          unidadGestionId: unidadGestionIdComp,
          estado: 'CANCELADO',
          entidadNombre: entidadNombre,
        ));
      }
    }

    // Ordenar por fecha
    todosCancelados.sort((a, b) => a.fechaVencimiento.compareTo(b.fechaVencimiento));

    return todosCancelados;
  }

  /// Calcula el total esperado (suma de montos) en un rango de fechas.
  ///
  /// Útil para mostrar proyecciones en UI.
  Future<Map<String, double>> calcularTotalEsperado({
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    int? unidadGestionId,
  }) async {
    final movimientos = await calcularMovimientosEsperadosGlobal(
      fechaDesde: fechaDesde,
      fechaHasta: fechaHasta,
      unidadGestionId: unidadGestionId,
    );

    double totalIngresos = 0;
    double totalEgresos = 0;

    for (final mov in movimientos) {
      if (mov.tipo == 'INGRESO') {
        totalIngresos += mov.monto;
      } else {
        totalEgresos += mov.monto;
      }
    }

    return {
      'ingresos': totalIngresos,
      'egresos': totalEgresos,
      'saldo': totalIngresos - totalEgresos,
    };
  }

  /// Verifica si un compromiso tiene movimientos esperados pendientes.
  ///
  /// Útil para validaciones antes de desactivar un compromiso.
  Future<bool> tieneMovimientosEsperados({
    required int compromisoId,
    DateTime? fechaDesde,
  }) async {
    final desde = fechaDesde ?? DateTime.now();
    final hasta = DateTime(2099, 12, 31); // Fecha muy futura

    final movimientos = await calcularMovimientosEsperados(
      compromisoId: compromisoId,
      fechaDesde: desde,
      fechaHasta: hasta,
    );

    return movimientos.isNotEmpty;
  }
}

/// Modelo transient para movimientos proyectados.
///
/// NO se persiste en DB, solo se usa para cálculos y visualización.
class MovimientoProyectado {
  final int compromisoId;
  final DateTime fechaVencimiento;
  final double monto;
  final int? numeroCuota; // null si el compromiso no tiene cuotas
  final int? totalCuotas; // total de cuotas del compromiso (para mostrar X/Y)
  final String tipo; // 'INGRESO' | 'EGRESO'
  final String categoria;
  final String nombre;
  final String? observaciones;
  final int unidadGestionId;
  final String estado; // 'ESPERADO' | 'CANCELADO'
  final String? entidadNombre; // Nombre del jugador/staff asociado

  const MovimientoProyectado({
    required this.compromisoId,
    required this.fechaVencimiento,
    required this.monto,
    required this.numeroCuota,
    this.totalCuotas,
    required this.tipo,
    required this.categoria,
    required this.nombre,
    this.observaciones,
    required this.unidadGestionId,
    this.estado = 'ESPERADO',
    this.entidadNombre,
  });

  /// Convierte a Map para fácil integración con UI.
  Map<String, dynamic> toMap() {
    return {
      'compromiso_id': compromisoId,
      'fecha_vencimiento': fechaVencimiento.toIso8601String(),
      'monto': monto,
      'numero_cuota': numeroCuota,
      'total_cuotas': totalCuotas,
      'tipo': tipo,
      'categoria': categoria,
      'nombre': nombre,
      'observaciones': observaciones,
      'unidad_gestion_id': unidadGestionId,
      'estado': estado,
      'entidad_nombre': entidadNombre,
    };
  }

  /// Genera descripción para mostrar en UI.
  String get descripcion {
    final cuotaStr = numeroCuota != null && totalCuotas != null
        ? ' (Cuota $numeroCuota/$totalCuotas)'
        : numeroCuota != null
        ? ' (Cuota $numeroCuota)'
        : '';
    return '$nombre$cuotaStr';
  }

  @override
  String toString() {
    return 'MovimientoProyectado(compromiso=$compromisoId, fecha=$fechaVencimiento, monto=$monto, cuota=$numeroCuota, estado=$estado)';
  }
}
