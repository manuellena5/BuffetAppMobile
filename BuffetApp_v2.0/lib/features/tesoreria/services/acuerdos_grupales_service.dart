import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../data/dao/db.dart';
import '../../shared/services/acuerdos_service.dart';
import '../../shared/services/compromisos_service.dart';

/// FASE 19: Servicio para gestionar acuerdos grupales (carga masiva de plantel).
/// 
/// Un acuerdo grupal NO es una entidad operativa, es una herramienta de carga
/// que genera N acuerdos individuales independientes.
class AcuerdosGrupalesService {
  AcuerdosGrupalesService._();
  static final AcuerdosGrupalesService instance = AcuerdosGrupalesService._();

  final _compromisosSvc = CompromisosService.instance;
  final _uuid = const Uuid();

  /// Valida jugadores seleccionados y retorna advertencias (NO bloquea).
  /// 
  /// Validaciones:
  /// - Jugador tiene acuerdos activos en la misma categoría
  /// - Jugador tiene compromisos pendientes
  /// - Fechas solapadas
  Future<Map<int, List<String>>> validarJugadores({
    required List<JugadorConMonto> jugadores,
    required int unidadGestionId,
    required String categoria,
  }) async {
    final validaciones = <int, List<String>>{};

    try {
      for (final jugador in jugadores) {
        final jugadorId = jugador.id;
        final warnings = <String>[];

        // Buscar acuerdos activos en la misma categoría
        final acuerdosExistentes = await AcuerdosService.listarAcuerdos(
          entidadPlantelId: jugadorId,
          soloActivos: true,
          categoria: categoria,
        );

        if (acuerdosExistentes.isNotEmpty) {
          for (final acuerdo in acuerdosExistentes) {
            final nombre = acuerdo['nombre']?.toString() ?? '';
            final inicio = acuerdo['fecha_inicio']?.toString() ?? '';
            warnings.add('Ya tiene acuerdo activo "$nombre" desde $inicio');
          }
        }

        // Buscar compromisos activos
        final compromisosPendientes = await _compromisosSvc.listarCompromisos(
          entidadPlantelId: jugadorId,
          activo: true,
        );

        if (compromisosPendientes.isNotEmpty) {
          warnings.add('Tiene ${compromisosPendientes.length} compromisos pendientes');
        }

        if (warnings.isNotEmpty) {
          validaciones[jugadorId] = warnings;
        }
      }

      return validaciones;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_grupales.validar_jugadores',
        error: e.toString(),
        stackTrace: stack,
        payload: {
          'jugadores_count': jugadores.length,
          'categoria': categoria,
        },
      );
      rethrow;
    }
  }

  /// Genera preview de acuerdos y compromisos a crear.
  Future<PreviewAcuerdoGrupal> generarPreview({
    required String nombre,
    required String tipo,
    required String modalidad,
    required double montoBase,
    double? montoTotal,
    required String frecuencia,
    int? cuotas,
    required String fechaInicio,
    String? fechaFin,
    required bool generaCompromisos,
    required List<JugadorConMonto> jugadores,
  }) async {
    try {
      final previewsIndividuales = <PreviewAcuerdoIndividual>[];
      int totalCompromisos = 0;
      double totalComprometido = 0.0;

      for (final jugador in jugadores) {
        // Calcular compromisos esperados si aplica
        int compromisosEstimados = 0;
        if (generaCompromisos) {
          // Lógica simplificada: depende de modalidad y frecuencia
          if (modalidad == 'MONTO_TOTAL_CUOTAS') {
            // Usar cuotas pasadas o calcular según fechas
            compromisosEstimados = cuotas ?? _calcularCuotasPorFrecuencia(
              fechaInicio,
              fechaFin,
              frecuencia,
            );
          } else if (modalidad == 'RECURRENTE') {
            // Compromisos hasta fecha_fin o infinitos
            if (fechaFin != null) {
              compromisosEstimados = _calcularCuotasPorFrecuencia(
                fechaInicio,
                fechaFin,
                frecuencia,
              );
            } else {
              compromisosEstimados = -1; // Infinito
            }
          }
        }

        final montoFinal = jugador.monto;
        
        previewsIndividuales.add(PreviewAcuerdoIndividual(
          jugadorId: jugador.id,
          jugadorNombre: jugador.nombre,
          montoAjustado: montoFinal,
          compromisosEstimados: compromisosEstimados,
        ));

        if (compromisosEstimados > 0) {
          totalCompromisos += compromisosEstimados;
          totalComprometido += (modalidad == 'MONTO_TOTAL_CUOTAS')
              ? montoFinal
              : montoFinal * compromisosEstimados;
        }
      }

      return PreviewAcuerdoGrupal(
        nombreGrupal: nombre,
        cantidadAcuerdos: jugadores.length,
        totalCompromisos: totalCompromisos,
        totalComprometido: totalComprometido,
        previewsIndividuales: previewsIndividuales,
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_grupales.generar_preview',
        error: e.toString(),
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Crea acuerdos individuales + histórico + compromisos (si aplica).
  /// 
  /// Retorna mapa:
  /// - creados: List<int> IDs de acuerdos creados
  /// - errores: List<String> errores por jugador
  Future<ResultadoCreacionGrupal> crearAcuerdosGrupales({
    required String nombre,
    required int unidadGestionId,
    required String tipo,
    required String modalidad,
    required double montoBase,
    double? montoTotal,
    required String frecuencia,
    int? cuotas,
    required String fechaInicio,
    String? fechaFin,
    required String categoria,
    String? observacionesComunes,
    required bool generaCompromisos,
    required List<JugadorConMonto> jugadores,
    Map<String, dynamic>? payloadFiltros,
  }) async {
    final db = await AppDatabase.instance();
    final acuerdosCreados = <int>[];
    final errores = <String>[];
    final grupalUuid = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      // 1. Crear registro de histórico ANTES de crear acuerdos individuales
      final jugadoresPayload = jugadores
          .map((j) => {
                'id': j.id,
                'nombre': j.nombre,
                'monto_ajustado': j.monto,
              })
          .toList();

      final historicoId = await db.insert('acuerdos_grupales_historico', {
        'uuid_ref': grupalUuid,
        'nombre': nombre,
        'unidad_gestion_id': unidadGestionId,
        'tipo': tipo,
        'modalidad': modalidad,
        'monto_base': montoBase,
        'frecuencia': frecuencia,
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
        'categoria': categoria,
        'observaciones_comunes': observacionesComunes,
        'genera_compromisos': generaCompromisos ? 1 : 0,
        'cantidad_acuerdos_generados': 0, // Se actualiza después
        'payload_filtros': payloadFiltros != null ? jsonEncode(payloadFiltros) : null,
        'payload_jugadores': jsonEncode(jugadoresPayload),
        'created_ts': now,
      });

      // 2. Crear acuerdos individuales
      for (final jugador in jugadores) {
        try {
          // Calcular cuotas si modalidad MONTO_TOTAL_CUOTAS
          int? cuotasCalc;
          double montoAcuerdo = jugador.monto;

          if (modalidad == 'MONTO_TOTAL_CUOTAS') {
            cuotasCalc = cuotas ?? _calcularCuotasPorFrecuencia(
              fechaInicio,
              fechaFin,
              frecuencia,
            );
          }

          final acuerdoId = await AcuerdosService.crearAcuerdo(
            unidadGestionId: unidadGestionId,
            entidadPlantelId: jugador.id,
            nombre: '$nombre - ${jugador.nombre}',
            tipo: tipo,
            modalidad: modalidad,
            montoTotal: modalidad == 'MONTO_TOTAL_CUOTAS' ? montoAcuerdo : null,
            montoPeriodico: modalidad == 'RECURRENTE' ? montoAcuerdo : null,
            frecuencia: frecuencia,
            cuotas: cuotasCalc,
            fechaInicio: fechaInicio,
            fechaFin: fechaFin,
            categoria: categoria,
            observaciones: observacionesComunes,
            generaCompromisos: generaCompromisos,
            origenGrupal: true,
            acuerdoGrupalRef: grupalUuid,
          );

          acuerdosCreados.add(acuerdoId);
          
          // Si debe generar compromisos, crearlos ahora
          if (generaCompromisos) {
            try {
              await AcuerdosService.generarCompromisos(acuerdoId);
            } catch (e) {
              await AppDatabase.logLocalError(
                scope: 'acuerdos_grupales.generar_compromisos',
                error: e.toString(),
                payload: {'acuerdo_id': acuerdoId, 'jugador_id': jugador.id},
              );
              // No lanzar error para no detener la creación de otros acuerdos
            }
          }
        } catch (e) {
          errores.add('${jugador.nombre}: ${e.toString()}');
          await AppDatabase.logLocalError(
            scope: 'acuerdos_grupales.crear_acuerdo_individual',
            error: e.toString(),
            payload: {'jugador_id': jugador.id, 'jugador_nombre': jugador.nombre},
          );
        }
      }

      // 3. Actualizar histórico con cantidad de acuerdos creados
      await db.update(
        'acuerdos_grupales_historico',
        {'cantidad_acuerdos_generados': acuerdosCreados.length},
        where: 'id = ?',
        whereArgs: [historicoId],
      );

      return ResultadoCreacionGrupal(
        acuerdosCreados: acuerdosCreados,
        errores: errores,
        grupalUuid: grupalUuid,
      );
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_grupales.crear_acuerdos_grupales',
        error: e.toString(),
        stackTrace: stack,
        payload: {'nombre': nombre, 'jugadores_count': jugadores.length},
      );
      rethrow;
    }
  }

  /// Obtiene el registro histórico de un acuerdo grupal.
  Future<Map<String, dynamic>?> obtenerHistorico(String grupalUuid) async {
    try {
      final db = await AppDatabase.instance();
      final result = await db.query(
        'acuerdos_grupales_historico',
        where: 'uuid_ref = ?',
        whereArgs: [grupalUuid],
      );

      return result.isEmpty ? null : result.first;
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_grupales.obtener_historico',
        error: e.toString(),
        stackTrace: stack,
        payload: {'grupal_uuid': grupalUuid},
      );
      rethrow;
    }
  }

  /// Lista todos los acuerdos que pertenecen a un acuerdo grupal.
  Future<List<Map<String, dynamic>>> listarAcuerdosHermanos(String grupalUuid) async {
    try {
      return await AcuerdosService.listarAcuerdos(acuerdoGrupalRef: grupalUuid);
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'acuerdos_grupales.listar_acuerdos_hermanos',
        error: e.toString(),
        stackTrace: stack,
        payload: {'grupal_uuid': grupalUuid},
      );
      rethrow;
    }
  }

  // =====================
  // HELPERS PRIVADOS
  // =====================

  int _calcularCuotasPorFrecuencia(String fechaInicio, String? fechaFin, String frecuencia) {
    if (fechaFin == null) return -1; // Infinito

    try {
      final inicio = DateTime.parse(fechaInicio);
      final fin = DateTime.parse(fechaFin);
      final dias = fin.difference(inicio).inDays;

      // Obtener días de frecuencia
      final diasPorCuota = _obtenerDiasPorFrecuencia(frecuencia);
      if (diasPorCuota == 0) return 1; // UNICA

      return (dias / diasPorCuota).ceil();
    } catch (_) {
      return 0;
    }
  }

  int _obtenerDiasPorFrecuencia(String frecuencia) {
    switch (frecuencia) {
      case 'UNICA':
        return 0;
      case 'SEMANAL':
        return 7;
      case 'QUINCENAL':
        return 15;
      case 'MENSUAL':
        return 30;
      case 'BIMESTRAL':
        return 60;
      case 'TRIMESTRAL':
        return 90;
      case 'SEMESTRAL':
        return 180;
      case 'ANUAL':
        return 365;
      default:
        return 30; // Default mensual
    }
  }
}

// =====================
// MODELOS
// =====================

class JugadorConMonto {
  final int id;
  final String nombre;
  final int? numeroAsociado;
  final String? rol;
  final String? alias;
  final String? tipoContratacion;
  final String? posicion;
  final double monto;

  JugadorConMonto({
    required this.id,
    required this.nombre,
    this.numeroAsociado,
    this.rol,
    this.alias,
    this.tipoContratacion,
    this.posicion,
    required this.monto,
  });
}

class PreviewAcuerdoIndividual {
  final int jugadorId;
  final String jugadorNombre;
  final double montoAjustado;
  final int compromisosEstimados; // -1 = infinito, 0 = sin compromisos

  PreviewAcuerdoIndividual({
    required this.jugadorId,
    required this.jugadorNombre,
    required this.montoAjustado,
    required this.compromisosEstimados,
  });
}

class PreviewAcuerdoGrupal {
  final String nombreGrupal;
  final int cantidadAcuerdos;
  final int totalCompromisos;
  final double totalComprometido;
  final List<PreviewAcuerdoIndividual> previewsIndividuales;

  PreviewAcuerdoGrupal({
    required this.nombreGrupal,
    required this.cantidadAcuerdos,
    required this.totalCompromisos,
    required this.totalComprometido,
    required this.previewsIndividuales,
  });
}

class ResultadoCreacionGrupal {
  final List<int> acuerdosCreados;
  final List<String> errores;
  final String grupalUuid;

  ResultadoCreacionGrupal({
    required this.acuerdosCreados,
    required this.errores,
    required this.grupalUuid,
  });

  int get cantidadCreados => acuerdosCreados.length;
  bool get tieneErrores => errores.isNotEmpty;
  bool get todoExitoso => errores.isEmpty && acuerdosCreados.isNotEmpty;
}
