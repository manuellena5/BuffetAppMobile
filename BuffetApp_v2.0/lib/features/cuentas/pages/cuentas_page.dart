import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/dao/db.dart';
import '../../../domain/models.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/state/drawer_state.dart';
import '../../shared/format.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../shared/widgets/tesoreria_drawer_helper.dart';
import '../../tesoreria/services/cuenta_service.dart';
import 'crear_cuenta_page.dart';
import 'detalle_cuenta_page.dart';

/// Pantalla de listado de cuentas de fondos
class CuentasPage extends StatefulWidget {
  const CuentasPage({super.key});

  @override
  State<CuentasPage> createState() => _CuentasPageState();
}

class _CuentasPageState extends State<CuentasPage> {
  final _cuentaService = CuentaService();
  
  List<CuentaFondos> _cuentas = [];
  Map<int, double> _saldos = {};
  bool _cargando = true;
  bool _mostrarInactivas = false;
  bool _showAdvanced = false;
  String? _filtroTipo;

  @override
  void initState() {
    super.initState();
    _loadShowAdvanced();
    _cargarCuentas();
  }
  
  /// Carga el estado de las opciones avanzadas desde SharedPreferences
  Future<void> _loadShowAdvanced() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showAdvanced = prefs.getBool('show_advanced_options') ?? false;
      });
    }
  }

  Future<void> _cargarCuentas() async {
    try {
      setState(() => _cargando = true);
      
      final settings = context.read<AppSettings>();
      final unidadId = settings.disciplinaActivaId;
      
      if (unidadId == null) {
        if (mounted) {
          setState(() {
            _cuentas = [];
            _saldos = {};
            _cargando = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seleccione una unidad de gestión')),
          );
        }
        return;
      }

      // Cargar cuentas
      var cuentas = await _cuentaService.listarPorUnidad(
        unidadId,
        soloActivas: !_mostrarInactivas,
      );

      // Filtrar por tipo si se seleccionó
      if (_filtroTipo != null) {
        cuentas = cuentas.where((c) => c.tipo == _filtroTipo).toList();
      }

      // Cargar saldos
      final saldos = await _cuentaService.obtenerSaldosPorUnidad(unidadId);

      if (mounted) {
        setState(() {
          _cuentas = cuentas;
          _saldos = saldos;
          _cargando = false;
        });
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuentas_page.cargar',
        error: e,
        stackTrace: st,
      );
      
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar cuentas: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navegarACrear() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CrearCuentaPage(),
      ),
    );
    
    if (resultado == true) {
      _cargarCuentas();
    }
  }

  void _navegarADetalle(CuentaFondos cuenta) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleCuentaPage(cuenta: cuenta),
      ),
    );
    
    if (resultado == true) {
      _cargarCuentas();
    }
  }

  void _toggleEstadoCuenta(CuentaFondos cuenta) async {
    try {
      if (cuenta.activa) {
        await _cuentaService.desactivar(cuenta.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cuenta desactivada')),
          );
        }
      } else {
        await _cuentaService.reactivar(cuenta.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cuenta reactivada')),
          );
        }
      }
      _cargarCuentas();
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'cuentas_page.toggle_estado',
        error: e,
        stackTrace: st,
        payload: {'cuenta_id': cuenta.id},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _iconoPorTipo(String tipo) {
    switch (tipo) {
      case 'BANCO':
        return Icons.account_balance;
      case 'BILLETERA':
        return Icons.account_balance_wallet;
      case 'CAJA':
        return Icons.money;
      case 'INVERSION':
        return Icons.trending_up;
      default:
        return Icons.attach_money;
    }
  }

  Color _colorPorTipo(String tipo) {
    switch (tipo) {
      case 'BANCO':
        return Colors.blue;
      case 'BILLETERA':
        return Colors.purple;
      case 'CAJA':
        return Colors.green;
      case 'INVERSION':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawerState>(
      builder: (context, drawerState, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cuentas / Fondos'),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            // No mostrar leading si el drawer está fijo
            automaticallyImplyLeading: !drawerState.isFixed,
            actions: [
              // Filtro por tipo
              PopupMenuButton<String?>(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filtrar por tipo',
                onSelected: (tipo) {
                  setState(() => _filtroTipo = tipo);
                  _cargarCuentas();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('Todas')),
                  const PopupMenuItem(value: 'BANCO', child: Text('🏦 Banco')),
                  const PopupMenuItem(value: 'BILLETERA', child: Text('📱 Billetera')),
                  const PopupMenuItem(value: 'CAJA', child: Text('💵 Caja')),
                  const PopupMenuItem(value: 'INVERSION', child: Text('📈 Inversión')),
                ],
              ),
              
              // Mostrar/ocultar inactivas
              IconButton(
                icon: Icon(_mostrarInactivas ? Icons.visibility : Icons.visibility_off),
                tooltip: _mostrarInactivas ? 'Ocultar inactivas' : 'Mostrar inactivas',
                onPressed: () {
                  setState(() => _mostrarInactivas = !_mostrarInactivas);
                  _cargarCuentas();
                },
              ),
              
              // Refrescar
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _cargarCuentas,
              ),
            ],
          ),
          drawer: drawerState.isFixed ? null : TesoreriaDrawerHelper.build(
            context: context,
            currentRouteName: '/cuentas',
            unidadGestionNombre: null,
            showAdvanced: _showAdvanced, // Leer desde SharedPreferences en initState
          ),
          body: Row(
            children: [
              // Drawer fijo (si está configurado)
              if (drawerState.isFixed) 
                TesoreriaDrawerHelper.build(
                  context: context,
                  currentRouteName: '/cuentas',
                  unidadGestionNombre: null,
                  showAdvanced: _showAdvanced, // Leer desde SharedPreferences en initState
                ),
              
              // Contenido principal
              Expanded(
                child: _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : ResponsiveContainer(
                        maxWidth: 1200,
                        child: _cuentas.isEmpty
                            ? _buildVacio()
                            : _buildListado(),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _navegarACrear,
            backgroundColor: Colors.teal,
            icon: const Icon(Icons.add),
            label: const Text('Nueva Cuenta'),
          ),
        );
      },
    );
  }

  Widget _buildVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _filtroTipo != null
                ? 'No hay cuentas de tipo $_filtroTipo'
                : 'No hay cuentas registradas',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _navegarACrear,
            icon: const Icon(Icons.add),
            label: const Text('Crear primera cuenta'),
          ),
        ],
      ),
    );
  }

  Widget _buildListado() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _cuentas.length,
      itemBuilder: (context, index) {
        final cuenta = _cuentas[index];
        final saldo = _saldos[cuenta.id] ?? 0.0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _colorPorTipo(cuenta.tipo),
              child: Icon(
                _iconoPorTipo(cuenta.tipo),
                color: Colors.white,
              ),
            ),
            title: Text(
              cuenta.nombre,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: cuenta.activa ? null : TextDecoration.lineThrough,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cuenta.tipo),
                if (cuenta.tieneComision && cuenta.comisionPorcentaje != null)
                  Text(
                    'Comisión: ${cuenta.comisionPorcentaje}%',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCurrency(saldo),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: saldo >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                Text(
                  cuenta.activa ? 'Activa' : 'Inactiva',
                  style: TextStyle(
                    fontSize: 12,
                    color: cuenta.activa ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            onTap: () => _navegarADetalle(cuenta),
            onLongPress: () => _mostrarOpciones(cuenta),
          ),
        );
      },
    );
  }

  void _mostrarOpciones(CuentaFondos cuenta) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('Ver detalle'),
            onTap: () {
              Navigator.pop(context);
              _navegarADetalle(cuenta);
            },
          ),
          ListTile(
            leading: Icon(cuenta.activa ? Icons.block : Icons.check_circle),
            title: Text(cuenta.activa ? 'Desactivar' : 'Reactivar'),
            onTap: () {
              Navigator.pop(context);
              _toggleEstadoCuenta(cuenta);
            },
          ),
        ],
      ),
    );
  }
}
