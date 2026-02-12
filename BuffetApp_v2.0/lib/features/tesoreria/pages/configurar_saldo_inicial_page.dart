import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../data/dao/db.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../../domain/models.dart';
import '../services/saldo_inicial_service.dart';
import '../../shared/format.dart';
import '../../shared/state/app_settings.dart';

/// Pantalla para configurar Saldo Inicial de una unidad de gestión.
/// Permite crear/editar el saldo disponible al comienzo de un período (año o mes).
class ConfigurarSaldoInicialPage extends StatefulWidget {
  /// ID del saldo inicial a editar (null para crear nuevo)
  final int? saldoId;

  /// Unidad de gestión preseleccionada (null para permitir selección)
  final int? unidadGestionId;

  const ConfigurarSaldoInicialPage({
    super.key,
    this.saldoId,
    this.unidadGestionId,
  });

  @override
  State<ConfigurarSaldoInicialPage> createState() =>
      _ConfigurarSaldoInicialPageState();
}

class _ConfigurarSaldoInicialPageState
    extends State<ConfigurarSaldoInicialPage> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _observacionCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _modoEdicion = false;

  List<Map<String, dynamic>> _unidades = [];
  int? _unidadSeleccionada;
  String _periodoTipo = 'ANIO'; // 'ANIO' | 'MES'
  int _anio = DateTime.now().year;
  int _mes = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _modoEdicion = widget.saldoId != null;
    _unidadSeleccionada = widget.unidadGestionId;
    _cargar();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
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

      // Cargar solo la unidad activa
      final db = await AppDatabase.instance();
      final rows = await db.query(
        'unidades_gestion',
        where: 'id = ? AND activo = 1',
        whereArgs: [settings.unidadGestionActivaId],
      );

      setState(() {
        _unidades = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        // Establecer la unidad activa como seleccionada (no se puede cambiar)
        _unidadSeleccionada = settings.unidadGestionActivaId;
      });

      // Si es modo edición, cargar el saldo existente
      if (_modoEdicion && widget.saldoId != null) {
        await _cargarSaldoExistente();
      }

      setState(() => _loading = false);
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'config_saldo_inicial.cargar',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _loading = false);
        _mostrarError(
          'No se pudieron cargar los datos necesarios. '
          'Verifique su configuración e inténtelo nuevamente.'
        );
      }
    }
  }

  Future<void> _cargarSaldoExistente() async {
    try {
      final db = await AppDatabase.instance();
      final rows = await db.query(
        'saldos_iniciales',
        where: 'id = ?',
        whereArgs: [widget.saldoId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Saldo inicial no encontrado');
      }

      final saldo = SaldoInicial.fromMap(rows.first);

      // Prellenar el formulario
      _unidadSeleccionada = saldo.unidadGestionId;
      _periodoTipo = saldo.periodoTipo;
      _montoCtrl.text = Format.money(saldo.monto);
      _observacionCtrl.text = saldo.observacion ?? '';

      // Parsear el período
      if (saldo.periodoTipo == 'ANIO') {
        _anio = int.parse(saldo.periodoValor);
      } else if (saldo.periodoTipo == 'MES') {
        final partes = saldo.periodoValor.split('-');
        _anio = int.parse(partes[0]);
        _mes = int.parse(partes[1]);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_unidadSeleccionada == null) {
      _mostrarError('Debe seleccionar una unidad de gestión');
      return;
    }

    try {
      setState(() => _saving = true);

      // Usar parseCurrencyToDouble para manejar el formato de moneda correctamente
      final monto = parseCurrencyToDouble(_montoCtrl.text);

      final observacion =
          _observacionCtrl.text.trim().isEmpty ? null : _observacionCtrl.text.trim();

      if (_modoEdicion) {
        // Actualizar existente
        await SaldoInicialService.actualizar(
          id: widget.saldoId!,
          monto: monto,
          observacion: observacion,
        );

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saldo inicial actualizado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Crear nuevo
        final periodoValor = SaldoInicialService.generarPeriodoValor(
          periodoTipo: _periodoTipo,
          anio: _anio,
          mes: _mes,
        );

        await SaldoInicialService.crear(
          unidadGestionId: _unidadSeleccionada!,
          periodoTipo: _periodoTipo,
          periodoValor: periodoValor,
          monto: monto,
          observacion: observacion,
        );

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saldo inicial creado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'config_saldo_inicial.guardar',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _saving = false);
        
        // Mostrar mensaje de error personalizado según el tipo de error
        final errorMsg = e.toString();
        if (errorMsg.contains('Ya existe un saldo inicial')) {
          _mostrarError('Ya existe un saldo inicial para este período.');
        } else if (errorMsg.contains('no puede ser negativo')) {
          _mostrarError('El monto no puede ser negativo.');
        } else if (errorMsg.contains('Saldo inicial no encontrado')) {
          _mostrarError('El saldo inicial que intenta editar no existe.');
        } else {
          _mostrarError(
            'No se pudo guardar el saldo inicial. '
            'Verifique los datos ingresados e inténtelo nuevamente.'
          );
        }
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_modoEdicion ? 'Editar Saldo Inicial' : 'Configurar Saldo Inicial'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: 800,
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Información de ayuda
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  '¿Qué es el Saldo Inicial?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'El saldo inicial representa los fondos disponibles al '
                              'comienzo de un período (año o mes). No se registra como '
                              'movimiento, sino que sirve como base para los cálculos.',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '• Solo se carga una vez por período\n'
                              '• No puede duplicarse\n'
                              '• El saldo anual se usa para el primer mes del año',
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Unidad de Gestión (heredada, no editable)
                    TextFormField(
                      initialValue: _unidades.isNotEmpty 
                          ? (_unidades.first['nombre'] as String)
                          : 'Cargando...',
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Unidad de Gestión',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance),
                        helperText: 'Heredada de la configuración actual',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tipo de Período
                    DropdownButtonFormField<String>(
                      value: _periodoTipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Período *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ANIO', child: Text('Anual')),
                        DropdownMenuItem(value: 'MES', child: Text('Mensual')),
                      ],
                      onChanged: _modoEdicion
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _periodoTipo = val);
                              }
                            },
                    ),
                    const SizedBox(height: 16),

                    // Año
                    TextFormField(
                      initialValue: _anio.toString(),
                      enabled: !_modoEdicion,
                      decoration: const InputDecoration(
                        labelText: 'Año *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                        hintText: '2026',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Ingrese el año';
                        }
                        final anio = int.tryParse(val);
                        if (anio == null || anio < 2000 || anio > 2100) {
                          return 'Año inválido';
                        }
                        return null;
                      },
                      onChanged: (val) {
                        final anio = int.tryParse(val);
                        if (anio != null) {
                          setState(() => _anio = anio);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Mes (solo si período es mensual)
                    if (_periodoTipo == 'MES')
                      DropdownButtonFormField<int>(
                        value: _mes,
                        decoration: const InputDecoration(
                          labelText: 'Mes *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_month),
                        ),
                        items: List.generate(12, (i) {
                          final mesNum = i + 1;
                          final mesNombre = [
                            'Enero',
                            'Febrero',
                            'Marzo',
                            'Abril',
                            'Mayo',
                            'Junio',
                            'Julio',
                            'Agosto',
                            'Septiembre',
                            'Octubre',
                            'Noviembre',
                            'Diciembre'
                          ][i];
                          return DropdownMenuItem<int>(
                            value: mesNum,
                            child: Text(mesNombre),
                          );
                        }),
                        onChanged: _modoEdicion
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _mes = val);
                                }
                              },
                      ),
                    if (_periodoTipo == 'MES') const SizedBox(height: 16),

                    // Monto
                    TextFormField(
                      controller: _montoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Monto *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                        hintText: '8.062.355,74',
                        helperText: 'Saldo disponible al inicio del período',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [CurrencyInputFormatter()],
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Ingrese el monto';
                        }
                        try {
                          final monto = parseCurrencyToDouble(val);
                          if (monto < 0) {
                            return 'El monto no puede ser negativo';
                          }
                          return null;
                        } catch (e) {
                          return 'Formato de monto inválido';
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Observación
                    TextFormField(
                      controller: _observacionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Observación (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                        hintText: 'Ej: Saldo disponible cierre 2025',
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),
                    const SizedBox(height: 24),

                    // Advertencia si ya existe
                    if (!_modoEdicion)
                      FutureBuilder<bool>(
                        future: _verificarExistencia(),
                        builder: (ctx, snapshot) {
                          if (snapshot.hasData && snapshot.data == true) {
                            return Card(
                              color: Colors.orange.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber,
                                        color: Colors.orange.shade700),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Ya existe un saldo inicial para este '
                                        'período. Si continúa, se producirá un error.',
                                        style: TextStyle(
                                          color: Colors.orange.shade900,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    const SizedBox(height: 16),

                    // Botón Guardar
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _guardar,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_modoEdicion ? 'Actualizar' : 'Guardar'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Future<bool> _verificarExistencia() async {
    if (_unidadSeleccionada == null) return false;

    try {
      final periodoValor = SaldoInicialService.generarPeriodoValor(
        periodoTipo: _periodoTipo,
        anio: _anio,
        mes: _mes,
      );

      return await SaldoInicialService.existe(
        unidadGestionId: _unidadSeleccionada!,
        periodoTipo: _periodoTipo,
        periodoValor: periodoValor,
      );
    } catch (e) {
      return false;
    }
  }
}
