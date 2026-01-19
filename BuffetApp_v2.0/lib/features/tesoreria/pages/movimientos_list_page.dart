import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../shared/services/movimiento_service.dart';
import '../../shared/services/export_service.dart';
import '../../shared/services/tesoreria_sync_service.dart';
import '../../shared/services/movimientos_proyectados_service.dart';
import '../../shared/services/compromisos_service.dart';
import '../../shared/format.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../shared/state/app_settings.dart';
import 'detalle_movimiento_page.dart';
import 'confirmar_movimiento_page.dart';
import 'crear_movimiento_page.dart';
import '../services/categoria_movimiento_service.dart';

/// Pantalla para listar todos los movimientos financieros de una Unidad de Gestión
class MovimientosListPage extends StatefulWidget {
  const MovimientosListPage({super.key});

  @override
  State<MovimientosListPage> createState() => _MovimientosListPageState();
}

class _MovimientosListPageState extends State<MovimientosListPage> {
  final _svc = EventoMovimientoService();
  final _syncSvc = TesoreriaSyncService();
  final _proyectadosSvc = MovimientosProyectadosService.instance;
  final _compromisosService = CompromisosService.instance;
  
  List<Map<String, dynamic>> _movimientos = [];
  List<MovimientoProyectado> _movimientosEsperados = [];
  List<MovimientoProyectado> _movimientosCancelados = [];
  bool _loading = true;
  String? _unidadGestionNombre;
  int _pendientesCount = 0;
  double _saldoArrastre = 0.0;
  
  // Cache de nombres de categorías para evitar lookups repetidos
  final Map<String, String> _categoriasNombresCache = {};
  
  // Filtros
  String? _filtroTipo; // null = todos, 'INGRESO', 'EGRESO'
  String? _filtroEstado; // null = todos, 'CONFIRMADO', 'ESPERADO', 'CANCELADO'
  DateTime _mesSeleccionado = DateTime.now();
  
  // Vista
  bool _vistaTabla = true; // true = tabla, false = tarjetas
  
  // Selecci\u00f3n de movimiento esperado (solo uno a la vez)
  MovimientoProyectado? _movimientoSeleccionado;
  
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    
    try {
      final settings = context.read<AppSettings>();
      final unidadGestionId = settings.unidadGestionActivaId;
      
      if (unidadGestionId != null) {
        // Cargar nombre de Unidad de Gestión
        final db = await AppDatabase.instance();
        final rows = await db.query('unidades_gestion',
            columns: ['nombre'],
            where: 'id=?',
            whereArgs: [unidadGestionId],
            limit: 1);
        if (rows.isNotEmpty) {
          _unidadGestionNombre = (rows.first['nombre'] ?? '').toString();
        }
        
        // Cargar movimientos (aún usa disciplinaId para compatibilidad)
        // TODO: migrar a unidadGestionId cuando la tabla evento_movimiento lo soporte
        final movs = await _svc.listar(disciplinaId: unidadGestionId);
        
        // Calcular movimientos esperados del mes
        final esperados = await _proyectadosSvc.calcularMovimientosEsperadosMes(
          year: _mesSeleccionado.year,
          month: _mesSeleccionado.month,
          unidadGestionId: unidadGestionId,
        );
        
        // Calcular movimientos cancelados del mes (según su fecha programada)
        final cancelados = await _proyectadosSvc.calcularMovimientosCanceladosMes(
          year: _mesSeleccionado.year,
          month: _mesSeleccionado.month,
          unidadGestionId: unidadGestionId,
        );
        
        // Contar pendientes
        final pendientes = await _syncSvc.contarPendientes();
        
        // Buscar saldo inicial configurado para el período
        double saldoArrastre = 0.0;
        
        // Intentar obtener saldo inicial del mes
        final periodoMes = '${_mesSeleccionado.year}-${_mesSeleccionado.month.toString().padLeft(2, '0')}';
        final saldoInicialMes = await AppDatabase.obtenerSaldoInicial(
          unidadGestionId: unidadGestionId,
          periodoTipo: 'MES',
          periodoValor: periodoMes,
        );
        
        if (saldoInicialMes != null) {
          // Usar saldo inicial configurado para el mes
          saldoArrastre = (saldoInicialMes['monto'] as num?)?.toDouble() ?? 0.0;
        } else {
          // Intentar obtener saldo inicial del año
          final periodoAnio = '${_mesSeleccionado.year}';
          final saldoInicialAnio = await AppDatabase.obtenerSaldoInicial(
            unidadGestionId: unidadGestionId,
            periodoTipo: 'ANIO',
            periodoValor: periodoAnio,
          );
          
          if (saldoInicialAnio != null) {
            // Usar saldo inicial del año + movimientos hasta mes anterior
            final saldoInicialBase = (saldoInicialAnio['monto'] as num?)?.toDouble() ?? 0.0;
            final saldoMovimientos = await _svc.calcularSaldoArrastre(
              disciplinaId: unidadGestionId,
              hastaFecha: _mesSeleccionado,
            );
            saldoArrastre = saldoInicialBase + saldoMovimientos;
          } else {
            // No hay saldo inicial configurado, calcular desde el inicio de los movimientos
            saldoArrastre = await _svc.calcularSaldoArrastre(
              disciplinaId: unidadGestionId,
              hastaFecha: _mesSeleccionado,
            );
          }
        }
        
        setState(() {
          _movimientos = movs;
          _movimientosEsperados = esperados;
          _movimientosCancelados = cancelados;
          _pendientesCount = pendientes;
          _saldoArrastre = saldoArrastre;
          _loading = false;
        });
      } else {
        setState(() {
          _movimientos = [];
          _pendientesCount = 0;
          _loading = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
          scope: 'movimientos_list.load', error: e, stackTrace: st);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _movimientosFiltrados {
    var resultado = _movimientos;
    
    // Filtrar por mes
    resultado = resultado.where((m) {
      final ts = m['created_ts'];
      DateTime? fecha;
      if (ts is int) {
        fecha = DateTime.fromMillisecondsSinceEpoch(ts);
      } else if (ts is String) {
        fecha = DateTime.tryParse(ts);
      }
      
      if (fecha == null) return false;
      
      return fecha.year == _mesSeleccionado.year && 
             fecha.month == _mesSeleccionado.month;
    }).toList();
    
    // Filtrar por tipo (Ingreso/Egreso)
    if (_filtroTipo != null) {
      resultado = resultado.where((m) => m['tipo'] == _filtroTipo).toList();
    }
    // Filtrar por estado (solo movimientos confirmados/cancelados)
    if (_filtroEstado != null && _filtroEstado != 'ESPERADO') {
      if (_filtroEstado == 'CONFIRMADO') {
        resultado = resultado.where((m) => (m['estado'] as String? ?? 'CONFIRMADO') == 'CONFIRMADO').toList();
      } else if (_filtroEstado == 'CANCELADO') {
        resultado = resultado.where((m) => (m['estado'] as String?) == 'CANCELADO').toList();
      }
    }
    
    return resultado;
  }
  
  List<MovimientoProyectado> get _esperadosFiltrados {
    var resultado = _movimientosEsperados;
    
    // Filtrar por tipo
    if (_filtroTipo != null) {
      resultado = resultado.where((m) => m.tipo == _filtroTipo).toList();
    }
    
    return resultado;
  }
  
  List<MovimientoProyectado> get _canceladosFiltrados {
    var resultado = _movimientosCancelados;
    
    // Filtrar por tipo
    if (_filtroTipo != null) {
      resultado = resultado.where((m) => m.tipo == _filtroTipo).toList();
    }
    
    return resultado;
  }
  
  // Lista combinada de movimientos reales y esperados
  List<dynamic> get _movimientosCombinados {
    if (_filtroEstado == 'CONFIRMADO') {
      // Solo mostrar movimientos confirmados
      return _movimientosFiltrados;
    } else if (_filtroEstado == 'CANCELADO') {
      // Combinar movimientos cancelados reales con cuotas canceladas
      final combinados = <dynamic>[
        ..._movimientosFiltrados,
        ..._canceladosFiltrados,
      ];
      return combinados;
    } else if (_filtroEstado == 'ESPERADO') {
      // Solo mostrar esperados
      return _esperadosFiltrados;
    } else {
      // Combinar todos (confirmados + esperados + cancelados)
      final combinados = <dynamic>[
        ..._movimientosFiltrados,
        ..._esperadosFiltrados,
        ..._canceladosFiltrados,
      ];
      
      // Ordenar por fecha descendente
      combinados.sort((a, b) {
        DateTime? fechaA;
        DateTime? fechaB;
        
        if (a is Map<String, dynamic>) {
          final ts = a['created_ts'];
          if (ts is int) {
            fechaA = DateTime.fromMillisecondsSinceEpoch(ts);
          }
        } else if (a is MovimientoProyectado) {
          fechaA = a.fechaVencimiento;
        }
        
        if (b is Map<String, dynamic>) {
          final ts = b['created_ts'];
          if (ts is int) {
            fechaB = DateTime.fromMillisecondsSinceEpoch(ts);
          }
        } else if (b is MovimientoProyectado) {
          fechaB = b.fechaVencimiento;
        }
        
        if (fechaA == null && fechaB == null) return 0;
        if (fechaA == null) return 1;
        if (fechaB == null) return -1;
        
        return fechaB.compareTo(fechaA); // Descendente
      });
      
      return combinados;
    }
  }

  double get _totalIngresos {
    return _movimientosFiltrados
        .where((m) => m['tipo'] == 'INGRESO')
        .fold(0.0, (sum, m) => sum + ((m['monto'] as num?)?.toDouble() ?? 0.0));
  }

  double get _totalEgresos {
    return _movimientosFiltrados
        .where((m) => m['tipo'] == 'EGRESO')
        .fold(0.0, (sum, m) => sum + ((m['monto'] as num?)?.toDouble() ?? 0.0));
  }

  double get _saldo => _totalIngresos - _totalEgresos;
  
  // Totales esperados
  double get _totalIngresosEsperados {
    return _esperadosFiltrados
        .where((m) => m.tipo == 'INGRESO')
        .fold(0.0, (sum, m) => sum + m.monto);
  }

  double get _totalEgresosEsperados {
    return _esperadosFiltrados
        .where((m) => m.tipo == 'EGRESO')
        .fold(0.0, (sum, m) => sum + m.monto);
  }

  double get _saldoEsperado => _totalIngresosEsperados - _totalEgresosEsperados;

  /// Obtiene el nombre de una categoría por su código, con cache
  Future<String> _obtenerNombreCategoria(String? codigo) async {
    if (codigo == null || codigo.isEmpty) return 'Sin categoría';
    
    // Verificar cache
    if (_categoriasNombresCache.containsKey(codigo)) {
      return _categoriasNombresCache[codigo]!;
    }
    
    // Buscar en BD
    final nombre = await CategoriaMovimientoService.obtenerNombrePorCodigo(codigo);
    final nombreFinal = nombre ?? codigo; // Fallback al código si no se encuentra
    
    // Guardar en cache
    _categoriasNombresCache[codigo] = nombreFinal;
    
    return nombreFinal;
  }

  Future<void> _sincronizarPendientes() async {
    // Verificar si hay pendientes
    if (_pendientesCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay movimientos pendientes')),
      );
      return;
    }

    // Verificar conexión
    final conectado = await _syncSvc.verificarConexion();
    if (!conectado) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.orange),
                SizedBox(width: 8),
                Text('Sin conexión'),
              ],
            ),
            content: const Text(
              'No se pudo conectar con Supabase.\n\n'
              'Verificá tu conexión a internet e intentá nuevamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Mostrar diálogo de progreso
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Sincronizando $_pendientesCount movimientos...'),
          ],
        ),
      ),
    );

    try {
      final resultado = await _syncSvc.syncMovimientosPendientes();

      if (mounted) {
        // Cerrar progreso
        Navigator.pop(context);

        // Mostrar resultado
        final exitosos = resultado['exitosos'] ?? 0;
        final fallidos = resultado['fallidos'] ?? 0;
        final total = resultado['total'] ?? 0;

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  fallidos == 0 ? Icons.check_circle : Icons.warning,
                  color: fallidos == 0 ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text('Sincronización completada'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total procesados: $total'),
                Text('✓ Exitosos: $exitosos', style: const TextStyle(color: Colors.green)),
                if (fallidos > 0)
                  Text('✗ Fallidos: $fallidos', style: const TextStyle(color: Colors.red)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );

        // Recargar lista
        await _load();
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'movimientos_list.sincronizar',
        error: e,
        stackTrace: st,
      );

      if (mounted) {
        // Cerrar progreso
        Navigator.pop(context);

        // Mostrar error
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error al sincronizar'),
              ],
            ),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _exportarExcel() async {
    if (_movimientosFiltrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay movimientos para exportar')),
      );
      return;
    }
    
    // Mostrar diálogo de progreso
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generando archivo Excel...'),
          ],
        ),
      ),
    );
    
    try {
      final mesStr = DateFormat('yyyy-MM').format(_mesSeleccionado);
      final filename = 'movimientos_${_unidadGestionNombre ?? 'tesoreria'}_$mesStr';
      
      final savedPath = await ExportService().exportMovimientosExcel(
        movimientos: _movimientosFiltrados,
        filename: filename,
        unidadGestionNombre: _unidadGestionNombre,
        mes: _mesSeleccionado,
        saldoInicial: _saldoArrastre,
        totalIngresos: _totalIngresos,
        totalEgresos: _totalEgresos,
        saldoFinal: _saldo + _saldoArrastre,
        proyeccionPendiente: _saldoEsperado,
      );
      
      if (mounted) {
        // Cerrar diálogo de progreso
        Navigator.pop(context);
        
        // Mostrar diálogo de éxito con opciones
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Exportación exitosa'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Se exportaron ${_movimientosFiltrados.length} movimientos'),
                const SizedBox(height: 8),
                const Text('Ubicación:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  savedPath,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final result = await OpenFilex.open(savedPath);
                    if (result.type != ResultType.done && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('No se pudo abrir: ${result.message}'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error al abrir: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir archivo'),
              ),
            ],
          ),
        );
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'movimientos_list.exportar',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        // Cerrar diálogo de progreso
        Navigator.pop(context);
        
        // Mostrar error
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error al exportar'),
              ],
            ),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final unidadGestionId = settings.unidadGestionActivaId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimientos'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          // Botón de sincronización con badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.cloud_upload),
                tooltip: 'Sincronizar con Supabase',
                onPressed: _sincronizarPendientes,
              ),
              if (_pendientesCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _pendientesCount > 99 ? '99+' : '$_pendientesCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: Icon(_vistaTabla ? Icons.view_list : Icons.table_chart),
            tooltip: _vistaTabla ? 'Ver como tarjetas' : 'Ver como tabla',
            onPressed: () {
              setState(() {
                _vistaTabla = !_vistaTabla;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Exportar Excel',
            onPressed: _exportarExcel,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : unidadGestionId == null
              ? _buildSinUnidadGestion()
              : Column(
                  children: [
                    // Header con totales
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.shade700,
                            Colors.green.shade500,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _unidadGestionNombre ?? 'Cargando...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              DateFormat('MMMM yyyy', 'es_AR').format(_mesSeleccionado),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Saldo de arrastre (saldo inicial del mes)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.history,
                                        color: Colors.white.withOpacity(0.8),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Saldo inicial (arrastre):',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    Format.money(_saldoArrastre),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.95),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 8),
                            Divider(color: Colors.white.withOpacity(0.3), height: 1),
                            const SizedBox(height: 12),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTotalCard(
                                    'Ingresos',
                                    _totalIngresos,
                                    Icons.arrow_downward,
                                    Colors.green.shade100,
                                    Colors.green.shade900,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTotalCard(
                                    'Egresos',
                                    _totalEgresos,
                                    Icons.arrow_upward,
                                    Colors.red.shade100,
                                    Colors.red.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _saldo >= 0
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Saldo Real:',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    Format.money(_saldo),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Proyección (esperados)
                            if (_movimientosEsperados.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => _mostrarDetalleProyeccion(),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.pending_actions, color: Colors.white.withOpacity(0.8), size: 20),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Proyección pendiente:',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.9),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_movimientosEsperados.length} compromiso${_movimientosEsperados.length != 1 ? 's' : ''}',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.7),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            Format.money(_saldoEsperado),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.chevron_right,
                                            color: Colors.white.withOpacity(0.6),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    // Selector de Mes
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () async {
                              setState(() {
                                _mesSeleccionado = DateTime(
                                  _mesSeleccionado.year,
                                  _mesSeleccionado.month - 1,
                                );
                              });
                              await _load(); // Recargar movimientos del nuevo mes
                            },
                            tooltip: 'Mes anterior',
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                DateFormat('MMMM yyyy', 'es_AR').format(_mesSeleccionado),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () async {
                              setState(() {
                                _mesSeleccionado = DateTime(
                                  _mesSeleccionado.year,
                                  _mesSeleccionado.month + 1,
                                );
                              });
                              await _load(); // Recargar movimientos del nuevo mes
                            },
                            tooltip: 'Mes siguiente',
                          ),
                          IconButton(
                            icon: const Icon(Icons.today),
                            onPressed: () async {
                              setState(() {
                                _mesSeleccionado = DateTime.now();
                              });
                              await _load(); // Recargar movimientos del mes actual
                            },
                            tooltip: 'Mes actual',
                          ),
                        ],
                      ),
                    ),
                    
                    // Filtros
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          // Filtro por tipo
                          SegmentedButton<String?>(
                            segments: const [
                              ButtonSegment(
                                value: null,
                                label: Text('Todos'),
                                icon: Icon(Icons.list),
                              ),
                              ButtonSegment(
                                value: 'INGRESO',
                                label: Text('Ingresos'),
                                icon: Icon(Icons.arrow_downward),
                              ),
                              ButtonSegment(
                                value: 'EGRESO',
                                label: Text('Egresos'),
                                icon: Icon(Icons.arrow_upward),
                              ),
                            ],
                            selected: {_filtroTipo},
                            onSelectionChanged: (Set<String?> selected) {
                              setState(() => _filtroTipo = selected.first);
                            },
                          ),
                          const SizedBox(height: 8),
                          // Filtro por estado
                          SegmentedButton<String?>(
                            segments: const [
                              ButtonSegment(
                                value: null,
                                label: Text('Todos'),
                              ),
                              ButtonSegment(
                                value: 'CONFIRMADO',
                                label: Text('Confirmados'),
                                icon: Icon(Icons.check_circle, size: 16),
                              ),
                              ButtonSegment(
                                value: 'ESPERADO',
                                label: Text('Esperados'),
                                icon: Icon(Icons.pending, size: 16),
                              ),
                              ButtonSegment(
                                value: 'CANCELADO',
                                label: Text('Cancelados'),
                                icon: Icon(Icons.cancel, size: 16),
                              ),
                            ],
                            selected: {_filtroEstado},
                            onSelectionChanged: (Set<String?> selected) {
                              setState(() => _filtroEstado = selected.first);
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // Lista
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _movimientosCombinados.isEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  return SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.inbox_outlined,
                                              size: 64,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              _filtroEstado == 'ESPERADO'
                                                  ? 'No hay movimientos esperados'
                                                  : _filtroTipo == null
                                                  ? 'No hay movimientos registrados'
                                                  : 'No hay ${_filtroTipo == 'INGRESO' ? 'ingresos' : 'egresos'} registrados',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : _vistaTabla
                                ? SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: _buildMovimientosTable(),
                                    ),
                                  )
                                : ListView.builder(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _movimientosCombinados.length,
                                    itemBuilder: (context, index) {
                                      final item = _movimientosCombinados[index];
                                      if (item is Map<String, dynamic>) {
                                        return _buildMovimientoCard(item);
                                      } else if (item is MovimientoProyectado) {
                                        return _buildMovimientoEsperadoCard(item);
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _movimientoSeleccionado != null ? _buildBottomActionBar() : null,
    );
  }

  Widget _buildBottomActionBar() {
    final esCancelado = _movimientoSeleccionado?.estado == 'CANCELADO';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: esCancelado
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _verDetallesMovimientoCancelado,
                      icon: const Icon(Icons.info_outline, color: Colors.white),
                      label: const Text('Ver Detalles'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _reactivarMovimientoSeleccionado,
                      icon: const Icon(Icons.restore, color: Colors.white),
                      label: const Text('Reactivar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelarMovimientoSeleccionado,
                      icon: const Icon(Icons.cancel, color: Colors.white),
                      label: const Text('Cancelar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _confirmarMovimientoSeleccionado,
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: const Text('Confirmar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMovimientosTable() {
    return DataTable(
      columnSpacing: 16,
      headingRowColor: WidgetStateProperty.all(Colors.green.shade50),
      border: TableBorder.all(color: Colors.grey.shade300, width: 1),
      columns: const [
        DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Monto', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
        DataColumn(label: Text('Medio Pago', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Compromiso', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Observación', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Adjunto', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
        DataColumn(label: Text('Sync', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: _movimientosCombinados.map((item) {
        // Determinar si es movimiento real o esperado
        if (item is MovimientoProyectado) {
          // Movimiento esperado o cancelado - fila con estilo atenuado
          final esIngreso = item.tipo == 'INGRESO';
          final esCancelado = item.estado == 'CANCELADO';
          return DataRow(
            selected: _movimientoSeleccionado == item,
            color: WidgetStateProperty.all(
              esCancelado ? Colors.red.shade50 : Colors.grey.shade100
            ),
            onSelectChanged: (_) {
              // Seleccionar/deseleccionar movimiento (cancelados también se pueden seleccionar para reactivar)
              setState(() {
                if (_movimientoSeleccionado == item) {
                  _movimientoSeleccionado = null;
                } else {
                  _movimientoSeleccionado = item;
                }
              });
            },
            cells: [
              DataCell(
                Text(
                  DateFormat('dd/MM/yyyy').format(item.fechaVencimiento),
                  style: TextStyle(
                    fontSize: 11,
                    color: esCancelado ? Colors.red.shade400 : Colors.grey.shade600,
                    decoration: esCancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: esCancelado
                        ? Colors.red.shade100
                        : esIngreso ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        esCancelado
                            ? Icons.cancel
                            : esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 14,
                        color: esCancelado
                            ? Colors.red.shade400
                            : esIngreso ? Colors.green.shade300 : Colors.red.shade300,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.tipo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: esCancelado
                              ? Colors.red.shade400
                              : esIngreso ? Colors.green.shade600 : Colors.red.shade600,
                          decoration: esCancelado ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.categoria,
                      style: TextStyle(
                        fontSize: 12,
                        color: esCancelado ? Colors.red.shade400 : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                        decoration: esCancelado ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (item.numeroCuota != null && item.totalCuotas != null)
                      Text(
                        'Cuota ${item.numeroCuota}/${item.totalCuotas}',
                        style: TextStyle(
                          fontSize: 10,
                          color: esCancelado ? Colors.red.shade300 : Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                          decoration: esCancelado ? TextDecoration.lineThrough : null,
                        ),
                      ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  Format.money(item.monto),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: esCancelado
                        ? Colors.red.shade400
                        : esIngreso ? Colors.green.shade600 : Colors.red.shade600,
                    decoration: esCancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const DataCell(Text('-', style: TextStyle(fontSize: 12))),
              DataCell(
                Container(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    item.nombre,
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              DataCell(
                Text(
                  item.observaciones ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const DataCell(Icon(Icons.remove, size: 16, color: Colors.grey)),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      esCancelado ? Icons.cancel : Icons.pending,
                      size: 14,
                      color: esCancelado ? Colors.red.shade700 : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      esCancelado ? 'CANCELADO' : 'ESPERADO',
                      style: TextStyle(
                        fontSize: 11,
                        color: esCancelado ? Colors.red.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.remove, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'N/A',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        
        // Movimiento real
        final mov = item as Map<String, dynamic>;
        final id = mov['id'] as int?;
        final tipo = (mov['tipo'] ?? '').toString();
        final esIngreso = tipo == 'INGRESO';
        final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
        final categoria = (mov['categoria'] ?? '').toString();
        final medioPago = (mov['medio_pago_desc'] ?? '').toString();
        final obs = (mov['observacion'] ?? '').toString();
        final ts = mov['created_ts'];
        final syncEstado = (mov['sync_estado'] ?? '').toString();
        final tieneAdjunto = (mov['archivo_local_path'] ?? '').toString().isNotEmpty;
        final compromisoNombre = (mov['compromiso_nombre'] ?? '').toString();
        
        DateTime? fecha;
        if (ts is int) {
          fecha = DateTime.fromMillisecondsSinceEpoch(ts);
        } else if (ts is String) {
          fecha = DateTime.tryParse(ts);
        }

        Color? rowColor;
        if (syncEstado.toUpperCase() == 'ERROR') {
          rowColor = Colors.red.shade50;
        } else if (syncEstado.toUpperCase() == 'PENDIENTE') {
          rowColor = Colors.orange.shade50;
        }

        return DataRow(
          color: rowColor != null ? WidgetStateProperty.all(rowColor) : null,
          onSelectChanged: id != null ? (_) async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetalleMovimientoPage(movimientoId: id),
              ),
            );
            if (result == true && mounted) {
              await _load();
            }
          } : null,
          cells: [
            DataCell(
              Text(
                fecha != null 
                    ? DateFormat('dd/MM/yy\nHH:mm').format(fecha)
                    : '-',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: esIngreso 
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 14,
                      color: esIngreso ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tipo,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: esIngreso ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DataCell(
              FutureBuilder<String>(
                future: _obtenerNombreCategoria(categoria),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? categoria,
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
            DataCell(
              Text(
                Format.money(monto),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: esIngreso ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payment, size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    medioPago.isEmpty ? '-' : medioPago,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            DataCell(
              compromisoNombre.isNotEmpty
                  ? Container(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_note, size: 12, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              compromisoNombre,
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Text('-', style: TextStyle(fontSize: 12)),
            ),
            DataCell(
              Container(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  obs.isEmpty ? '-' : obs,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
            DataCell(
              tieneAdjunto
                  ? const Icon(Icons.attach_file, size: 16, color: Colors.blue)
                  : const Icon(Icons.remove, size: 16, color: Colors.grey),
            ),
            DataCell(
              _buildEstadoBadge(mov['estado'] as String? ?? 'CONFIRMADO'),
            ),
            DataCell(
              _buildSyncBadge(syncEstado),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildEstadoBadge(String estado) {
    IconData icon;
    Color color;
    String text;

    switch (estado.toUpperCase()) {
      case 'CONFIRMADO':
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Confirmado';
        break;
      case 'ESPERADO':
        icon = Icons.pending;
        color = Colors.orange;
        text = 'Esperado';
        break;
      case 'CANCELADO':
        icon = Icons.cancel;
        color = Colors.red;
        text = 'Cancel.';
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
        text = estado;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSyncBadge(String estado) {
    IconData icon;
    Color color;
    String text;

    switch (estado.toUpperCase()) {
      case 'SINCRONIZADA':
        icon = Icons.cloud_done;
        color = Colors.green;
        text = 'OK';
        break;
      case 'ERROR':
        icon = Icons.error_outline;
        color = Colors.red;
        text = 'Error';
        break;
      default:
        icon = Icons.cloud_queue;
        color = Colors.orange;
        text = 'Pend';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSinUnidadGestion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber,
              size: 64,
              color: Colors.orange.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Seleccioná una Unidad de Gestión para ver sus movimientos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard(
    String label,
    double amount,
    IconData icon,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            Format.money(amount),
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientoCard(Map<String, dynamic> mov) {
    final id = mov['id'] as int?;
    final tipo = (mov['tipo'] ?? '').toString();
    final esIngreso = tipo == 'INGRESO';
    final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
    final categoria = (mov['categoria'] ?? '').toString();
    final medioPago = (mov['medio_pago_desc'] ?? '').toString();
    final obs = (mov['observacion'] ?? '').toString();
    final ts = mov['created_ts'];
    final syncEstado = (mov['sync_estado'] ?? '').toString();
    final estado = (mov['estado'] ?? 'CONFIRMADO').toString();
    final tieneAdjunto = (mov['archivo_local_path'] ?? '').toString().isNotEmpty;
    final compromisoNombre = (mov['compromiso_nombre'] ?? '').toString();
    
    DateTime? fecha;
    if (ts is int) {
      fecha = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      fecha = DateTime.tryParse(ts);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: id != null ? () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetalleMovimientoPage(movimientoId: id),
            ),
          );
          if (result == true && mounted) {
            await _load();
          }
        } : null,
        onLongPress: id != null ? () async {
          await _mostrarOpcionesMovimiento(mov);
        } : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: esIngreso 
                ? Colors.green.withOpacity(0.2)
                : Colors.red.withOpacity(0.2),
            child: Icon(
              esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
              color: esIngreso ? Colors.green : Colors.red,
            ),
          ),
          title: FutureBuilder<String>(
            future: _obtenerNombreCategoria(categoria),
            builder: (context, snapshot) {
              final nombreCategoria = snapshot.data ?? categoria;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      nombreCategoria.isEmpty ? tipo : nombreCategoria,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    Format.money(monto),
                    style: TextStyle(
                      color: esIngreso ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              );
            },
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compromisoNombre.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.event_note, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          compromisoNombre,
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              if (medioPago.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.payment, size: 14),
                    const SizedBox(width: 4),
                    Text(medioPago, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              if (tieneAdjunto)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, size: 14, color: Colors.blue),
                      const SizedBox(width: 4),
                      const Text(
                        'Tiene adjunto',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              if (obs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    obs,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (fecha != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(fecha),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEstadoBadgeCompact(estado),
              const SizedBox(width: 4),
              _buildSyncBadgeCompact(syncEstado),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncBadgeCompact(String syncEstado) {
    IconData icon;
    Color color;

    switch (syncEstado.toUpperCase()) {
      case 'SINCRONIZADA':
        icon = Icons.cloud_done;
        color = Colors.green;
        break;
      case 'ERROR':
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.cloud_queue;
        color = Colors.orange;
    }

    return Icon(icon, size: 18, color: color);
  }
  
  Widget _buildEstadoBadgeCompact(String estado) {
    IconData icon;
    Color color;

    switch (estado.toUpperCase()) {
      case 'CONFIRMADO':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'ESPERADO':
        icon = Icons.pending;
        color = Colors.orange;
        break;
      case 'CANCELADO':
        icon = Icons.cancel;
        color = Colors.red;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return Icon(icon, size: 18, color: color);
  }
  
  Widget _buildMovimientoEsperadoCard(MovimientoProyectado mov) {
    final esIngreso = mov.tipo == 'INGRESO';
    final esCancelado = mov.estado == 'CANCELADO';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: esCancelado ? Colors.red.shade50 : Colors.grey.shade100,
      child: InkWell(
        onTap: esCancelado ? null : () async {
          // Navegar a confirmar movimiento (solo si no está cancelado)
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConfirmarMovimientoPage(
                compromisoId: mov.compromisoId,
                fechaVencimiento: mov.fechaVencimiento,
                montoSugerido: mov.monto,
                tipo: mov.tipo,
                categoria: mov.categoria,
                numeroCuota: mov.numeroCuota,
              ),
            ),
          );
          if (result == true) {
            await _load();
          }
        },
        onLongPress: esCancelado
            ? () async {
                // Reactivar cuota cancelada
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reactivar compromiso'),
                    content: Text(
                      '¿Desea reactivar este ${mov.tipo.toLowerCase()} de ${Format.money(mov.monto)}?\n\n'
                      'Volverá a aparecer como pendiente en las proyecciones.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('No'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.green),
                        child: const Text('Sí, reactivar'),
                      ),
                    ],
                  ),
                );

                if (confirmar == true) {
                  try {
                    final db = await AppDatabase.instance();
                    final cuotas = await db.query(
                      'compromiso_cuotas',
                      where: 'compromiso_id = ? AND numero_cuota = ?',
                      whereArgs: [mov.compromisoId, mov.numeroCuota],
                      limit: 1,
                    );
                    
                    if (cuotas.isEmpty) {
                      throw StateError('No se encontró la cuota para reactivar');
                    }
                    
                    final cuotaId = cuotas.first['id'] as int;
                    
                    // Cambiar estado de CANCELADO a ESPERADO
                    await _compromisosService.actualizarEstadoCuota(
                      cuotaId,
                      'ESPERADO',
                    );

                    await _load();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Compromiso reactivado correctamente'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error al reactivar: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              }
            : () async {
          // Cancelar movimiento esperado (solo si no está cancelado)
          final observacionController = TextEditingController();
          final confirmar = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cancelar movimiento'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Desea cancelar este ${mov.tipo.toLowerCase()} de ${Format.money(mov.monto)}?\n\n'
                    'Se registrará como cancelado y no volverá a aparecer en las proyecciones.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: observacionController,
                    decoration: const InputDecoration(
                      labelText: 'Observación (opcional)',
                      hintText: 'Motivo de la cancelación',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    maxLength: 200,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Sí, cancelar'),
                ),
              ],
            ),
          );

          if (confirmar == true) {
            try {
              // Obtener el cuotaId desde compromiso_cuotas
              final db = await AppDatabase.instance();
              final cuotas = await db.query(
                'compromiso_cuotas',
                where: 'compromiso_id = ? AND numero_cuota = ?',
                whereArgs: [mov.compromisoId, mov.numeroCuota],
                limit: 1,
              );
              
              if (cuotas.isEmpty) {
                throw StateError('No se encontró la cuota para cancelar');
              }
              
              final cuotaId = cuotas.first['id'] as int;
              
              // Actualizar estado de la cuota a CANCELADO
              await _compromisosService.actualizarEstadoCuota(
                cuotaId,
                'CANCELADO',
              );
              
              // Si hay observación, actualizar también la observación de la cuota
              if (observacionController.text.trim().isNotEmpty) {
                await db.update(
                  'compromiso_cuotas',
                  {
                    'observacion_cancelacion': observacionController.text.trim(),
                    'updated_ts': DateTime.now().millisecondsSinceEpoch,
                  },
                  where: 'id = ?',
                  whereArgs: [cuotaId],
                );
              }

              // Recargar lista
              await _load();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cuota cancelada correctamente'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e, st) {
              // Loguear error técnico
              await AppDatabase.logLocalError(
                scope: 'movimientos_list.cancelar_compromiso',
                error: e,
                stackTrace: st,
                payload: {
                  'compromiso_id': mov.compromisoId,
                  'numero_cuota': mov.numeroCuota,
                },
              );
              
              if (mounted) {
                // Mostrar modal de error amigable
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.error, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Error al cancelar'),
                      ],
                    ),
                    content: const Text(
                      'No se pudo cancelar el compromiso.\n\n'
                      'Por favor, intentá nuevamente. Si el problema persiste, '
                      'contactá al soporte técnico.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              }
            }
          }
        },
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: esCancelado
                ? Colors.red.withOpacity(0.2)
                : esIngreso 
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
            child: Icon(
              esCancelado
                  ? Icons.cancel
                  : esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
              color: esCancelado
                  ? Colors.red.shade400
                  : esIngreso ? Colors.green.shade300 : Colors.red.shade300,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  mov.descripcion,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: esCancelado ? Colors.red.shade700 : Colors.grey.shade700,
                    decoration: esCancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Text(
                Format.money(mov.monto),
                style: TextStyle(
                  color: esCancelado
                      ? Colors.red.shade400
                      : esIngreso ? Colors.green.shade600 : Colors.red.shade600,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  decoration: esCancelado ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mov.categoria.isNotEmpty)
                Text(
                  mov.categoria,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    esCancelado ? Icons.cancel : Icons.pending,
                    size: 14,
                    color: esCancelado ? Colors.red.shade400 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    esCancelado
                        ? 'Cancelado - Vencimiento: ${DateFormat('dd/MM/yyyy').format(mov.fechaVencimiento)}'
                        : 'Vence: ${DateFormat('dd/MM/yyyy').format(mov.fechaVencimiento)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: esCancelado ? Colors.red.shade600 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (mov.numeroCuota != null && mov.totalCuotas != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Cuota ${mov.numeroCuota}/${mov.totalCuotas}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Toque para confirmar • Mantenga presionado para cancelar',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          trailing: Chip(
            label: const Text('ESPERADO', style: TextStyle(fontSize: 10)),
            backgroundColor: Colors.orange.shade100,
            labelStyle: TextStyle(color: Colors.orange.shade900),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
  
  /// Muestra diálogo con detalle de movimientos proyectados
  void _mostrarDetalleProyeccion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.pending_actions, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Movimientos Esperados'),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Resumen
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total compromisos:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${_movimientosEsperados.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Impacto proyectado:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          Format.money(_saldoEsperado),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _saldoEsperado >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Detalle:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              
              // Lista de movimientos esperados
              Flexible(
                child: _movimientosEsperados.isEmpty
                    ? const Center(child: Text('No hay movimientos esperados'))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _movimientosEsperados.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final mov = _movimientosEsperados[index];
                          final esIngreso = mov.tipo == 'INGRESO';
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: esIngreso 
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.red.withOpacity(0.15),
                              child: Icon(
                                esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                                size: 16,
                                color: esIngreso ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(
                              mov.nombre,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (mov.categoria.isNotEmpty)
                                  Text(
                                    mov.categoria,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                Text(
                                  'Vence: ${DateFormat('dd/MM/yy').format(mov.fechaVencimiento)}',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                ),
                                if (mov.numeroCuota != null && mov.totalCuotas != null)
                                  Text(
                                    'Cuota ${mov.numeroCuota}/${mov.totalCuotas}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Text(
                              Format.money(mov.monto),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: esIngreso ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                            onTap: () async {
                              // Cerrar diálogo actual
                              Navigator.pop(ctx);
                              
                              // Navegar a confirmar movimiento
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ConfirmarMovimientoPage(
                                    compromisoId: mov.compromisoId,
                                    fechaVencimiento: mov.fechaVencimiento,
                                    montoSugerido: mov.monto,
                                    tipo: mov.tipo,
                                    categoria: mov.categoria,
                                    numeroCuota: mov.numeroCuota,
                                  ),
                                ),
                              );
                              if (result == true) {
                                await _load();
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarOpcionesMovimiento(Map<String, dynamic> mov) async {
    final compromisoId = mov['compromiso_id'] as int?;
    final estado = (mov['estado'] ?? 'CONFIRMADO').toString();
    
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (estado == 'CANCELADO' && compromisoId != null)
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.green),
                title: const Text('Reactivar compromiso'),
                subtitle: const Text('Cambiar estado a ESPERADO'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _reactivarCompromisoDeMovimiento(mov);
                },
              )
            else if (estado != 'CANCELADO')
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Editar movimiento'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _editarMovimiento(mov);
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cerrar'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarMovimiento(Map<String, dynamic> mov) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CrearMovimientoPage(movimientoExistente: mov),
      ),
    );
    
    if (result == true && mounted) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimiento actualizado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _reactivarCompromisoDeMovimiento(Map<String, dynamic> mov) async {
    final compromisoId = mov['compromiso_id'] as int?;
    
    if (compromisoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este movimiento no está asociado a un compromiso'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivar compromiso'),
        content: const Text(
          '¿Desea reactivar este compromiso?\n\n'
          'Volverá a aparecer como pendiente en las proyecciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Sí, reactivar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      // Buscar la cuota asociada al movimiento
      final db = await AppDatabase.instance();
      
      // Obtener información del compromiso desde el movimiento
      final cuotas = await db.rawQuery('''
        SELECT cc.id, cc.numero_cuota
        FROM compromiso_cuotas cc
        WHERE cc.compromiso_id = ? 
          AND cc.estado = 'CANCELADO'
        ORDER BY cc.numero_cuota
      ''', [compromisoId]);
      
      if (cuotas.isEmpty) {
        throw StateError('No se encontró ninguna cuota cancelada para este compromiso');
      }
      
      // Mostrar selector si hay múltiples cuotas canceladas
      int? cuotaId;
      if (cuotas.length == 1) {
        cuotaId = cuotas.first['id'] as int;
      } else {
        final seleccionada = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Seleccionar cuota'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: cuotas.map((c) {
                final numCuota = c['numero_cuota'] as int;
                final id = c['id'] as int;
                return ListTile(
                  title: Text('Cuota $numCuota'),
                  onTap: () => Navigator.pop(ctx, id),
                );
              }).toList(),
            ),
          ),
        );
        
        if (seleccionada == null) return;
        cuotaId = seleccionada;
      }
      
      // Actualizar estado a ESPERADO
      await _compromisosService.actualizarEstadoCuota(
        cuotaId,
        'ESPERADO',
      );

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compromiso reactivado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reactivar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelarMovimientoSeleccionado() async {
    if (_movimientoSeleccionado == null) return;
    
    final mov = _movimientoSeleccionado!;
    final observacionController = TextEditingController();
    
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar movimiento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Desea cancelar este ${mov.tipo.toLowerCase()} de ${Format.money(mov.monto)}?\n\n'
              'Se registrará como cancelado y no volverá a aparecer en las proyecciones.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: observacionController,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
                hintText: 'Motivo de la cancelación',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        // Obtener el cuotaId desde compromiso_cuotas
        final db = await AppDatabase.instance();
        final cuotas = await db.query(
          'compromiso_cuotas',
          where: 'compromiso_id = ? AND numero_cuota = ?',
          whereArgs: [mov.compromisoId, mov.numeroCuota],
          limit: 1,
        );
        
        if (cuotas.isEmpty) {
          throw StateError('No se encontró la cuota para cancelar');
        }
        
        final cuotaId = cuotas.first['id'] as int;
        
        // Actualizar estado de la cuota a CANCELADO
        await _compromisosService.actualizarEstadoCuota(
          cuotaId,
          'CANCELADO',
        );
        
        // Si hay observación, actualizar también la observación de la cuota
        if (observacionController.text.trim().isNotEmpty) {
          await db.update(
            'compromiso_cuotas',
            {
              'observacion_cancelacion': observacionController.text.trim(),
              'updated_ts': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [cuotaId],
          );
        }

        // Limpiar selección
        setState(() {
          _movimientoSeleccionado = null;
        });

        // Recargar lista
        await _load();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cuota cancelada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e, st) {
        // Loguear error técnico
        await AppDatabase.logLocalError(
          scope: 'movimientos_list.cancelar_seleccionado',
          error: e,
          stackTrace: st,
          payload: {
            'compromiso_id': mov.compromisoId,
            'numero_cuota': mov.numeroCuota,
          },
        );
        
        if (mounted) {
          // Mostrar modal de error amigable
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Error al cancelar'),
                ],
              ),
              content: const Text(
                'No se pudo cancelar el compromiso.\n\n'
                'Por favor, intentá nuevamente. Si el problema persiste, '
                'contactá al soporte técnico.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmarMovimientoSeleccionado() async {
    if (_movimientoSeleccionado == null) return;
    
    final mov = _movimientoSeleccionado!;
    
    // Limpiar selección
    setState(() {
      _movimientoSeleccionado = null;
    });
    
    // Navegar a confirmar movimiento
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmarMovimientoPage(
          compromisoId: mov.compromisoId,
          fechaVencimiento: mov.fechaVencimiento,
          montoSugerido: mov.monto,
          tipo: mov.tipo,
          categoria: mov.categoria,
          numeroCuota: mov.numeroCuota,
        ),
      ),
    );
    
    if (result == true) {
      await _load();
    }
  }

  Future<void> _verDetallesMovimientoCancelado() async {
    if (_movimientoSeleccionado == null) return;
    
    final mov = _movimientoSeleccionado!;
    
    // Obtener observación de cancelación desde la BD
    String? observacionCancelacion;
    DateTime? fechaCancelacion;
    
    try {
      final db = await AppDatabase.instance();
      final cuotas = await db.query(
        'compromiso_cuotas',
        columns: ['observacion_cancelacion', 'updated_ts'],
        where: 'compromiso_id = ? AND numero_cuota = ?',
        whereArgs: [mov.compromisoId, mov.numeroCuota],
        limit: 1,
      );
      
      if (cuotas.isNotEmpty) {
        observacionCancelacion = cuotas.first['observacion_cancelacion'] as String?;
        final updatedTs = cuotas.first['updated_ts'];
        if (updatedTs is int) {
          fechaCancelacion = DateTime.fromMillisecondsSinceEpoch(updatedTs);
        }
      }
    } catch (e) {
      // Si hay error, continuar sin observación
    }
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cancel, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Movimiento Cancelado'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tipo y Monto
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: mov.tipo == 'INGRESO' 
                      ? Colors.green.shade50 
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: mov.tipo == 'INGRESO' 
                        ? Colors.green.shade200 
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          mov.tipo == 'INGRESO' 
                              ? Icons.arrow_downward 
                              : Icons.arrow_upward,
                          color: mov.tipo == 'INGRESO' 
                              ? Colors.green 
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mov.tipo,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: mov.tipo == 'INGRESO' 
                                ? Colors.green.shade700 
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      Format.money(mov.monto),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: mov.tipo == 'INGRESO' 
                            ? Colors.green.shade700 
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Categoría
              _buildDetalleRow('Categoría', mov.categoria),
              const Divider(height: 16),
              
              // Compromiso
              _buildDetalleRow('Compromiso', mov.descripcion),
              const Divider(height: 16),
              
              // Cuota
              if (mov.numeroCuota != null && mov.totalCuotas != null) ...[
                _buildDetalleRow(
                  'Cuota',
                  '${mov.numeroCuota} de ${mov.totalCuotas}',
                ),
                const Divider(height: 16),
              ],
              
              // Fecha vencimiento original
              _buildDetalleRow(
                'Vencimiento original',
                DateFormat('dd/MM/yyyy').format(mov.fechaVencimiento),
              ),
              const Divider(height: 16),
              
              // Fecha de cancelación
              if (fechaCancelacion != null) ...[
                _buildDetalleRow(
                  'Fecha de cancelación',
                  DateFormat('dd/MM/yyyy HH:mm').format(fechaCancelacion),
                ),
                const Divider(height: 16),
              ],
              
              // Observación de cancelación
              const Text(
                'Motivo de cancelación:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  observacionCancelacion?.isNotEmpty == true
                      ? observacionCancelacion!
                      : 'Sin observación registrada',
                  style: TextStyle(
                    fontSize: 13,
                    color: observacionCancelacion?.isNotEmpty == true
                        ? Colors.grey.shade800
                        : Colors.grey.shade500,
                    fontStyle: observacionCancelacion?.isNotEmpty == true
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Future<void> _reactivarMovimientoSeleccionado() async {
    if (_movimientoSeleccionado == null) return;
    
    final mov = _movimientoSeleccionado!;
    
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivar compromiso'),
        content: Text(
          '¿Desea reactivar este ${mov.tipo.toLowerCase()} de ${Format.money(mov.monto)}?\n\n'
          'Volverá a aparecer como pendiente en las proyecciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Sí, reactivar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final db = await AppDatabase.instance();
        final cuotas = await db.query(
          'compromiso_cuotas',
          where: 'compromiso_id = ? AND numero_cuota = ?',
          whereArgs: [mov.compromisoId, mov.numeroCuota],
          limit: 1,
        );
        
        if (cuotas.isEmpty) {
          throw StateError('No se encontró la cuota para reactivar');
        }
        
        final cuotaId = cuotas.first['id'] as int;
        
        // Cambiar estado de CANCELADO a ESPERADO
        await _compromisosService.actualizarEstadoCuota(
          cuotaId,
          'ESPERADO',
        );

        // Limpiar selección
        setState(() {
          _movimientoSeleccionado = null;
        });

        await _load();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Compromiso reactivado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al reactivar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
