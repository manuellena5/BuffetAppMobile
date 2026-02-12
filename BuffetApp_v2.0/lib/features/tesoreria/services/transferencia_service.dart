import 'package:uuid/uuid.dart';
import '../../../data/dao/db.dart';
import 'cuenta_service.dart';

/// Servicio para gestión de transferencias entre cuentas
/// 
/// Una transferencia genera DOS movimientos vinculados:
/// - EGRESO desde cuenta origen
/// - INGRESO en cuenta destino
/// 
/// Ambos movimientos comparten el mismo transferencia_id (UUID v4)
class TransferenciaService {
  final _cuentaService = CuentaService();

  /// Crear una transferencia entre dos cuentas
  /// 
  /// Reglas:
  /// - NO permitir transferencias entre cuentas de diferentes unidades
  /// - NO permitir transferencia a la misma cuenta
  /// - Genera 2 movimientos con es_transferencia=1
  /// - Usa categoría 'TRANSFERENCIA'
  /// - Comparten el mismo transferencia_id (UUID v4)
  Future<String> crear({
    required int cuentaOrigenId,
    required int cuentaDestinoId,
    required double monto,
    required int medioPagoId,
    String? observacion,
    String? dispositivoId,
    double? montoComisionOverride,
    String? observacionComisionOverride,
  }) async {
    try {
      // Validaciones básicas
      if (monto <= 0) {
        throw Exception('El monto debe ser mayor a cero');
      }

      if (cuentaOrigenId == cuentaDestinoId) {
        throw Exception('No se puede transferir a la misma cuenta');
      }

      // Obtener cuentas
      final cuentaOrigen = await _cuentaService.obtenerPorId(cuentaOrigenId);
      final cuentaDestino = await _cuentaService.obtenerPorId(cuentaDestinoId);

      if (cuentaOrigen == null) {
        throw Exception('Cuenta de origen no encontrada');
      }

      if (cuentaDestino == null) {
        throw Exception('Cuenta de destino no encontrada');
      }

      // Validar que ambas cuentas pertenezcan a la misma unidad (regla de negocio)
      if (cuentaOrigen.unidadGestionId != cuentaDestino.unidadGestionId) {
        throw Exception(
          'No se pueden realizar transferencias entre cuentas de diferentes unidades de gestión',
        );
      }

      // Verificar que ambas cuentas estén activas
      if (!cuentaOrigen.activa) {
        throw Exception('La cuenta de origen está inactiva');
      }

      if (!cuentaDestino.activa) {
        throw Exception('La cuenta de destino está inactiva');
      }

      final db = await AppDatabase.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final transferenciaId = const Uuid().v4();
      
      // FASE 22.3: Calcular comisiones para ambas cuentas si aplica
      // Comisión en cuenta ORIGEN (egreso de dinero)
      final comisionOrigenPorcentaje = cuentaOrigen.tieneComision ? (cuentaOrigen.comisionPorcentaje ?? 0.0) : 0.0;
      final montoComisionOrigen = comisionOrigenPorcentaje > 0 ? monto * (comisionOrigenPorcentaje / 100) : 0.0;
      
      // Comisión en cuenta DESTINO (ingreso de dinero)
      final comisionDestinoPorcentaje = cuentaDestino.tieneComision ? (cuentaDestino.comisionPorcentaje ?? 0.0) : 0.0;
      final montoComisionDestino = montoComisionOverride ?? 
        (comisionDestinoPorcentaje > 0 ? monto * (comisionDestinoPorcentaje / 100) : 0.0);
      
      // Usar transacción para asegurar atomicidad
      await db.transaction((txn) async {
        // Movimiento 1: EGRESO desde cuenta origen
        await txn.insert('evento_movimiento', {
          'disciplina_id': cuentaOrigen.unidadGestionId, // Usar unidad como disciplina
          'cuenta_id': cuentaOrigenId,
          'tipo': 'EGRESO',
          'categoria': 'TRANSFERENCIA',
          'monto': monto,
          'medio_pago_id': medioPagoId,
          'observacion': observacion ?? 'Transferencia a ${cuentaDestino.nombre}',
          'es_transferencia': 1,
          'transferencia_id': transferenciaId,
          'dispositivo_id': dispositivoId,
          'eliminado': 0,
          'estado': 'CONFIRMADO',
          'sync_estado': 'PENDIENTE',
          'created_ts': now,
        });

        // Movimiento 2: INGRESO en cuenta destino
        await txn.insert('evento_movimiento', {
          'disciplina_id': cuentaDestino.unidadGestionId,
          'cuenta_id': cuentaDestinoId,
          'tipo': 'INGRESO',
          'categoria': 'TRANSFERENCIA',
          'monto': monto,
          'medio_pago_id': medioPagoId,
          'observacion': observacion ?? 'Transferencia desde ${cuentaOrigen.nombre}',
          'es_transferencia': 1,
          'transferencia_id': transferenciaId,
          'dispositivo_id': dispositivoId,
          'eliminado': 0,
          'estado': 'CONFIRMADO',
          'sync_estado': 'PENDIENTE',
          'created_ts': now,
        });

        // FASE 22.3: Movimiento 3 - Comisión en cuenta ORIGEN (si cobra comisión por egreso)
        if (montoComisionOrigen > 0) {
          final observacionComisionOrigen = 
            'Comisión $comisionOrigenPorcentaje% por transferencia a ${cuentaDestino.nombre}';
          
          await txn.insert('evento_movimiento', {
            'disciplina_id': cuentaOrigen.unidadGestionId,
            'cuenta_id': cuentaOrigenId,
            'tipo': 'EGRESO',
            'categoria': 'COM_BANC', // Comisión bancaria
            'monto': montoComisionOrigen,
            'medio_pago_id': medioPagoId,
            'observacion': observacionComisionOrigen,
            'es_transferencia': 1, // Vinculado a la transferencia
            'transferencia_id': transferenciaId,
            'dispositivo_id': dispositivoId,
            'eliminado': 0,
            'estado': 'CONFIRMADO',
            'sync_estado': 'PENDIENTE',
            'created_ts': now,
          });
        }

        // FASE 22.3: Movimiento 4 - Comisión en cuenta DESTINO (si cobra comisión por ingreso)
        if (montoComisionDestino > 0) {
          final observacionComision = observacionComisionOverride ?? 
            'Comisión $comisionDestinoPorcentaje% por transferencia desde ${cuentaOrigen.nombre}';
          
          await txn.insert('evento_movimiento', {
            'disciplina_id': cuentaDestino.unidadGestionId,
            'cuenta_id': cuentaDestinoId,
            'tipo': 'EGRESO',
            'categoria': 'COM_BANC', // Comisión bancaria
            'monto': montoComisionDestino,
            'medio_pago_id': medioPagoId,
            'observacion': observacionComision,
            'es_transferencia': 1, // Vinculado a la transferencia
            'transferencia_id': transferenciaId,
            'dispositivo_id': dispositivoId,
            'eliminado': 0,
            'estado': 'CONFIRMADO',
            'sync_estado': 'PENDIENTE',
            'created_ts': now,
          });
        }
      });

      return transferenciaId;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'transferencia_service.crear',
        error: e,
        stackTrace: st,
        payload: {
          'cuenta_origen_id': cuentaOrigenId,
          'cuenta_destino_id': cuentaDestinoId,
          'monto': monto,
        },
      );
      rethrow;
    }
  }

  /// Obtener movimientos de una transferencia (ambos: egreso e ingreso)
  Future<List<Map<String, dynamic>>> obtenerMovimientos(String transferenciaId) async {
    try {
      final db = await AppDatabase.instance();
      
      final rows = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ? AND eliminado = 0',
        whereArgs: [transferenciaId],
        orderBy: 'tipo DESC', // INGRESO primero, EGRESO después
      );

      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'transferencia_service.obtener_movimientos',
        error: e,
        stackTrace: st,
        payload: {'transferencia_id': transferenciaId},
      );
      rethrow;
    }
  }

  /// Listar transferencias por cuenta (como origen o destino)
  Future<List<Map<String, dynamic>>> listarPorCuenta(int cuentaId) async {
    try {
      final db = await AppDatabase.instance();
      
      final rows = await db.rawQuery('''
        SELECT DISTINCT
          transferencia_id,
          MAX(created_ts) as fecha,
          MAX(CASE WHEN tipo='EGRESO' THEN monto END) as monto,
          MAX(CASE WHEN tipo='EGRESO' THEN cuenta_id END) as cuenta_origen_id,
          MAX(CASE WHEN tipo='INGRESO' THEN cuenta_id END) as cuenta_destino_id,
          MAX(observacion) as observacion
        FROM evento_movimiento
        WHERE transferencia_id IS NOT NULL
          AND es_transferencia = 1
          AND eliminado = 0
          AND (cuenta_id = ? OR transferencia_id IN (
            SELECT transferencia_id 
            FROM evento_movimiento 
            WHERE cuenta_id = ? AND es_transferencia = 1
          ))
        GROUP BY transferencia_id
        ORDER BY fecha DESC
      ''', [cuentaId, cuentaId]);

      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'transferencia_service.listar_por_cuenta',
        error: e,
        stackTrace: st,
        payload: {'cuenta_id': cuentaId},
      );
      rethrow;
    }
  }

  /// Anular una transferencia (marca ambos movimientos como eliminados)
  /// 
  /// IMPORTANTE: Solo puede anularse si no está sincronizada
  Future<void> anular(String transferenciaId, {String? motivoAnulacion}) async {
    try {
      final db = await AppDatabase.instance();
      
      // Verificar que no esté sincronizada
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'transferencia_id = ? AND sync_estado = ?',
        whereArgs: [transferenciaId, 'SINCRONIZADA'],
        limit: 1,
      );

      if (movimientos.isNotEmpty) {
        throw Exception(
          'No se puede anular una transferencia ya sincronizada con el servidor',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final observacionAnulacion = motivoAnulacion != null
          ? 'ANULADA: $motivoAnulacion'
          : 'ANULADA';

      // Marcar ambos movimientos como eliminados
      await db.update(
        'evento_movimiento',
        {
          'eliminado': 1,
          'estado': 'CANCELADO',
          'observacion': observacionAnulacion,
          'updated_ts': now,
        },
        where: 'transferencia_id = ?',
        whereArgs: [transferenciaId],
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'transferencia_service.anular',
        error: e,
        stackTrace: st,
        payload: {
          'transferencia_id': transferenciaId,
          'motivo': motivoAnulacion,
        },
      );
      rethrow;
    }
  }

  /// Verificar integridad de una transferencia
  /// 
  /// Una transferencia válida debe tener exactamente 2 movimientos:
  /// - 1 EGRESO
  /// - 1 INGRESO
  /// - Mismo monto
  /// - Mismo transferencia_id
  Future<bool> verificarIntegridad(String transferenciaId) async {
    try {
      final movimientos = await obtenerMovimientos(transferenciaId);
      
      if (movimientos.length != 2) return false;
      
      final egreso = movimientos.firstWhere(
        (m) => m['tipo'] == 'EGRESO',
        orElse: () => {},
      );
      
      final ingreso = movimientos.firstWhere(
        (m) => m['tipo'] == 'INGRESO',
        orElse: () => {},
      );
      
      if (egreso.isEmpty || ingreso.isEmpty) return false;
      
      // Verificar que tengan el mismo monto
      final montoEgreso = (egreso['monto'] as num?)?.toDouble() ?? 0;
      final montoIngreso = (ingreso['monto'] as num?)?.toDouble() ?? 0;
      
      return (montoEgreso - montoIngreso).abs() < 0.01; // Tolerancia para decimales
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'transferencia_service.verificar_integridad',
        error: e,
        stackTrace: st,
        payload: {'transferencia_id': transferenciaId},
      );
      return false;
    }
  }
}
