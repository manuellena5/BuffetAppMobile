import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../domain/models.dart';
import '../../shared/widgets/responsive_container.dart';
import '../services/saldo_inicial_service.dart';
import '../../../data/dao/db.dart';
import '../../shared/format.dart';
import '../../shared/state/app_settings.dart';
import 'configurar_saldo_inicial_page.dart';

/// Pantalla para listar y gestionar los Saldos Iniciales configurados.
class SaldosInicialesListPage extends StatefulWidget {
  const SaldosInicialesListPage({super.key});

  @override
  State<SaldosInicialesListPage> createState() =>
      _SaldosInicialesListPageState();
}

class _SaldosInicialesListPageState extends State<SaldosInicialesListPage> {
  bool _loading = true;
  List<SaldoInicial> _saldos = [];
  Map<int, String> _unidadesNombres = {};
  int? _unidadActiva;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      setState(() => _loading = true);

      // Obtener unidad de gestión activa desde settings
      final settings = context.read<AppSettings>();
      await settings.ensureLoaded();
      
      if (!settings.isUnidadGestionConfigured) {
        throw Exception('No hay unidad de gestión configurada');
      }

      // Cargar nombres de unidades
      final db = await AppDatabase.instance();
      final unidades = await db.query(
        'unidades_gestion',
        columns: ['id', 'nombre'],
      );
      
      _unidadesNombres = {
        for (var u in unidades) u['id'] as int: u['nombre'] as String
      };

      // Establecer unidad activa
      _unidadActiva = settings.unidadGestionActivaId;

      // Cargar saldos SOLO de la unidad activa
      final saldos = await SaldoInicialService.listar(
        unidadGestionId: _unidadActiva,
      );

      setState(() {
        _saldos = saldos;
        _loading = false;
      });
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldos_iniciales_list.cargar',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
        _mostrarError(
          'No se pudieron cargar los saldos iniciales. '
          'Verifique su configuración e inténtelo nuevamente.'
        );
      }
    }
  }

  Future<void> _eliminar(SaldoInicial saldo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Saldo Inicial'),
        content: const Text(
          '¿Está seguro de eliminar este saldo inicial?\n\n'
          'Esta acción puede afectar los cálculos históricos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await SaldoInicialService.eliminar(saldo.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saldo inicial eliminado'),
            backgroundColor: Colors.green,
          ),
        );
        _cargar();
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'saldos_iniciales_list.eliminar',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        _mostrarError(
          'No se pudo eliminar el saldo inicial. '
          'Verifique que no esté siendo utilizado e inténtelo nuevamente.'
        );
      }
    }
  }

  Future<void> _navegarEditar(SaldoInicial saldo) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfigurarSaldoInicialPage(
          saldoId: saldo.id,
          unidadGestionId: saldo.unidadGestionId,
        ),
      ),
    );

    if (resultado == true) {
      _cargar();
    }
  }

  Future<void> _navegarNuevo() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ConfigurarSaldoInicialPage(),
      ),
    );

    if (resultado == true) {
      _cargar();
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _formatearPeriodo(SaldoInicial saldo) {
    if (saldo.periodoTipo == 'ANIO') {
      return 'Año ${saldo.periodoValor}';
    } else {
      final partes = saldo.periodoValor.split('-');
      if (partes.length == 2) {
        final meses = [
          'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
          'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
        ];
        final mes = int.tryParse(partes[1]);
        if (mes != null && mes >= 1 && mes <= 12) {
          return '${meses[mes - 1]} ${partes[0]}';
        }
      }
      return saldo.periodoValor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saldos Iniciales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 1000,
              child: Column(
              children: [
                // Mostrar unidad activa (no editable)
                if (_unidadActiva != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Unidad de Gestión',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _unidadesNombres[_unidadActiva] ?? 'Desconocida',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Lista
                Expanded(
                  child: _saldos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'No hay saldos iniciales configurados',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _navegarNuevo,
                                icon: const Icon(Icons.add),
                                label: const Text('Configurar Saldo Inicial'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _saldos.length,
                          itemBuilder: (ctx, i) {
                            final saldo = _saldos[i];
                            final unidadNombre =
                                _unidadesNombres[saldo.unidadGestionId] ??
                                    'Desconocida';

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      saldo.periodoTipo == 'ANIO'
                                          ? Colors.blue
                                          : Colors.green,
                                  child: Icon(
                                    saldo.periodoTipo == 'ANIO'
                                        ? Icons.calendar_today
                                        : Icons.calendar_month,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  unidadNombre,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_formatearPeriodo(saldo)),
                                    const SizedBox(height: 4),
                                    if (saldo.observacion != null &&
                                        saldo.observacion!.isNotEmpty)
                                      Text(
                                        saldo.observacion!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      Format.money(saldo.monto),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: saldo.monto >= 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      saldo.fechaCarga.split(' ')[0],
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _navegarEditar(saldo),
                                onLongPress: () => _mostrarOpciones(saldo),
                              ),
                            );
                          },
                        ),
                ),
              ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navegarNuevo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Saldo'),
      ),
    );
  }

  void _mostrarOpciones(SaldoInicial saldo) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(ctx);
                _navegarEditar(saldo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Eliminar',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _eliminar(saldo);
              },
            ),
          ],
        ),
      ),
    );
  }
}
