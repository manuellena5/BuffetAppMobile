import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/format.dart';
import 'crear_compromiso_page.dart';
import 'detalle_compromiso_page.dart';

/// Página principal de gestión de compromisos financieros.
/// Muestra lista de compromisos con filtros y acciones.
class CompromisosPage extends StatefulWidget {
  const CompromisosPage({super.key});

  @override
  State<CompromisosPage> createState() => _CompromisosPageState();
}

class _CompromisosPageState extends State<CompromisosPage> {
  final _compromisosService = CompromisosService.instance;
  
  List<Map<String, dynamic>> _compromisos = [];
  bool _isLoading = true;
  
  // Filtros
  int? _unidadGestionId;
  String? _tipoFiltro; // 'INGRESO', 'EGRESO', null = todos
  bool? _activoFiltro; // true = activos, false = pausados, null = todos
  
  // Vista
  bool _vistaTabla = false; // false = tarjetas (por defecto), true = tabla

  @override
  void initState() {
    super.initState();
    _cargarCompromisos();
  }

  Future<void> _cargarCompromisos() async {
    setState(() => _isLoading = true);
    
    try {
      final compromisos = await _compromisosService.listarCompromisos(
        unidadGestionId: _unidadGestionId,
        tipo: _tipoFiltro,
        activo: _activoFiltro,
      );
      
      setState(() {
        _compromisos = compromisos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar compromisos: $e')),
        );
      }
    }
  }

  void _aplicarFiltros() {
    _cargarCompromisos();
  }

  void _limpiarFiltros() {
    setState(() {
      _unidadGestionId = null;
      _tipoFiltro = null;
      _activoFiltro = null;
    });
    _cargarCompromisos();
  }

  Future<void> _pausarReactivar(int id, bool activo) async {
    try {
      if (activo) {
        await _compromisosService.pausarCompromiso(id);
      } else {
        await _compromisosService.reactivarCompromiso(id);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(activo ? 'Compromiso pausado' : 'Compromiso reactivado'),
          ),
        );
      }
      
      _cargarCompromisos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compromisos'),
        actions: [
          // Toggle vista tabla/tarjetas
          IconButton(
            icon: Icon(_vistaTabla ? Icons.view_list : Icons.table_chart),
            onPressed: () {
              setState(() => _vistaTabla = !_vistaTabla);
            },
            tooltip: _vistaTabla ? 'Vista de tarjetas' : 'Vista de tabla',
          ),
          // Filtros
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _mostrarFiltros,
            tooltip: 'Filtros',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _compromisos.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _cargarCompromisos,
                  child: _vistaTabla
                      ? _buildTabla()
                      : _buildTarjetas(),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearCompromiso,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Compromiso'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay compromisos registrados',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Creá un compromiso para empezar',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildTabla() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Monto')),
            DataColumn(label: Text('Frecuencia')),
            DataColumn(label: Text('Próximo Vencimiento')),
            DataColumn(label: Text('Cuotas')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: _compromisos.map((c) => _buildFilaTabla(c)).toList(),
        ),
      ),
    );
  }

  DataRow _buildFilaTabla(Map<String, dynamic> c) {
    final activo = c['activo'] == 1;
    final tipo = c['tipo'] as String;
    final cuotas = c['cuotas'];
    final cuotasConfirmadas = c['cuotas_confirmadas'] ?? 0;
    
    return DataRow(
      onSelectChanged: (_) => _verDetalle(c['id'] as int),
      cells: [
        DataCell(Text(c['nombre'] ?? '')),
        DataCell(_buildTipoBadge(tipo)),
        DataCell(Text(Format.money(c['monto'] ?? 0))),
        DataCell(Text(c['frecuencia'] ?? '')),
        DataCell(_buildProximoVencimiento(c['id'] as int)),
        DataCell(Text(cuotas != null ? '$cuotasConfirmadas/$cuotas' : '-')),
        DataCell(_buildEstadoBadge(activo)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(activo ? Icons.pause : Icons.play_arrow),
                iconSize: 20,
                onPressed: () => _pausarReactivar(c['id'] as int, activo),
                tooltip: activo ? 'Pausar' : 'Reactivar',
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                iconSize: 20,
                onPressed: () => _verDetalle(c['id'] as int),
                tooltip: 'Ver detalle',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetas() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _compromisos.length,
      itemBuilder: (context, index) {
        final c = _compromisos[index];
        return _buildTarjeta(c);
      },
    );
  }

  Widget _buildTarjeta(Map<String, dynamic> c) {
    final activo = c['activo'] == 1;
    final tipo = c['tipo'] as String;
    final cuotas = c['cuotas'];
    final cuotasConfirmadas = c['cuotas_confirmadas'] ?? 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _verDetalle(c['id'] as int),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: nombre y tipo
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c['nombre'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildTipoBadge(tipo),
                  const SizedBox(width: 8),
                  _buildEstadoBadge(activo),
                ],
              ),
              const SizedBox(height: 12),
              
              // Monto y frecuencia
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monto',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          Format.money(c['monto'] ?? 0),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Frecuencia',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          c['frecuencia'] ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Próximo vencimiento
              _buildProximoVencimiento(c['id'] as int),
              
              if (cuotas != null) ...[
                const SizedBox(height: 12),
                // Barra de progreso de cuotas
                LinearProgressIndicator(
                  value: cuotasConfirmadas / cuotas,
                  backgroundColor: Colors.grey[300],
                  color: tipo == 'INGRESO' ? Colors.green : Colors.blue,
                ),
                const SizedBox(height: 4),
                Text(
                  '$cuotasConfirmadas de $cuotas cuotas confirmadas',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                // Estado financiero (pagado/remanente)
                _buildEstadoFinanciero(c['id'] as int),
              ],
              
              const SizedBox(height: 12),
              
              // Acciones
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _pausarReactivar(c['id'] as int, activo),
                    icon: Icon(activo ? Icons.pause : Icons.play_arrow),
                    label: Text(activo ? 'Pausar' : 'Reactivar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _verDetalle(c['id'] as int),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Ver Detalle'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoBadge(String tipo) {
    final esIngreso = tipo == 'INGRESO';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: esIngreso ? Colors.green[100] : Colors.red[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tipo,
        style: TextStyle(
          color: esIngreso ? Colors.green[900] : Colors.red[900],
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEstadoBadge(bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activo ? Colors.blue[100] : Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        activo ? 'ACTIVO' : 'PAUSADO',
        style: TextStyle(
          color: activo ? Colors.blue[900] : Colors.grey[700],
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildProximoVencimiento(int compromisoId) {
    return FutureBuilder<DateTime?>(
      future: _compromisosService.calcularProximoVencimiento(compromisoId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const Text(
            'Sin próximo vencimiento',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          );
        }
        
        final fecha = snapshot.data!;
        final formato = DateFormat('dd/MM/yyyy');
        final hoy = DateTime.now();
        final diferencia = fecha.difference(hoy).inDays;
        
        Color color = Colors.grey[700]!;
        String prefijo = '';
        
        if (diferencia < 0) {
          color = Colors.red;
          prefijo = 'Vencido: ';
        } else if (diferencia <= 7) {
          color = Colors.orange;
          prefijo = 'Próximo: ';
        } else {
          prefijo = 'Próximo: ';
        }
        
        return Text(
          '$prefijo${formato.format(fecha)}',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: diferencia <= 7 ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      },
    );
  }

  Widget _buildEstadoFinanciero(int compromisoId) {
    return FutureBuilder<Map<String, double>>(
      future: _calcularEstadoFinanciero(compromisoId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        final pagado = snapshot.data!['pagado'] ?? 0.0;
        final remanente = snapshot.data!['remanente'] ?? 0.0;
        final total = pagado + remanente;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pagado',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Format.money(pagado),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.grey[300],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remanente',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Format.money(remanente),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  void _mostrarFiltros() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtros'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tipo
              const Text('Tipo:', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String?>(
                      title: const Text('Todos'),
                      value: null,
                      groupValue: _tipoFiltro,
                      onChanged: (val) => setDialogState(() => _tipoFiltro = val),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String?>(
                      title: const Text('Ingresos'),
                      value: 'INGRESO',
                      groupValue: _tipoFiltro,
                      onChanged: (val) => setDialogState(() => _tipoFiltro = val),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String?>(
                      title: const Text('Egresos'),
                      value: 'EGRESO',
                      groupValue: _tipoFiltro,
                      onChanged: (val) => setDialogState(() => _tipoFiltro = val),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Estado
              const Text('Estado:', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool?>(
                      title: const Text('Todos'),
                      value: null,
                      groupValue: _activoFiltro,
                      onChanged: (val) => setDialogState(() => _activoFiltro = val),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool?>(
                      title: const Text('Activos'),
                      value: true,
                      groupValue: _activoFiltro,
                      onChanged: (val) => setDialogState(() => _activoFiltro = val),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool?>(
                      title: const Text('Pausados'),
                      value: false,
                      groupValue: _activoFiltro,
                      onChanged: (val) => setDialogState(() => _activoFiltro = val),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _limpiarFiltros();
            },
            child: const Text('Limpiar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _aplicarFiltros();
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  Future<void> _crearCompromiso() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CrearCompromisoPage()),
    );
    
    if (resultado == true) {
      _cargarCompromisos();
    }
  }

  Future<void> _verDetalle(int compromisoId) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleCompromisoPage(compromisoId: compromisoId),
      ),
    );
    
    if (resultado == true) {
      _cargarCompromisos();
    }
  }
}
