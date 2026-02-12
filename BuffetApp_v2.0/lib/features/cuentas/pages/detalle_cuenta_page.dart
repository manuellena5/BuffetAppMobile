import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/dao/db.dart';
import '../../../domain/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../tesoreria/services/cuenta_service.dart';
import '../../tesoreria/services/categoria_movimiento_service.dart';
import '../../tesoreria/pages/detalle_movimiento_page.dart';
import 'transferencia_page.dart';

/// Pantalla de detalle de una cuenta de fondos
/// Muestra el saldo actual y el listado de movimientos
class DetalleCuentaPage extends StatefulWidget {
  final CuentaFondos cuenta;
  
  const DetalleCuentaPage({super.key, required this.cuenta});

  @override
  State<DetalleCuentaPage> createState() => _DetalleCuentaPageState();
}

class _DetalleCuentaPageState extends State<DetalleCuentaPage> {
  final _cuentaService = CuentaService();
  
  double _saldoActual = 0.0;
  List<Map<String, dynamic>> _movimientos = [];
  bool _cargando = true;
  DateTime _mesSeleccionado = DateTime.now();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      setState(() => _cargando = true);
      
      // Cargar saldo actual
      final saldo = await _cuentaService.obtenerSaldo(widget.cuenta.id);
      
      // Cargar movimientos del mes seleccionado
      final db = await AppDatabase.instance();
      
      // Calcular rango del mes
      final primerDia = DateTime(_mesSeleccionado.year, _mesSeleccionado.month, 1);
      final ultimoDia = DateTime(_mesSeleccionado.year, _mesSeleccionado.month + 1, 0, 23, 59, 59);
      
      final movimientos = await db.query(
        'evento_movimiento',
        where: 'cuenta_id = ? AND eliminado = 0 AND created_ts >= ? AND created_ts <= ?',
        whereArgs: [
          widget.cuenta.id,
          primerDia.millisecondsSinceEpoch,
          ultimoDia.millisecondsSinceEpoch,
        ],
        orderBy: 'created_ts DESC', // De más nuevo a más viejo
      );
      
      if (mounted) {
        setState(() {
          _saldoActual = saldo;
          _movimientos = movimientos.map((m) => Map<String, dynamic>.from(m)).toList();
          _cargando = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_cuenta_page.cargar',
        error: e,
        stackTrace: st,
        payload: {'cuenta_id': widget.cuenta.id, 'mes': _mesSeleccionado.toString()},
      );
      
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navegarATransferencia() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransferenciaPage(cuentaOrigenId: widget.cuenta.id),
      ),
    );
    
    if (resultado == true) {
      _cargarDatos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cuenta.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 1200,
              child: Column(
                children: [
                  _buildHeader(),
                  _buildSelectorMes(),
                  _buildAcciones(),
                  const Divider(),
                  Expanded(child: _buildMovimientos()),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Saldo actual
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Saldo Actual',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Text(
                  formatCurrency(_saldoActual),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _saldoActual >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Información de la cuenta
            _buildInfoRow('Tipo', widget.cuenta.tipo),
            _buildInfoRow('Saldo inicial', formatCurrency(widget.cuenta.saldoInicial)),
            if (widget.cuenta.tieneComision && widget.cuenta.comisionPorcentaje != null)
              _buildInfoRow(
                'Comisión',
                '${widget.cuenta.comisionPorcentaje}%',
                color: Colors.orange,
              ),
            if (widget.cuenta.bancoNombre != null)
              _buildInfoRow('Banco', widget.cuenta.bancoNombre!),
            if (widget.cuenta.cbuAlias != null)
              _buildInfoRow('CBU/Alias', widget.cuenta.cbuAlias!),
            if (widget.cuenta.observaciones != null)
              _buildInfoRow('Observaciones', widget.cuenta.observaciones!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorMes() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _mesSeleccionado = DateTime(
                  _mesSeleccionado.year,
                  _mesSeleccionado.month - 1,
                );
              });
              _cargarDatos();
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
            onPressed: () {
              setState(() {
                _mesSeleccionado = DateTime(
                  _mesSeleccionado.year,
                  _mesSeleccionado.month + 1,
                );
              });
              _cargarDatos();
            },
            tooltip: 'Mes siguiente',
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _mesSeleccionado = DateTime.now();
              });
              _cargarDatos();
            },
            tooltip: 'Mes actual',
          ),
        ],
      ),
    );
  }

  Widget _buildAcciones() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _navegarATransferencia,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Transferir'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientos() {
    if (_movimientos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay movimientos en este mes',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<double>(
      future: _calcularSaldoInicialMes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final saldoInicial = snapshot.data!;
        
        // FASE 22.4: Crear lista de filas con saldos acumulados correctamente
        // Los movimientos están ordenados DESC (más nuevo primero),
        // pero el saldo debe calcularse desde el más antiguo al más nuevo
        final movimientosConSaldo = <Map<String, dynamic>>[];
        double saldoAcumulado = saldoInicial;
        
        // Invertir para calcular saldos de antiguo a nuevo
        final movimientosReversed = _movimientos.reversed.toList();
        
        for (final mov in movimientosReversed) {
          final tipo = mov['tipo'] as String;
          final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
          
          // Actualizar saldo acumulado
          if (tipo == 'INGRESO') {
            saldoAcumulado += monto;
          } else {
            saldoAcumulado -= monto;
          }
          
          movimientosConSaldo.add({
            ...mov,
            '_saldo_acumulado': saldoAcumulado,
          });
        }
        
        // Volver a invertir para mostrar de más nuevo a más viejo
        final filasConSaldo = movimientosConSaldo.reversed.toList();
        
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Saldo inicial del mes
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Saldo inicial del mes: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatCurrency(saldoInicial),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: saldoInicial >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Tabla de movimientos
                  DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
                    columns: const [
                      DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Categoría', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Monto', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Saldo', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: filasConSaldo.map((mov) {
                      final tipo = mov['tipo'] as String;
                      final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
                      final categoriaCode = mov['categoria'] as String? ?? tipo;
                      final movId = mov['id'] as int;
                      final createdTs = mov['created_ts'] as int;
                      final fecha = DateTime.fromMillisecondsSinceEpoch(createdTs);
                      final saldoEnEsteFila = mov['_saldo_acumulado'] as double;
                      
                      return DataRow(
                        cells: [
                          DataCell(Text(DateFormat('dd/MM/yyyy').format(fecha))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: tipo == 'INGRESO' ? Colors.green.shade100 : Colors.red.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tipo,
                                style: TextStyle(
                                  color: tipo == 'INGRESO' ? Colors.green.shade900 : Colors.red.shade900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            FutureBuilder<String?>(
                              future: CategoriaMovimientoService.obtenerNombrePorCodigo(categoriaCode),
                              builder: (context, snapshot) {
                                return Text(snapshot.data ?? categoriaCode);
                              },
                            ),
                          ),
                          DataCell(
                            Text(
                              '${tipo == 'INGRESO' ? '+' : '-'} ${formatCurrency(monto)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tipo == 'INGRESO' ? Colors.green : Colors.red,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatCurrency(saldoEnEsteFila),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: saldoEnEsteFila >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 20),
                              tooltip: 'Ver detalle',
                              onPressed: () async {
                                final result = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DetalleMovimientoPage(movimientoId: movId),
                                  ),
                                );
                                if (result == true && mounted) {
                                  _cargarDatos();
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Saldo final del mes
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Saldo final del mes: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatCurrency(filasConSaldo.isNotEmpty ? filasConSaldo.first['_saldo_acumulado'] as double : saldoInicial),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: (filasConSaldo.isNotEmpty ? filasConSaldo.first['_saldo_acumulado'] as double : saldoInicial) >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<double> _calcularSaldoInicialMes() async {
    try {
      final db = await AppDatabase.instance();
      
      // Saldo inicial de la cuenta
      double saldo = widget.cuenta.saldoInicial;
      
      // Sumar/restar todos los movimientos anteriores al mes seleccionado
      final primerDiaMes = DateTime(_mesSeleccionado.year, _mesSeleccionado.month, 1);
      
      final movimientosAnteriores = await db.query(
        'evento_movimiento',
        where: 'cuenta_id = ? AND eliminado = 0 AND created_ts < ?',
        whereArgs: [widget.cuenta.id, primerDiaMes.millisecondsSinceEpoch],
      );
      
      for (final mov in movimientosAnteriores) {
        final tipo = mov['tipo'] as String;
        final monto = (mov['monto'] as num?)?.toDouble() ?? 0.0;
        
        if (tipo == 'INGRESO') {
          saldo += monto;
        } else {
          saldo -= monto;
        }
      }
      
      return saldo;
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'detalle_cuenta_page.calcular_saldo_inicial',
        error: e,
        stackTrace: st,
      );
      return widget.cuenta.saldoInicial;
    }
  }
}
