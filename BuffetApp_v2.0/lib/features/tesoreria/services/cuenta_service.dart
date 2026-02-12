import '../../../data/dao/db.dart';
import '../../../domain/models.dart';

/// Servicio para gestión de cuentas de fondos (bancos, billeteras, cajas, inversiones)
class CuentaService {
  /// Listar cuentas activas por unidad de gestión
  Future<List<CuentaFondos>> listarPorUnidad(int unidadGestionId, {bool soloActivas = true}) async {
    try {
      final db = await AppDatabase.instance();
      
      String where = 'unidad_gestion_id = ? AND eliminado = 0';
      List<dynamic> whereArgs = [unidadGestionId];
      
      if (soloActivas) {
        where += ' AND activa = 1';
      }
      
      final rows = await db.query(
        'cuentas_fondos',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'nombre ASC',
      );
      
      return rows.map((row) => CuentaFondos.fromMap(row)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.listar_por_unidad',
        error: e,
        stackTrace: st,
        payload: {'unidad_gestion_id': unidadGestionId},
      );
      rethrow;
    }
  }

  /// Listar todas las cuentas (para reportes o administración)
  Future<List<CuentaFondos>> listarTodas({bool soloActivas = true}) async {
    try {
      final db = await AppDatabase.instance();
      
      String where = 'eliminado = 0';
      if (soloActivas) {
        where += ' AND activa = 1';
      }
      
      final rows = await db.query(
        'cuentas_fondos',
        where: where,
        orderBy: 'unidad_gestion_id ASC, nombre ASC',
      );
      
      return rows.map((row) => CuentaFondos.fromMap(row)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.listar_todas',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Obtener cuenta por ID
  Future<CuentaFondos?> obtenerPorId(int id) async {
    try {
      final db = await AppDatabase.instance();
      
      final rows = await db.query(
        'cuentas_fondos',
        where: 'id = ? AND eliminado = 0',
        whereArgs: [id],
        limit: 1,
      );
      
      if (rows.isEmpty) return null;
      return CuentaFondos.fromMap(rows.first);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.obtener_por_id',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Crear nueva cuenta
  Future<int> crear({
    required String nombre,
    required String tipo,
    required int unidadGestionId,
    required double saldoInicial,
    bool tieneComision = false,
    double? comisionPorcentaje,
    String? observaciones,
    String? moneda,
    String? bancoNombre,
    String? cbuAlias,
    String? dispositivoId,
  }) async {
    try {
      // Validaciones
      if (nombre.trim().isEmpty) {
        throw Exception('El nombre de la cuenta es obligatorio');
      }
      
      if (!['BANCO', 'BILLETERA', 'CAJA', 'INVERSION'].contains(tipo)) {
        throw Exception('Tipo de cuenta inválido');
      }
      
      if (tieneComision && (comisionPorcentaje == null || comisionPorcentaje <= 0)) {
        throw Exception('Si la cuenta tiene comisión, debe especificar el porcentaje');
      }

      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final id = await db.insert('cuentas_fondos', {
        'nombre': nombre.trim(),
        'tipo': tipo,
        'unidad_gestion_id': unidadGestionId,
        'saldo_inicial': saldoInicial,
        'tiene_comision': tieneComision ? 1 : 0,
        'comision_porcentaje': comisionPorcentaje,
        'activa': 1,
        'observaciones': observaciones?.trim(),
        'moneda': moneda ?? 'ARS',
        'banco_nombre': bancoNombre?.trim(),
        'cbu_alias': cbuAlias?.trim(),
        'dispositivo_id': dispositivoId,
        'eliminado': 0,
        'sync_estado': 'PENDIENTE',
        'created_ts': now,
        'updated_ts': now,
      });

      return id;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.crear',
        error: e,
        stackTrace: st,
        payload: {
          'nombre': nombre,
          'tipo': tipo,
          'unidad_gestion_id': unidadGestionId,
        },
      );
      rethrow;
    }
  }

  /// Actualizar cuenta existente
  Future<void> actualizar({
    required int id,
    required String nombre,
    required String tipo,
    required double saldoInicial,
    bool tieneComision = false,
    double? comisionPorcentaje,
    String? observaciones,
    String? bancoNombre,
    String? cbuAlias,
  }) async {
    try {
      // Validaciones
      if (nombre.trim().isEmpty) {
        throw Exception('El nombre de la cuenta es obligatorio');
      }
      
      if (!['BANCO', 'BILLETERA', 'CAJA', 'INVERSION'].contains(tipo)) {
        throw Exception('Tipo de cuenta inválido');
      }
      
      if (tieneComision && (comisionPorcentaje == null || comisionPorcentaje <= 0)) {
        throw Exception('Si la cuenta tiene comisión, debe especificar el porcentaje');
      }

      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.update(
        'cuentas_fondos',
        {
          'nombre': nombre.trim(),
          'tipo': tipo,
          'saldo_inicial': saldoInicial,
          'tiene_comision': tieneComision ? 1 : 0,
          'comision_porcentaje': comisionPorcentaje,
          'observaciones': observaciones?.trim(),
          'banco_nombre': bancoNombre?.trim(),
          'cbu_alias': cbuAlias?.trim(),
          'sync_estado': 'PENDIENTE',
          'updated_ts': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.actualizar',
        error: e,
        stackTrace: st,
        payload: {'id': id, 'nombre': nombre},
      );
      rethrow;
    }
  }

  /// Desactivar cuenta (soft delete)
  Future<void> desactivar(int id) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.update(
        'cuentas_fondos',
        {
          'activa': 0,
          'sync_estado': 'PENDIENTE',
          'updated_ts': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.desactivar',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Reactivar cuenta
  Future<void> reactivar(int id) async {
    try {
      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.update(
        'cuentas_fondos',
        {
          'activa': 1,
          'sync_estado': 'PENDIENTE',
          'updated_ts': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.reactivar',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Eliminar cuenta (soft delete)
  Future<void> eliminar(int id) async {
    try {
      // Verificar que no tenga movimientos
      final db = await AppDatabase.instance();
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'cuenta_id = ? AND eliminado = 0',
        whereArgs: [id],
        limit: 1,
      );
      
      if (movimientos.isNotEmpty) {
        throw Exception(
          'No se puede eliminar una cuenta con movimientos registrados. '
          'Puede desactivarla en su lugar.',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.update(
        'cuentas_fondos',
        {
          'eliminado': 1,
          'activa': 0,
          'sync_estado': 'PENDIENTE',
          'updated_ts': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.eliminar',
        error: e,
        stackTrace: st,
        payload: {'id': id},
      );
      rethrow;
    }
  }

  /// Obtener saldo actual de una cuenta
  Future<double> obtenerSaldo(int cuentaId) async {
    try {
      final cuenta = await obtenerPorId(cuentaId);
      if (cuenta == null) {
        throw Exception('Cuenta no encontrada');
      }

      final db = await AppDatabase.instance();
      return await cuenta.calcularSaldoActual(db);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.obtener_saldo',
        error: e,
        stackTrace: st,
        payload: {'cuenta_id': cuentaId},
      );
      rethrow;
    }
  }

  /// Obtener saldos de todas las cuentas de una unidad
  Future<Map<int, double>> obtenerSaldosPorUnidad(int unidadGestionId) async {
    try {
      final cuentas = await listarPorUnidad(unidadGestionId);
      final db = await AppDatabase.instance();
      final Map<int, double> saldos = {};

      for (final cuenta in cuentas) {
        saldos[cuenta.id] = await cuenta.calcularSaldoActual(db);
      }

      return saldos;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.obtener_saldos_por_unidad',
        error: e,
        stackTrace: st,
        payload: {'unidad_gestion_id': unidadGestionId},
      );
      rethrow;
    }
  }

  /// Calcular comisión bancaria para un monto
  Future<double?> calcularComision(int cuentaId, double monto) async {
    try {
      final cuenta = await obtenerPorId(cuentaId);
      if (cuenta == null) return null;
      
      return cuenta.calcularComision(monto);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuenta_service.calcular_comision',
        error: e,
        stackTrace: st,
        payload: {'cuenta_id': cuentaId, 'monto': monto},
      );
      rethrow;
    }
  }
}
