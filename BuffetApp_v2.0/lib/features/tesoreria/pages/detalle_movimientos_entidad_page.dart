import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../core/theme/app_theme.dart';
import '../../../data/dao/db.dart';
import '../../shared/services/movimientos_proyectados_service.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/progress_dialog.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../../shared/format.dart';
import 'detalle_compromiso_page.dart';

/// FASE 35: Pantalla de detalle de movimientos por entidad y mes
/// Muestra todos los movimientos (reales y esperados) de una entidad específica en un mes
/// Permite navegar mes a mes con carrusel
class DetalleMovimientosEntidadPage extends StatefulWidget {
  final int entidadId;
  final int mesInicial;
  final int anioInicial;

  const DetalleMovimientosEntidadPage({
    super.key,
    required this.entidadId,
    required this.mesInicial,
    required this.anioInicial,
  });

  @override
  State<DetalleMovimientosEntidadPage> createState() => _DetalleMovimientosEntidadPageState();
}

class _DetalleMovimientosEntidadPageState extends State<DetalleMovimientosEntidadPage> {
  bool _cargando = true;
  late int _mesActual;
  late int _anioActual;

  // Datos cargados
  String _nombreEntidad = '';
  String _rolEntidad = '';
  List<Map<String, dynamic>> _movimientosReales = [];
  List<Map<String, dynamic>> _movimientosDirectos = [];
  List<MovimientoProyectado> _movimientosEsperados = [];

  // Totales
  double _totalIngresos = 0.0;
  double _totalEgresos = 0.0;

  @override
  void initState() {
    super.initState();
    _mesActual = widget.mesInicial;
    _anioActual = widget.anioInicial;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    try {
      // Cargar información de la entidad
      final db = await AppDatabase.instance();
      final entidadRows = await db.query(
        'entidades_plantel',
        where: 'id = ?',
        whereArgs: [widget.entidadId],
        limit: 1,
      );

      if (entidadRows.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entidad no encontrada')),
          );
        }
        return;
      }

      final entidad = entidadRows.first;
      _nombreEntidad = entidad['nombre']?.toString() ?? 'Sin nombre';
      _rolEntidad = entidad['rol']?.toString() ?? 'OTRO';

      // Obtener IDs de compromisos de esta entidad
      final compromisos = await db.query(
        'compromisos',
        columns: ['id'],
        where: 'entidad_plantel_id = ?',
        whereArgs: [widget.entidadId],
      );

      final compromisoIds = compromisos.map((c) => c['id'] as int).toList();

      // Rango del mes para las queries
      final primerDia = DateTime(_anioActual, _mesActual, 1);
      final ultimoDia = DateTime(_anioActual, _mesActual + 1, 0, 23, 59, 59);
      final fechaInicio = DateFormat('yyyy-MM-dd').format(primerDia);
      final fechaFin = DateFormat('yyyy-MM-dd').format(ultimoDia);

      // ── Movimientos reales (vía compromiso) ──────────────────────────────────
      List<Map<String, dynamic>> movimientosReales = [];
      if (compromisoIds.isNotEmpty) {
        final whereIds = compromisoIds.map((_) => '?').join(',');
        movimientosReales = (await db.rawQuery('''
          SELECT
            em.*,
            mp.descripcion as medio_pago_desc,
            c.nombre as compromiso_nombre
          FROM evento_movimiento em
          LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
          LEFT JOIN compromisos c ON c.id = em.compromiso_id
          WHERE em.compromiso_id IN ($whereIds)
            AND em.created_ts >= ?
            AND em.created_ts <= ?
            AND (em.eliminado IS NULL OR em.eliminado = 0)
          ORDER BY em.created_ts DESC
        ''', [
          ...compromisoIds,
          primerDia.millisecondsSinceEpoch,
          ultimoDia.millisecondsSinceEpoch,
        ])).map((e) => Map<String, dynamic>.from(e)).toList();
      }

      // ── Movimientos directos y de eventos (sin compromiso, por entidad_plantel_id) ─
      final movimientosDirectos = (await db.rawQuery('''
        SELECT
          em.*,
          mp.descripcion as medio_pago_desc
        FROM evento_movimiento em
        LEFT JOIN metodos_pago mp ON mp.id = em.medio_pago_id
        WHERE em.entidad_plantel_id = ?
          AND em.compromiso_id IS NULL
          AND em.fecha BETWEEN ? AND ?
          AND (em.eliminado IS NULL OR em.eliminado = 0)
        ORDER BY em.fecha DESC, em.created_ts DESC
      ''', [widget.entidadId, fechaInicio, fechaFin]))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // ── Movimientos esperados (cuotas ESPERADO del mes) ──────────────────────
      final movimientosEsperados = <MovimientoProyectado>[];
      if (compromisoIds.isNotEmpty) {
        final primerDiaStr = fechaInicio;
        final ultimoDiaStr = fechaFin;

        for (final compromisoId in compromisoIds) {
          final cuotas = await db.rawQuery('''
            SELECT
              cc.*,
              c.tipo,
              c.categoria,
              c.nombre as compromiso_nombre
            FROM compromiso_cuotas cc
            JOIN compromisos c ON c.id = cc.compromiso_id
            WHERE cc.compromiso_id = ?
              AND cc.estado = 'ESPERADO'
              AND cc.fecha_programada BETWEEN ? AND ?
            ORDER BY cc.fecha_programada ASC
          ''', [compromisoId, primerDiaStr, ultimoDiaStr]);

          for (final cuota in cuotas) {
            movimientosEsperados.add(MovimientoProyectado(
              nombre: cuota['compromiso_nombre']?.toString() ?? 'Sin nombre',
              unidadGestionId: 0,
              compromisoId: cuota['compromiso_id'] as int,
              numeroCuota: cuota['numero_cuota'] as int,
              tipo: cuota['tipo']?.toString() ?? 'EGRESO',
              categoria: cuota['categoria']?.toString() ?? 'Sin categoría',
              monto: (cuota['monto_esperado'] as num?)?.toDouble() ?? 0.0,
              fechaVencimiento: DateTime.tryParse(cuota['fecha_programada']?.toString() ?? '') ?? primerDia,
              estado: 'ESPERADO',
            ));
          }
        }
      }

      // Calcular totales (solo movimientos CONFIRMADO)
      double ingresos = 0.0;
      double egresos = 0.0;

      for (final mov in movimientosReales) {
        final estado = (mov['estado'] ?? 'CONFIRMADO').toString();
        if (estado == 'CONFIRMADO') {
          final tipo = mov['tipo']?.toString() ?? '';
          final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;

          if (tipo == 'INGRESO') {
            ingresos += monto;
          } else if (tipo == 'EGRESO') {
            egresos += monto;
          }
        }
      }

      // Sumar movimientos directos
      for (final mov in movimientosDirectos) {
        final estado = (mov['estado'] ?? 'CONFIRMADO').toString();
        if (estado == 'CONFIRMADO') {
          final tipo = mov['tipo']?.toString() ?? '';
          final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;

          if (tipo == 'INGRESO') {
            ingresos += monto;
          } else if (tipo == 'EGRESO') {
            egresos += monto;
          }
        }
      }

      if (mounted) {
        setState(() {
          _movimientosReales = movimientosReales;
          _movimientosDirectos = movimientosDirectos;
          _movimientosEsperados = movimientosEsperados;
          _totalIngresos = ingresos;
          _totalEgresos = egresos;
        });
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'detalle_mov_entidad.cargar_datos',
        error: e,
        stackTrace: stack,
        payload: {
          'entidad_id': widget.entidadId,
          'mes': _mesActual,
          'anio': _anioActual,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar movimientos. Por favor, intente nuevamente.'),
            backgroundColor: AppColors.egreso,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _mesSiguiente() {
    setState(() {
      if (_mesActual == 12) {
        _mesActual = 1;
        _anioActual++;
      } else {
        _mesActual++;
      }
    });
    _cargarDatos();
  }

  void _mesAnterior() {
    setState(() {
      if (_mesActual == 1) {
        _mesActual = 12;
        _anioActual--;
      } else {
        _mesActual--;
      }
    });
    _cargarDatos();
  }

  void _verCompromiso(int compromisoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleCompromisoPage(compromisoId: compromisoId),
      ),
    ).then((_) => _cargarDatos());
  }

  @override
  Widget build(BuildContext context) {
    final hayDatos = _movimientosReales.isNotEmpty || _movimientosDirectos.isNotEmpty || _movimientosEsperados.isNotEmpty;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Movimientos - $_nombreEntidad'),
        backgroundColor: AppColors.info,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ResponsiveContainer(
        maxWidth: 1000,
        child: RefreshIndicator(
          onRefresh: _cargarDatos,
          child: _cargando
              ? SkeletonLoader.list(count: 5)
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      _buildCarruselMes(),
                      _buildInfoEntidad(),
                      _buildResumen(),
                      const Divider(),
                      _movimientosReales.isEmpty && _movimientosDirectos.isEmpty && _movimientosEsperados.isEmpty
                          ? _buildEmpty()
                          : _buildTabla(),
                    ],
                  ),
                ),
        ),
      ),
      floatingActionButton: hayDatos
          ? FloatingActionButton.extended(
              onPressed: _exportarExcel,
              backgroundColor: AppColors.ingreso,
              icon: const Icon(Icons.file_download),
              label: const Text('Exportar Excel'),
            )
          : null,
    );
  }

  Widget _buildCarruselMes() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: context.appColors.infoDim,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 32),
            onPressed: _cargando ? null : _mesAnterior,
            tooltip: 'Mes anterior',
          ),
          Text(
            '${_nombreMes(_mesActual)} $_anioActual',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.appColors.textPrimary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 32),
            onPressed: _cargando ? null : _mesSiguiente,
            tooltip: 'Mes siguiente',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEntidad() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: context.appColors.bgElevated,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _colorPorRol(_rolEntidad),
            radius: 24,
            child: Text(
              _inicialesRol(_rolEntidad),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nombreEntidad,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.appColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _nombreRol(_rolEntidad),
                  style: TextStyle(
                    fontSize: 14,
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen() {
    final saldo = _totalIngresos - _totalEgresos;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildKpiCard(
              'Ingresos',
              Format.money(_totalIngresos),
              Icons.arrow_downward,
              AppColors.ingreso,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildKpiCard(
              'Egresos',
              Format.money(_totalEgresos),
              Icons.arrow_upward,
              AppColors.egreso,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildKpiCard(
              'Saldo',
              Format.money(saldo),
              Icons.account_balance_wallet,
              saldo >= 0 ? AppColors.info : AppColors.advertencia,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String valor, IconData icono, Color color) {
    return Container(
      decoration: AppDecorations.cardOf(context),
      padding: const EdgeInsets.all(12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 16, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      
    );
  }

  Widget _buildEmpty() {
    return const EmptyState(
      icon: Icons.inbox,
      title: 'No hay movimientos en este mes',
    );
  }

  Widget _buildTabla() {
    // Marcar movimientos directos para distinguirlos
    final movimientosRealesMarcados = _movimientosReales.map((m) {
      final copia = Map<String, dynamic>.from(m);
      copia['_esDirecto'] = false;
      return copia;
    }).toList();

    final movimientosDirectosMarcados = _movimientosDirectos.map((m) {
      final copia = Map<String, dynamic>.from(m);
      copia['_esDirecto'] = true;
      return copia;
    }).toList();

    // Combinar movimientos reales, directos y esperados
    final combinados = <dynamic>[
      ...movimientosRealesMarcados,
      ...movimientosDirectosMarcados,
      ..._movimientosEsperados,
    ];

    // Ordenar por fecha descendente
    combinados.sort((a, b) {
      DateTime fechaA;
      DateTime fechaB;

      if (a is Map<String, dynamic>) {
        final ts = a['created_ts'];
        if (ts is int) {
          fechaA = DateTime.fromMillisecondsSinceEpoch(ts);
        } else if (ts is String) {
          fechaA = DateTime.tryParse(ts) ?? DateTime.now();
        } else {
          fechaA = DateTime.now();
        }
      } else if (a is MovimientoProyectado) {
        fechaA = a.fechaVencimiento;
      } else {
        fechaA = DateTime.now();
      }

      if (b is Map<String, dynamic>) {
        final ts = b['created_ts'];
        if (ts is int) {
          fechaB = DateTime.fromMillisecondsSinceEpoch(ts);
        } else if (ts is String) {
          fechaB = DateTime.tryParse(ts) ?? DateTime.now();
        } else {
          fechaB = DateTime.now();
        }
      } else if (b is MovimientoProyectado) {
        fechaB = b.fechaVencimiento;
      } else {
        fechaB = DateTime.now();
      }

      return fechaB.compareTo(fechaA);
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(context.appColors.infoDim),
        columns: [
          DataColumn(label: Text('Fecha', style: AppText.label)),
          DataColumn(label: Text('Origen', style: AppText.label)),
          DataColumn(label: Text('Tipo', style: AppText.label)),
          DataColumn(label: Text('Categoría', style: AppText.label)),
          DataColumn(label: Text('Monto', style: AppText.label)),
          DataColumn(label: Text('Medio Pago', style: AppText.label)),
          DataColumn(label: Text('Estado', style: AppText.label)),
          DataColumn(label: Text('Sync', style: AppText.label)),
          DataColumn(label: Text('Acciones', style: AppText.label)),
        ],
        rows: combinados.map<DataRow>((item) {
          if (item is Map<String, dynamic>) {
            final esDirecto = item['_esDirecto'] == true;
            return _buildMovimientoRealRow(item, esDirecto: esDirecto);
          } else if (item is MovimientoProyectado) {
            return _buildMovimientoEsperadoRow(item);
          } else {
            return const DataRow(cells: [
              DataCell(Text('Error')),
              DataCell(Text('-')),
              DataCell(Text('-')),
              DataCell(Text('-')),
              DataCell(Text('-')),
              DataCell(Text('-')),
              DataCell(Text('-')),
              DataCell(Text('-')),
            ]);
          }
        }).toList(),
      ),
    );
  }

  DataRow _buildMovimientoRealRow(Map<String, dynamic> mov, {required bool esDirecto}) {
    final ts = mov['created_ts'];
    DateTime? fecha;
    if (ts is int) {
      fecha = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      fecha = DateTime.tryParse(ts);
    }

    final tipo = (mov['tipo'] ?? '').toString();
    final categoria = (mov['categoria'] ?? 'Sin categoría').toString();
    final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
    final medioPago = (mov['medio_pago_desc'] ?? '-').toString();
    final estado = (mov['estado'] ?? 'CONFIRMADO').toString();
    final syncEstado = (mov['sync_estado'] ?? 'PENDIENTE').toString();
    final compromisoId = mov['compromiso_id'] as int?;

    return DataRow(
      cells: [
        DataCell(Text(fecha != null ? DateFormat('dd/MM/yyyy').format(fecha) : '-')),
        DataCell(
          esDirecto
              ? const Row(
                  children: [
                    Icon(Icons.description, size: 16, color: AppColors.info),
                    SizedBox(width: 4),
                    Text('Directo', style: TextStyle(fontSize: 11)),
                  ],
                )
              : const Row(
                  children: [
                    Icon(Icons.link, size: 16, color: AppColors.accentDim),
                    SizedBox(width: 4),
                    Text('Compromiso', style: TextStyle(fontSize: 11)),
                  ],
                ),
        ),
        DataCell(
          Row(
            children: [
              Icon(
                tipo == 'INGRESO' ? Icons.arrow_downward : Icons.arrow_upward,
                size: 16,
                color: tipo == 'INGRESO' ? AppColors.ingreso : AppColors.egreso,
              ),
              const SizedBox(width: 4),
              Text(tipo),
            ],
          ),
        ),
        DataCell(Text(categoria)),
        DataCell(
          Text(
            Format.money(monto),
            style: TextStyle(
              color: tipo == 'INGRESO' ? AppColors.ingreso : AppColors.egreso,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(Text(medioPago)),
        DataCell(_buildEstadoBadgeCompact(estado)),
        DataCell(_buildSyncBadgeCompact(syncEstado)),
        DataCell(
          compromisoId != null
              ? TextButton(
                  onPressed: () => _verCompromiso(compromisoId),
                  child: const Text('Ver Compromiso', style: TextStyle(fontSize: 11)),
                )
              : const Text('-', style: TextStyle(color: AppColors.textMuted)),
        ),
      ],
    );
  }

  DataRow _buildMovimientoEsperadoRow(MovimientoProyectado mov) {
    return DataRow(
      color: WidgetStateProperty.all(context.appColors.advertenciaDim),
      cells: [
        DataCell(Text(DateFormat('dd/MM/yyyy').format(mov.fechaVencimiento))),
        DataCell(
          const Row(
            children: [
              Icon(Icons.schedule, size: 16, color: AppColors.advertencia),
              SizedBox(width: 4),
              Text('Esperado', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        DataCell(
          Row(
            children: [
              Icon(
                mov.tipo == 'INGRESO' ? Icons.arrow_downward : Icons.arrow_upward,
                size: 16,
                color: mov.tipo == 'INGRESO' ? AppColors.ingreso : AppColors.egreso,
              ),
              const SizedBox(width: 4),
              Text(mov.tipo),
            ],
          ),
        ),
        DataCell(Text(mov.categoria)),
        DataCell(
          Text(
            Format.money(mov.monto),
            style: TextStyle(
              color: mov.tipo == 'INGRESO' ? AppColors.ingreso : AppColors.egreso,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const DataCell(Text('-')),
        DataCell(_buildEstadoBadgeCompact('ESPERADO')),
        const DataCell(Text('-')),
        DataCell(
          TextButton(
            onPressed: () => _verCompromiso(mov.compromisoId),
            child: const Text('Ver Compromiso', style: TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoBadgeCompact(String estado) {
    IconData icon;
    Color color;

    switch (estado.toUpperCase()) {
      case 'CONFIRMADO':
        icon = Icons.check_circle;
        color = AppColors.ingreso;
        break;
      case 'ESPERADO':
        icon = Icons.schedule;
        color = AppColors.advertencia;
        break;
      case 'CANCELADO':
        icon = Icons.cancel;
        color = AppColors.egreso;
        break;
      default:
        icon = Icons.help;
        color = AppColors.textMuted;
    }

    return Icon(icon, size: 18, color: color);
  }

  Widget _buildSyncBadgeCompact(String syncEstado) {
    IconData icon;
    Color color;

    switch (syncEstado.toUpperCase()) {
      case 'SINCRONIZADA':
        icon = Icons.cloud_done;
        color = AppColors.ingreso;
        break;
      case 'ERROR':
        icon = Icons.cloud_off;
        color = AppColors.egreso;
        break;
      default:
        icon = Icons.cloud_queue;
        color = AppColors.advertencia;
    }

    return Icon(icon, size: 18, color: color);
  }

  String _nombreMes(int mes) {
    const meses = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return meses[mes - 1];
  }

  String _nombreRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return 'Jugador';
      case 'DT':
        return 'Director Técnico';
      case 'AYUDANTE':
        return 'Ayudante de Campo';
      case 'PF':
        return 'Preparador Físico';
      case 'OTRO':
        return 'Otro';
      default:
        return rol;
    }
  }

  String _inicialesRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return 'J';
      case 'DT':
        return 'DT';
      case 'AYUDANTE':
        return 'AC';
      case 'PF':
        return 'PF';
      case 'OTRO':
        return 'O';
      default:
        return '?';
    }
  }

  Color _colorPorRol(String rol) {
    switch (rol) {
      case 'JUGADOR':
        return AppColors.info;
      case 'DT':
        return AppColors.accentDim;
      case 'AYUDANTE':
        return AppColors.accent;
      case 'PF':
        return AppColors.advertencia;
      case 'OTRO':
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }

  Future<void> _exportarExcel() async {
    try {
      ProgressDialog.show(context, 'Generando archivo Excel...');

      final nombreMes = _nombreMes(_mesActual);
      final filename = 'movimientos_${_nombreEntidad.replaceAll(' ', '_')}_${nombreMes}_$_anioActual.xlsx';

      // Preparar datos para Excel
      final List<Map<String, dynamic>> datos = [];

      // Combinar y ordenar todos los movimientos
      final combinados = <dynamic>[
        ..._movimientosReales,
        ..._movimientosDirectos,
        ..._movimientosEsperados,
      ];

      combinados.sort((a, b) {
        DateTime fechaA;
        DateTime fechaB;

        if (a is Map<String, dynamic>) {
          final ts = a['created_ts'];
          if (ts is int) {
            fechaA = DateTime.fromMillisecondsSinceEpoch(ts);
          } else if (ts is String) {
            fechaA = DateTime.tryParse(ts) ?? DateTime.now();
          } else {
            fechaA = DateTime.now();
          }
        } else if (a is MovimientoProyectado) {
          fechaA = a.fechaVencimiento;
        } else {
          fechaA = DateTime.now();
        }

        if (b is Map<String, dynamic>) {
          final ts = b['created_ts'];
          if (ts is int) {
            fechaB = DateTime.fromMillisecondsSinceEpoch(ts);
          } else if (ts is String) {
            fechaB = DateTime.tryParse(ts) ?? DateTime.now();
          } else {
            fechaB = DateTime.now();
          }
        } else if (b is MovimientoProyectado) {
          fechaB = b.fechaVencimiento;
        } else {
          fechaB = DateTime.now();
        }

        return fechaB.compareTo(fechaA);
      });

      // Convertir a formato para Excel
      for (final item in combinados) {
        if (item is Map<String, dynamic>) {
          final ts = item['created_ts'];
          DateTime? fecha;
          if (ts is int) {
            fecha = DateTime.fromMillisecondsSinceEpoch(ts);
          } else if (ts is String) {
            fecha = DateTime.tryParse(ts);
          }

          final esDirecto = item['compromiso_id'] == null;
          
          datos.add({
            'Fecha': fecha != null ? DateFormat('dd/MM/yyyy').format(fecha) : '-',
            'Origen': esDirecto ? 'Directo' : 'Compromiso',
            'Tipo': item['tipo'] ?? '',
            'Categoría': item['categoria'] ?? 'Sin categoría',
            'Monto': (item['monto'] as num?)?.toDouble() ?? 0.0,
            'Medio Pago': item['medio_pago_desc'] ?? '-',
            'Estado': item['estado'] ?? 'CONFIRMADO',
            'Sync': item['sync_estado'] ?? 'PENDIENTE',
          });
        } else if (item is MovimientoProyectado) {
          datos.add({
            'Fecha': DateFormat('dd/MM/yyyy').format(item.fechaVencimiento),
            'Origen': 'Esperado',
            'Tipo': item.tipo,
            'Categoría': item.categoria,
            'Monto': item.monto,
            'Medio Pago': '-',
            'Estado': 'ESPERADO',
            'Sync': '-',
          });
        }
      }

      // Generar Excel
      final excel = excel_pkg.Excel.createExcel();
      excel.delete('Sheet1');
      
      final sheet = excel['Movimientos'];
      
      // Estilos
      final headerStyle = excel_pkg.CellStyle(
        bold: true,
        backgroundColorHex: '#2E7D32',
        fontColorHex: '#FFFFFF',
      );
      
      // Headers
      final headers = ['Fecha', 'Origen', 'Tipo', 'Categoría', 'Monto', 'Medio Pago', 'Estado', 'Sync'];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = headers[i];
        cell.cellStyle = headerStyle;
      }
      
      // Datos
      var rowIndex = 1;
      for (final dato in datos) {
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = dato['Fecha'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = dato['Origen'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = dato['Tipo'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = dato['Categoría'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = dato['Monto'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = dato['Medio Pago'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = dato['Estado'];
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = dato['Sync'];
        rowIndex++;
      }
      
      // Guardar archivo
      final excelBytes = excel.encode();
      if (excelBytes == null) {
        throw Exception('Error al generar archivo Excel');
      }
      
      final cleanFilename = filename.replaceAll('.xlsx', '');
      final filePath = await FileSaver.instance.saveFile(
        name: cleanFilename,
        bytes: Uint8List.fromList(excelBytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );

      ProgressDialog.hide(context);

      // Mostrar diálogo de éxito con opción de abrir
      await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.ingreso, size: 32),
                SizedBox(width: 12),
                Text('Exportación Exitosa'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('El archivo Excel se generó correctamente.'),
                const SizedBox(height: 12),
                Text(
                  'Total movimientos: ${datos.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Ingresos: ${Format.money(_totalIngresos)}',
                  style: TextStyle(color: AppColors.ingreso),
                ),
                Text(
                  'Egresos: ${Format.money(_totalEgresos)}',
                  style: TextStyle(color: AppColors.egreso),
                ),
                const SizedBox(height: 12),
                Text(
                  'Archivo: $filename',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await OpenFilex.open(filePath);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir archivo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ingreso,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
    } catch (e, stack) {
      ProgressDialog.hide(context);
      
      await AppDatabase.logLocalError(
        scope: 'detalle_mov_entidad.exportar_excel',
        error: e,
        stackTrace: stack,
        payload: {
          'entidad_id': widget.entidadId,
          'mes': _mesActual,
          'anio': _anioActual,
        },
      );

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: AppColors.egreso, size: 32),
                SizedBox(width: 12),
                Text('Error'),
              ],
            ),
            content: const Text('No se pudo generar el archivo Excel. Por favor, intente nuevamente.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }
}
