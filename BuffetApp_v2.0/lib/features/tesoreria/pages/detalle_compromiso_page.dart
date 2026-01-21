import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/widgets/responsive_container.dart';


import '../../../features/shared/format.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/services/acuerdos_service.dart';
import '../../../data/dao/db.dart';
import '../services/categoria_movimiento_service.dart';
import 'editar_compromiso_page.dart';
import 'detalle_movimiento_page.dart';
import 'confirmar_movimiento_page.dart';
import 'detalle_acuerdo_page.dart';

/// Página de detalle de un compromiso financiero.
/// Muestra información completa, próximo vencimiento e historial de movimientos.
class DetalleCompromisoPage extends StatefulWidget {
  final int compromisoId;
  
  const DetalleCompromisoPage({
    super.key,
    required this.compromisoId,
  });

  @override
  State<DetalleCompromisoPage> createState() => _DetalleCompromisoPageState();
}

class _DetalleCompromisoPageState extends State<DetalleCompromisoPage> {
  final _compromisosService = CompromisosService.instance;
  
  Map<String, dynamic>? _compromiso;
  Map<String, dynamic>? _acuerdoOrigen;
  List<Map<String, dynamic>> _movimientos = [];
  DateTime? _proximoVencimiento;
  int? _cuotasRestantes;
  bool _isLoading = true;
  String? _error;
  String? _categoriaNombre;
  Map<int, String> _movimientosCategoriasNombres = {};
  List<Map<String, dynamic>> _cuotas = [];
  bool _cuotasExpanded = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final compromiso = await _compromisosService.obtenerCompromiso(widget.compromisoId);
      
      if (compromiso == null) {
        setState(() {
          _error = 'Compromiso no encontrado';
          _isLoading = false;
        });
        return;
      }
      
      // Cargar movimientos asociados
      final db = await AppDatabase.instance();
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'compromiso_id = ? AND eliminado = 0',
        whereArgs: [widget.compromisoId],
        orderBy: 'created_ts DESC',
      );
      
      // Cargar cuotas si existen
      final cuotas = await db.query(
        'compromiso_cuotas',
        where: 'compromiso_id = ?',
        whereArgs: [widget.compromisoId],
        orderBy: 'numero_cuota ASC',
      );
      
      // Calcular próximo vencimiento y cuotas restantes
      final proximoVenc = await _compromisosService.calcularProximoVencimiento(widget.compromisoId);
      final cuotasRest = await _compromisosService.calcularCuotasRestantes(widget.compromisoId);
      
      // Cargar acuerdo origen si existe
      Map<String, dynamic>? acuerdoOrigen;
      if (compromiso['acuerdo_id'] != null) {
        acuerdoOrigen = await _compromisosService.obtenerAcuerdoOrigen(widget.compromisoId);
      }
      
      // Cargar nombre de categoría del compromiso
      String? catNombre;
      final codigoCat = compromiso['categoria'] as String?;
      if (codigoCat != null && codigoCat.isNotEmpty) {
        catNombre = await CategoriaMovimientoService.obtenerNombrePorCodigo(codigoCat);
      }
      
      // Cargar nombres de categorías de movimientos
      final Map<int, String> movCategoriasNombres = {};
      for (final mov in movimientos) {
        final movId = mov['id'] as int;
        final movCodigoCat = mov['categoria'] as String?;
        if (movCodigoCat != null && movCodigoCat.isNotEmpty) {
          final nombre = await CategoriaMovimientoService.obtenerNombrePorCodigo(movCodigoCat);
          if (nombre != null) {
            movCategoriasNombres[movId] = nombre;
          }
        }
      }
      
      setState(() {
        _compromiso = compromiso;
        _acuerdoOrigen = acuerdoOrigen;
        _movimientos = movimientos;
        _proximoVencimiento = proximoVenc;
        _cuotasRestantes = cuotasRest;
        _categoriaNombre = catNombre;
        _movimientosCategoriasNombres = movCategoriasNombres;
        _cuotas = cuotas;
        _isLoading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_compromiso.cargar',
        error: e,
        stackTrace: st,
        payload: {'compromisoId': widget.compromisoId},
      );
      
      setState(() {
        _error = 'Error al cargar datos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pausarReactivar() async {
    if (_compromiso == null) return;
    
    final activo = _compromiso!['activo'] == 1;
    
    try {
      if (activo) {
        await _compromisosService.pausarCompromiso(widget.compromisoId);
      } else {
        await _compromisosService.reactivarCompromiso(widget.compromisoId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(activo ? 'Compromiso pausado' : 'Compromiso reactivado'),
          ),
        );
      }
      
      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _desactivar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar desactivación'),
        content: const Text(
          '¿Desactivar este compromiso?\n\n'
          'No se puede desactivar si tiene movimientos esperados pendientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DESACTIVAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmar != true) return;
    
    try {
      await _compromisosService.desactivarCompromiso(widget.compromisoId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compromiso desactivado')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _editar() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditarCompromisoPage(compromisoId: widget.compromisoId),
      ),
    );
    
    if (result == true) {
      await _cargarDatos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Compromiso'),
        actions: [
          if (_compromiso != null && _compromiso!['eliminado'] == 0) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editar,
              tooltip: 'Editar',
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'pausar_reactivar') {
                  _pausarReactivar();
                } else if (value == 'desactivar') {
                  _desactivar();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pausar_reactivar',
                  child: Text(
                    _compromiso!['activo'] == 1 ? 'Pausar' : 'Reactivar',
                  ),
                ),
                const PopupMenuItem(
                  value: 'desactivar',
                  child: Text('Desactivar', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _cargarDatos,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    
    if (_compromiso == null) {
      return const Center(child: Text('Compromiso no encontrado'));
    }
    
    return ResponsiveContainer(
      maxWidth: 800,
      child: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            if (_acuerdoOrigen != null) ...[
              _buildOrigenAcuerdoCard(),
              const SizedBox(height: 16),
            ],
            _buildEstadoFinanciero(),
            const SizedBox(height: 16),
            _buildEstadoCard(),
            const SizedBox(height: 16),
            if (_cuotas.isNotEmpty) ...[
              _buildCuotasCard(),
              const SizedBox(height: 16),
            ],
            _buildMovimientosCard(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final comp = _compromiso!;
    final activo = comp['activo'] == 1;
    final eliminado = comp['eliminado'] == 1;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    comp['nombre'] as String,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (eliminado)
                  const Chip(
                    label: Text('DESACTIVADO', style: TextStyle(fontSize: 10)),
                    backgroundColor: Colors.red,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                else if (!activo)
                  const Chip(
                    label: Text('PAUSADO', style: TextStyle(fontSize: 10)),
                    backgroundColor: Colors.orange,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                else
                  const Chip(
                    label: Text('ACTIVO', style: TextStyle(fontSize: 10)),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Tipo', comp['tipo'] as String),
            _buildInfoRow('Monto', Format.money(comp['monto'] as double)),
            _buildInfoRow('Frecuencia', comp['frecuencia'] as String),
            if (comp['frecuencia_dias'] != null)
              _buildInfoRow('Días', '${comp['frecuencia_dias']} días'),
            _buildInfoRow('Categoría', _categoriaNombre ?? (comp['categoria'] as String? ?? '—')),
            _buildInfoRow(
              'Fecha inicio',
              _formatFecha(comp['fecha_inicio'] as String?),
            ),
            if (comp['fecha_fin'] != null)
              _buildInfoRow(
                'Fecha fin',
                _formatFecha(comp['fecha_fin'] as String?),
              ),
            if (comp['observaciones'] != null && (comp['observaciones'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Observaciones:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(comp['observaciones'] as String),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoCard() {
    final comp = _compromiso!;
    final cuotasTotales = comp['cuotas'] as int?;
    final cuotasConfirmadas = comp['cuotas_confirmadas'] as int? ?? 0;
    final activo = comp['activo'] == 1;
    final eliminado = comp['eliminado'] == 1;
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estado del Compromiso',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (cuotasTotales != null) ...[
              _buildInfoRow(
                'Cuotas',
                '$cuotasConfirmadas de $cuotasTotales confirmadas',
              ),
              if (_cuotasRestantes != null)
                _buildInfoRow('Restantes', '$_cuotasRestantes cuotas'),
            ] else
              _buildInfoRow('Cuotas', 'Sin límite (recurrente)'),
            if (_proximoVencimiento != null) ...[
              _buildInfoRow(
                'Próximo vencimiento',
                DateFormat('dd/MM/yyyy').format(_proximoVencimiento!),
              ),
              // Botón para registrar pago/cobro
              if (activo && !eliminado) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConfirmarMovimientoPage(
                          compromisoId: widget.compromisoId,
                          fechaVencimiento: _proximoVencimiento!,
                          montoSugerido: comp['monto'] as double,
                          tipo: comp['tipo'] as String,
                          categoria: comp['categoria'] as String? ?? '',
                        ),
                      ),
                    );
                    if (result == true) {
                      await _cargarDatos();
                    }
                  },
                  icon: Icon(
                    comp['tipo'] == 'INGRESO' ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18,
                  ),
                  label: Text(
                    comp['tipo'] == 'INGRESO' ? 'Registrar cobro' : 'Registrar pago',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ] else if (activo && !eliminado)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No hay próximos vencimientos calculados',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCuotasCard() {
    final comp = _compromiso!;
    final activo = comp['activo'] == 1;
    final eliminado = comp['eliminado'] == 1;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _cuotasExpanded = !_cuotasExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cuotas Generadas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      Text(
                        '${_cuotas.length} total',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _cuotasExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_cuotasExpanded) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Nro', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Monto', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _cuotas.map((cuota) {
                  final estado = cuota['estado'] as String;
                  final numeroCuota = cuota['numero_cuota'] as int;
                  final fechaProgramada = cuota['fecha_programada'] as String;
                  final montoEsperado = (cuota['monto_esperado'] as num).toDouble();
                  
                  return DataRow(
                    cells: [
                      DataCell(Text('$numeroCuota')),
                      DataCell(Text(
                        DateFormat('dd/MM/yyyy').format(DateTime.parse(fechaProgramada)),
                      )),
                      DataCell(Text(
                        '\$${NumberFormat('#,##0.00', 'es_AR').format(montoEsperado)}',
                      )),
                      DataCell(_buildEstadoBadge(estado)),
                      DataCell(
                        estado == 'ESPERADO' && activo && !eliminado
                            ? IconButton(
                                icon: const Icon(Icons.payment, size: 20),
                                tooltip: 'Registrar pago',
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ConfirmarMovimientoPage(
                                        compromisoId: widget.compromisoId,
                                        fechaVencimiento: DateTime.parse(fechaProgramada),
                                        montoSugerido: montoEsperado,
                                        tipo: comp['tipo'] as String,
                                        categoria: comp['categoria'] as String? ?? '',
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    await _cargarDatos();
                                  }
                                },
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoBadge(String estado) {
    Color color;
    IconData icon;
    
    switch (estado) {
      case 'CONFIRMADO':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'CANCELADO':
        color = Colors.red;
        icon = Icons.cancel;
        break;
      case 'ESPERADO':
      default:
        color = Colors.orange;
        icon = Icons.schedule;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            estado,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientosCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Historial de Movimientos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_movimientos.length} total',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const Divider(),
            if (_movimientos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No hay movimientos registrados',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _movimientos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final mov = _movimientos[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: mov['tipo'] == 'INGRESO'
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      child: Icon(
                        mov['tipo'] == 'INGRESO'
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        color: mov['tipo'] == 'INGRESO'
                            ? Colors.green
                            : Colors.red,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      Format.money(mov['monto'] as double),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_movimientosCategoriasNombres[mov['id'] as int] ?? (mov['categoria'] as String? ?? 'Sin categoría')),
                        Text(
                          _formatFechaTs(mov['created_ts'] as int?),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(
                        mov['estado'] as String? ?? 'CONFIRMADO',
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: mov['estado'] == 'CONFIRMADO'
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetalleMovimientoPage(
                            movimientoId: mov['id'] as int,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFecha(String? fecha) {
    if (fecha == null) return '—';
    try {
      final dt = DateTime.parse(fecha);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return fecha;
    }
  }

  String _formatFechaTs(int? ts) {
    if (ts == null) return '—';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return '—';
    }
  }

  /// Widget para mostrar el estado financiero (Pagado/Remanente)
  Widget _buildEstadoFinanciero() {
    return FutureBuilder<Map<String, double>>(
      future: _calcularEstadoFinanciero(widget.compromisoId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }

        final pagado = snapshot.data!['pagado'] ?? 0.0;
        final remanente = snapshot.data!['remanente'] ?? 0.0;
        final total = pagado + remanente;

        return Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estado Financiero',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagado',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Format.money(pagado),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Remanente',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Format.money(remanente),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (total > 0) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Total: ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        Format.money(total),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, double>> _calcularEstadoFinanciero(int compromisoId) async {
    final pagado = await _compromisosService.calcularMontoPagado(compromisoId);
    final remanente = await _compromisosService.calcularMontoRemanente(compromisoId);
    return {'pagado': pagado, 'remanente': remanente};
  }

  /// Widget para mostrar información del acuerdo origen
  Widget _buildOrigenAcuerdoCard() {
    if (_acuerdoOrigen == null) return const SizedBox.shrink();
    
    final acuerdo = _acuerdoOrigen!;
    final activo = acuerdo['activo'] == 1;
    
    return Card(
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.handshake, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Origen: Acuerdo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (!activo)
                  Chip(
                    label: const Text('FINALIZADO', style: TextStyle(fontSize: 10)),
                    backgroundColor: Colors.grey.shade300,
                    labelStyle: const TextStyle(color: Colors.black87),
                  ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Nombre', acuerdo['nombre'] as String? ?? '—'),
            _buildInfoRow('Modalidad', acuerdo['modalidad'] as String? ?? '—'),
            _buildInfoRow('Frecuencia', acuerdo['frecuencia'] as String? ?? '—'),
            if (acuerdo['monto_total'] != null)
              _buildInfoRow(
                'Monto Total',
                Format.money((acuerdo['monto_total'] as num).toDouble()),
              ),
            if (acuerdo['monto_periodico'] != null)
              _buildInfoRow(
                'Monto Periódico',
                Format.money((acuerdo['monto_periodico'] as num).toDouble()),
              ),
            if (acuerdo['cuotas'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Cuota ${_compromiso!['numero_cuota'] ?? '?'} de ${acuerdo['cuotas']}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final resultado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetalleAcuerdoPage(
                      acuerdoId: acuerdo['id'] as int,
                    ),
                  ),
                );
                if (resultado == true) {
                  await _cargarDatos();
                }
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Ver Acuerdo Completo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
