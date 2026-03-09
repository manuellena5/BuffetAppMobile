import '../../../data/dao/db.dart';
import '../../../domain/models.dart';

/// Servicio de lógica de negocio para Saldos Iniciales.
///
/// El saldo inicial representa fondos disponibles previos al registro de
/// movimientos en la aplicación. No se registra como ingreso ni egreso.
/// Se utiliza únicamente como base para el cálculo del saldo del primer
/// mes del período.
class SaldoInicialService {
  /// Crea un nuevo saldo inicial.
  /// Valida que no exista ya un saldo para la misma unidad y período.
  /// Lanza [Exception] si ya existe o si los datos son inválidos.
  static Future<int> crear({
    required int unidadGestionId,
    required String periodoTipo, // 'ANIO' | 'MES'
    required String periodoValor, // '2026' o '2026-01'
    required double monto,
    String? observacion,
  }) async {
    try {
      // Validaciones básicas
      if (periodoTipo != 'ANIO' && periodoTipo != 'MES') {
        throw Exception('Tipo de período inválido. Debe ser ANIO o MES.');
      }

      if (periodoTipo == 'ANIO') {
        final anioRegex = RegExp(r'^\d{4}$');
        if (!anioRegex.hasMatch(periodoValor)) {
          throw Exception('Valor de año inválido. Formato esperado: YYYY');
        }
      } else if (periodoTipo == 'MES') {
        final mesRegex = RegExp(r'^\d{4}-\d{2}$');
        if (!mesRegex.hasMatch(periodoValor)) {
          throw Exception('Valor de mes inválido. Formato esperado: YYYY-MM');
        }
      }

      if (monto < 0) {
        throw Exception('El monto no puede ser negativo.');
      }

      final existe = await TesoreriaDao.existeSaldoInicial(
        unidadGestionId: unidadGestionId,
        periodoTipo: periodoTipo,
        periodoValor: periodoValor,
      );

      if (existe) {
        throw Exception(
          'Ya existe un saldo inicial para esta unidad y período. '
          'Por favor, edítelo en lugar de crear uno nuevo.',
        );
      }

      return await TesoreriaDao.insertSaldoInicial(
        unidadGestionId: unidadGestionId,
        periodoTipo: periodoTipo,
        periodoValor: periodoValor,
        monto: monto,
        observacion: observacion,
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.crear',
        error: e,
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'tipo': periodoTipo, 'valor': periodoValor},
      );
      rethrow;
    }
  }

  /// Actualiza un saldo inicial existente.
  /// Solo permite modificar monto y observación, no la unidad ni el período.
  static Future<void> actualizar({
    required int id,
    required double monto,
    String? observacion,
  }) async {
    try {
      if (monto < 0) {
        throw Exception('El monto no puede ser negativo.');
      }

      final filasAfectadas = await TesoreriaDao.actualizarSaldoInicial(
        id: id,
        monto: monto,
        observacion: observacion,
      );

      if (filasAfectadas == 0) {
        throw Exception('Saldo inicial no encontrado.');
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.actualizar',
        error: e,
        stackTrace: st,
        payload: {'id': id, 'monto': monto},
      );
      rethrow;
    }
  }

  /// Elimina un saldo inicial.
  /// ⚠️ Usar con precaución: puede afectar cálculos históricos.
  static Future<void> eliminar(int id) async {
    try {
      final filasAfectadas = await TesoreriaDao.eliminarSaldoInicial(id);

      if (filasAfectadas == 0) {
        throw Exception('Saldo inicial no encontrado.');
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.eliminar',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Obtiene el saldo inicial para una unidad y período específicos.
  /// Retorna null si no existe.
  static Future<SaldoInicial?> obtener({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    try {
      final map = await TesoreriaDao.obtenerSaldoInicial(
        unidadGestionId: unidadGestionId,
        periodoTipo: periodoTipo,
        periodoValor: periodoValor,
      );

      return map != null ? SaldoInicial.fromMap(map) : null;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.obtener',
        error: e,
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'tipo': periodoTipo, 'valor': periodoValor},
      );
      rethrow;
    }
  }

  /// Lista todos los saldos iniciales, opcionalmente filtrados por unidad.
  static Future<List<SaldoInicial>> listar({int? unidadGestionId}) async {
    try {
      final mapList = await TesoreriaDao.listarSaldosIniciales(
        unidadGestionId: unidadGestionId,
      );

      return mapList.map((map) => SaldoInicial.fromMap(map)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.listar',
        error: e,
        stackTrace: st,
        payload: {'unidad': unidadGestionId},
      );
      rethrow;
    }
  }

  /// Calcula el saldo inicial efectivo para un mes específico.
  ///
  /// Lógica:
  /// - Si existe saldo inicial del mes → usa ese.
  /// - Si NO existe saldo del mes pero SÍ del año → usa el saldo anual.
  /// - Si NO existe ninguno → retorna 0.
  static Future<double> calcularSaldoInicialMes({
    required int unidadGestionId,
    required int anio,
    required int mes,
  }) async {
    try {
      final mesStr = mes.toString().padLeft(2, '0');
      final periodoMes = '$anio-$mesStr';
      final periodoAnio = anio.toString();

      // 1) Buscar saldo inicial del mes específico
      final saldoMes = await obtener(
        unidadGestionId: unidadGestionId,
        periodoTipo: 'MES',
        periodoValor: periodoMes,
      );

      if (saldoMes != null) {
        return saldoMes.monto;
      }

      // 2) Si es el primer mes del año (enero), buscar saldo inicial anual
      if (mes == 1) {
        final saldoAnio = await obtener(
          unidadGestionId: unidadGestionId,
          periodoTipo: 'ANIO',
          periodoValor: periodoAnio,
        );

        if (saldoAnio != null) {
          return saldoAnio.monto;
        }
      }

      // 3) No hay saldo inicial configurado
      return 0.0;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.calcular_mes',
        error: e,
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'anio': anio, 'mes': mes},
      );
      rethrow;
    }
  }

  /// Verifica si existe un saldo inicial para una unidad y período.
  static Future<bool> existe({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    try {
      return await TesoreriaDao.existeSaldoInicial(
        unidadGestionId: unidadGestionId,
        periodoTipo: periodoTipo,
        periodoValor: periodoValor,
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldo_inicial.existe',
        error: e,
        stackTrace: st,
        payload: {'unidad': unidadGestionId, 'tipo': periodoTipo, 'valor': periodoValor},
      );
      rethrow;
    }
  }

  /// Genera el período valor según el tipo.
  /// Útil para la UI al preparar valores para crear/buscar saldos.
  static String generarPeriodoValor({
    required String periodoTipo,
    required int anio,
    int? mes,
  }) {
    if (periodoTipo == 'ANIO') {
      return anio.toString();
    } else if (periodoTipo == 'MES') {
      if (mes == null) {
        throw Exception('Debe proporcionar el mes para período tipo MES.');
      }
      final mesStr = mes.toString().padLeft(2, '0');
      return '$anio-$mesStr';
    }

    throw Exception('Tipo de período inválido: $periodoTipo');
  }
}
