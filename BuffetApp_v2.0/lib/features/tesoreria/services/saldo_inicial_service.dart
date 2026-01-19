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
    // Validaciones básicas
    if (periodoTipo != 'ANIO' && periodoTipo != 'MES') {
      throw Exception('Tipo de período inválido. Debe ser ANIO o MES.');
    }

    if (periodoTipo == 'ANIO') {
      // Validar formato YYYY
      final anioRegex = RegExp(r'^\d{4}$');
      if (!anioRegex.hasMatch(periodoValor)) {
        throw Exception('Valor de año inválido. Formato esperado: YYYY');
      }
    } else if (periodoTipo == 'MES') {
      // Validar formato YYYY-MM
      final mesRegex = RegExp(r'^\d{4}-\d{2}$');
      if (!mesRegex.hasMatch(periodoValor)) {
        throw Exception('Valor de mes inválido. Formato esperado: YYYY-MM');
      }
    }

    if (monto < 0) {
      throw Exception('El monto no puede ser negativo.');
    }

    // Verificar que no exista ya un saldo para esta unidad y período
    final existe = await AppDatabase.existeSaldoInicial(
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

    // Insertar el nuevo saldo
    return await AppDatabase.insertSaldoInicial(
      unidadGestionId: unidadGestionId,
      periodoTipo: periodoTipo,
      periodoValor: periodoValor,
      monto: monto,
      observacion: observacion,
    );
  }

  /// Actualiza un saldo inicial existente.
  /// Solo permite modificar monto y observación, no la unidad ni el período.
  static Future<void> actualizar({
    required int id,
    required double monto,
    String? observacion,
  }) async {
    if (monto < 0) {
      throw Exception('El monto no puede ser negativo.');
    }

    final filasAfectadas = await AppDatabase.actualizarSaldoInicial(
      id: id,
      monto: monto,
      observacion: observacion,
    );

    if (filasAfectadas == 0) {
      throw Exception('Saldo inicial no encontrado.');
    }
  }

  /// Elimina un saldo inicial.
  /// ⚠️ Usar con precaución: puede afectar cálculos históricos.
  static Future<void> eliminar(int id) async {
    final filasAfectadas = await AppDatabase.eliminarSaldoInicial(id);

    if (filasAfectadas == 0) {
      throw Exception('Saldo inicial no encontrado.');
    }
  }

  /// Obtiene el saldo inicial para una unidad y período específicos.
  /// Retorna null si no existe.
  static Future<SaldoInicial?> obtener({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    final map = await AppDatabase.obtenerSaldoInicial(
      unidadGestionId: unidadGestionId,
      periodoTipo: periodoTipo,
      periodoValor: periodoValor,
    );

    return map != null ? SaldoInicial.fromMap(map) : null;
  }

  /// Lista todos los saldos iniciales, opcionalmente filtrados por unidad.
  static Future<List<SaldoInicial>> listar({int? unidadGestionId}) async {
    final mapList = await AppDatabase.listarSaldosIniciales(
      unidadGestionId: unidadGestionId,
    );

    return mapList.map((map) => SaldoInicial.fromMap(map)).toList();
  }

  /// Calcula el saldo inicial efectivo para un mes específico.
  ///
  /// Lógica:
  /// - Si existe saldo inicial del mes → usa ese.
  /// - Si NO existe saldo del mes pero SÍ del año → usa el saldo anual.
  /// - Si NO existe ninguno → retorna 0.
  ///
  /// Ejemplo:
  /// - Para Enero 2026: busca saldo MES 2026-01, si no existe busca ANIO 2026.
  /// - Para Febrero 2026: busca saldo MES 2026-02 (no debería existir normalmente).
  ///
  /// Nota: El saldo inicial anual solo se usa para el primer mes del año.
  /// Los meses siguientes heredan el saldo del mes anterior (calculado externamente).
  static Future<double> calcularSaldoInicialMes({
    required int unidadGestionId,
    required int anio,
    required int mes,
  }) async {
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
  }

  /// Verifica si existe un saldo inicial para una unidad y período.
  static Future<bool> existe({
    required int unidadGestionId,
    required String periodoTipo,
    required String periodoValor,
  }) async {
    return await AppDatabase.existeSaldoInicial(
      unidadGestionId: unidadGestionId,
      periodoTipo: periodoTipo,
      periodoValor: periodoValor,
    );
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
