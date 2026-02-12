import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/dao/db.dart';
import '../../../features/shared/services/compromisos_service.dart';
import '../../../features/shared/format.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_scaffold.dart';
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
  List<Map<String, dynamic>> _entidades = []; // Para dropdown de entidades
  
  // FASE 22.5: Filtros visibles (no modal)
  int? _unidadGestionId;
  int? _entidadPlantelId; // Filtro por jugador/DT
  String? _rolFiltro; // 'DT', 'JUGADOR', 'OTRO', null = todos
  String? _tipoFiltro; // 'INGRESO', 'EGRESO', null = todos
  bool? _origenAcuerdoFiltro; // true = solo acuerdos, false = solo manuales, null = todos
  bool? _activoFiltro; // true = activos, false = pausados, null = todos
  
  // Vista
  bool _vistaTabla = true; // false = tarjetas, true = tabla (por defecto)

  @override
  void initState() {
    super.initState();
    _cargarEntidades();
    _cargarCompromisos();
  }

  Future<void> _cargarEntidades() async {
    try {
      final db = await AppDatabase.instance();
      final entidades = await db.query(
        'entidades_plantel',
        where: 'eliminado = 0',
        orderBy: 'nombre ASC',
      );
      
      if (mounted) {
        setState(() {
          _entidades = entidades.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      // Error silencioso, los filtros son opcionales
    }
  }

  Future<void> _cargarCompromisos() async {
    setState(() => _isLoading = true);
    
    try {
      // FASE 22.5: Usar vista completa con JOINs en lugar de enriquecer manualmente
      final db = await AppDatabase.instance();
      
      // Construir query dinámico con filtros
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];
      
      if (_unidadGestionId != null) {
        whereConditions.add('unidad_gestion_id = ?');
        whereArgs.add(_unidadGestionId);
      }
      
      if (_tipoFiltro != null) {
        whereConditions.add('tipo = ?');
        whereArgs.add(_tipoFiltro);
      }
      
      if (_activoFiltro != null) {
        whereConditions.add('activo = ?');
        whereArgs.add(_activoFiltro! ? 1 : 0);
      }
      
      if (_entidadPlantelId != null) {
        whereConditions.add('entidad_plantel_id = ?');
        whereArgs.add(_entidadPlantelId);
      }
      
      if (_rolFiltro != null) {
        whereConditions.add('entidad_rol = ?');
        whereArgs.add(_rolFiltro);
      }
      
      final whereClause = whereConditions.isEmpty ? null : whereConditions.join(' AND ');
      
      final compromisosRaw = await db.query(
        'v_compromisos_completo',
        where: whereClause,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'fecha_inicio DESC',
      );
      
      var compromisos = compromisosRaw.map((c) => Map<String, dynamic>.from(c)).toList();
      
      // Enriquecer con información de origen (si viene de acuerdo)
      for (final comp in compromisos) {
        final acuerdoId = comp['acuerdo_id'];
        if (acuerdoId != null) {
          final esDeAcuerdo = await _compromisosService.esCompromisoPorAcuerdo(comp['id'] as int);
          comp['es_de_acuerdo'] = esDeAcuerdo;
        } else {
          comp['es_de_acuerdo'] = false;
        }
      }
      
      // Filtrar por origen de acuerdo
      if (_origenAcuerdoFiltro != null) {
        compromisos = compromisos.where((c) => c['es_de_acuerdo'] == _origenAcuerdoFiltro).toList();
      }
      
      setState(() {
        _compromisos = compromisos;
        _isLoading = false;
      });
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'compromisos_page.cargar_compromisos',
        error: e.toString(),
        stackTrace: stack,
      );
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
      _entidadPlantelId = null;
      _rolFiltro = null;
      _tipoFiltro = null;
      _origenAcuerdoFiltro = null;
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
    return TesoreriaScaffold(
      title: 'Acuerdos y Compromisos',
      currentRouteName: '/compromisos',
      actions: [
        // Toggle vista tabla/tarjetas
        IconButton(
          icon: Icon(_vistaTabla ? Icons.view_list : Icons.table_chart),
          onPressed: () {
            setState(() => _vistaTabla = !_vistaTabla);
          },
          tooltip: _vistaTabla ? 'Vista de tarjetas' : 'Vista de tabla',
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearCompromiso,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Compromiso'),
      ),
      body: Column(
        children: [
          // FASE 22.5: Filtros visibles
          _buildFiltrosVisibles(),
          const Divider(height: 1),
          
          // Contenido principal
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _compromisos.isEmpty
                    ? _buildEmpty()
                    : ResponsiveContainer(
                        maxWidth: _vistaTabla ? 1400 : 1000,
                        child: RefreshIndicator(
                          onRefresh: _cargarCompromisos,
                          child: _vistaTabla
                              ? _buildTabla()
                              : _buildTarjetas(),
                        ),
                      ),
          ),
        ],
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

  /// FASE 22.5: Sección de filtros visibles (dropdowns en lugar de modal)
  Widget _buildFiltrosVisibles() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade100,
      child: ResponsiveContainer(
        maxWidth: 1400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila de dropdowns
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Entidad
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int?>(
                    value: _entidadPlantelId,
                    decoration: const InputDecoration(
                      labelText: 'Entidad',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
                      ..._entidades.map((e) => DropdownMenuItem<int?>(
                        value: e['id'] as int,
                        child: Text(e['nombre'] as String),
                      )),
                    ],
                    onChanged: (val) {
                      setState(() => _entidadPlantelId = val);
                    },
                  ),
                ),
                
                // Rol
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    value: _rolFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: 'DT', child: Text('DT')),
                      DropdownMenuItem(value: 'JUGADOR', child: Text('Jugador')),
                      DropdownMenuItem(value: 'OTRO', child: Text('Otro')),
                    ],
                    onChanged: (val) {
                      setState(() => _rolFiltro = val);
                    },
                  ),
                ),
                
                // Tipo
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    value: _tipoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: 'INGRESO', child: Text('Ingreso')),
                      DropdownMenuItem(value: 'EGRESO', child: Text('Egreso')),
                    ],
                    onChanged: (val) {
                      setState(() => _tipoFiltro = val);
                    },
                  ),
                ),
                
                // Estado (activo/pausado)
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<bool?>(
                    value: _activoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: true, child: Text('Activo')),
                      DropdownMenuItem(value: false, child: Text('Pausado')),
                    ],
                    onChanged: (val) {
                      setState(() => _activoFiltro = val);
                    },
                  ),
                ),
                
                // Origen acuerdo
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<bool?>(
                    value: _origenAcuerdoFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Origen',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: true, child: Text('Solo acuerdos')),
                      DropdownMenuItem(value: false, child: Text('Solo manuales')),
                    ],
                    onChanged: (val) {
                      setState(() => _origenAcuerdoFiltro = val);
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Botones de acción
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _aplicarFiltros,
                  icon: const Icon(Icons.filter_list),
                  label: const Text('Filtrar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpiar'),
                ),
                const Spacer(),
                Text(
                  '${_compromisos.length} resultado${_compromisos.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
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
            DataColumn(label: Text('Entidad')), // FASE 22.5
            DataColumn(label: Text('Rol')),      // FASE 22.5
            DataColumn(label: Text('Monto')),
            DataColumn(label: Text('Frecuencia')),
            DataColumn(label: Text('Próximo Vencimiento')),
            DataColumn(label: Text('Cuotas')),
            DataColumn(label: Text('Origen')),
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
    final esDeAcuerdo = c['es_de_acuerdo'] == true;
    
    // FASE 22.5: Obtener info de entidad desde la vista (ya viene con JOIN)
    final entidadNombre = c['entidad_nombre'] as String? ?? '—';
    final rolNombre = c['entidad_rol'] as String? ?? '—';
    
    return DataRow(
      onSelectChanged: (_) => _verDetalle(c['id'] as int),
      cells: [
        DataCell(Text(c['nombre'] ?? '')),
        DataCell(_buildTipoBadge(tipo)),
        DataCell(Text(entidadNombre)),  // FASE 22.5
        DataCell(Text(rolNombre)),      // FASE 22.5
        DataCell(Text(Format.money(c['monto'] ?? 0))),
        DataCell(Text(c['frecuencia'] ?? '')),
        DataCell(_buildProximoVencimiento(c['id'] as int)),
        DataCell(Text(cuotas != null ? '$cuotasConfirmadas/$cuotas' : '—')),
        DataCell(_buildOrigenBadge(esDeAcuerdo)),
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
    final esDeAcuerdo = c['es_de_acuerdo'] == true;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _verDetalle(c['id'] as int),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: nombre, tipo y estado
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
              
              // Indicador de origen
              if (esDeAcuerdo) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.handshake, size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Generado desde Acuerdo',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
              
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

  Widget _buildOrigenBadge(bool esDeAcuerdo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: esDeAcuerdo ? Colors.purple[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            esDeAcuerdo ? Icons.handshake : Icons.edit,
            size: 14,
            color: esDeAcuerdo ? Colors.purple[900] : Colors.grey[700],
          ),
          const SizedBox(width: 4),
          Text(
            esDeAcuerdo ? 'ACUERDO' : 'MANUAL',
            style: TextStyle(
              color: esDeAcuerdo ? Colors.purple[900] : Colors.grey[700],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
