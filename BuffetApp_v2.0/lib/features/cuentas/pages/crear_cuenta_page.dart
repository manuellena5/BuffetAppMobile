import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/dao/db.dart';
import '../../shared/state/app_settings.dart';
import '../../shared/widgets/responsive_container.dart';
import '../../tesoreria/services/cuenta_service.dart';

/// Pantalla para crear una nueva cuenta de fondos
class CrearCuentaPage extends StatefulWidget {
  const CrearCuentaPage({super.key});

  @override
  State<CrearCuentaPage> createState() => _CrearCuentaPageState();
}

class _CrearCuentaPageState extends State<CrearCuentaPage> {
  final _formKey = GlobalKey<FormState>();
  final _cuentaService = CuentaService();
  
  final _nombreCtrl = TextEditingController();
  final _saldoInicialCtrl = TextEditingController(text: '0');
  final _comisionCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _bancoNombreCtrl = TextEditingController();
  final _cbuAliasCtrl = TextEditingController();
  
  String _tipo = 'CAJA';
  bool _tieneComision = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _saldoInicialCtrl.dispose();
    _comisionCtrl.dispose();
    _observacionesCtrl.dispose();
    _bancoNombreCtrl.dispose();
    _cbuAliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final settings = context.read<AppSettings>();
    final unidadId = settings.disciplinaActivaId;

    if (unidadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione una unidad de gestión')),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final saldoInicial = double.tryParse(
        _saldoInicialCtrl.text.trim().replaceAll(',', '.'),
      ) ?? 0.0;

      final comisionPorcentaje = _tieneComision
          ? double.tryParse(_comisionCtrl.text.trim().replaceAll(',', '.'))
          : null;

      final cuentaId = await _cuentaService.crear(
        nombre: _nombreCtrl.text.trim(),
        tipo: _tipo,
        unidadGestionId: unidadId,
        saldoInicial: saldoInicial,
        tieneComision: _tieneComision,
        comisionPorcentaje: comisionPorcentaje,
        observaciones: _observacionesCtrl.text.trim().isEmpty
            ? null
            : _observacionesCtrl.text.trim(),
        bancoNombre: _bancoNombreCtrl.text.trim().isEmpty
            ? null
            : _bancoNombreCtrl.text.trim(),
        cbuAlias: _cbuAliasCtrl.text.trim().isEmpty
            ? null
            : _cbuAliasCtrl.text.trim(),
      );

      if (!mounted) return;
      
      // Modal de confirmación exitosa
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 32),
              SizedBox(width: 12),
              Text('Cuenta Creada'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La cuenta se creó correctamente:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              _buildInfoRow('ID', cuentaId.toString()),
              _buildInfoRow('Nombre', _nombreCtrl.text.trim()),
              _buildInfoRow('Tipo', _tipo),
              _buildInfoRow('Saldo Inicial', '\$${saldoInicial.toStringAsFixed(2)}'),
              if (_tieneComision && comisionPorcentaje != null)
                _buildInfoRow('Comisión', '${comisionPorcentaje.toStringAsFixed(2)}%'),
              if (_bancoNombreCtrl.text.trim().isNotEmpty)
                _buildInfoRow('Banco', _bancoNombreCtrl.text.trim()),
              if (_cbuAliasCtrl.text.trim().isNotEmpty)
                _buildInfoRow('CBU/Alias', _cbuAliasCtrl.text.trim()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Cierra el dialog
                Navigator.pop(context, true); // Retorna a la pantalla anterior
              },
              child: Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      await AppDatabase.logLocalError(
        scope: 'crear_cuenta_page.guardar',
        error: e,
        stackTrace: st,
      );

      if (!mounted) return;
      
      // Modal de error
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red, size: 32),
              SizedBox(width: 12),
              Text('Error al Crear Cuenta'),
            ],
          ),
          content: Text(
            'No se pudo crear la cuenta. Por favor, intente nuevamente.\n\nDetalle: ${e.toString()}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Cuenta'),
      ),
      body: ResponsiveContainer(
        maxWidth: 800,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
            // Nombre
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta *',
                hintText: 'Ej: Banco Santander, Mercado Pago, Caja Buffet',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es obligatorio';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Tipo de cuenta
            DropdownButtonFormField<String>(
              value: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de cuenta *',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'BANCO', child: Text('🏦 Banco')),
                DropdownMenuItem(value: 'BILLETERA', child: Text('📱 Billetera Digital')),
                DropdownMenuItem(value: 'CAJA', child: Text('💵 Caja de Efectivo')),
                DropdownMenuItem(value: 'INVERSION', child: Text('📈 Inversión / Plazo Fijo')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _tipo = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Campos específicos para BANCO
            if (_tipo == 'BANCO') ...[
              TextFormField(
                controller: _bancoNombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del banco',
                  hintText: 'Ej: Banco Santander',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cbuAliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'CBU / Alias',
                  hintText: 'Ej: club.futbol.mayor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Saldo inicial
            TextFormField(
              controller: _saldoInicialCtrl,
              decoration: const InputDecoration(
                labelText: 'Saldo inicial',
                hintText: '0',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingrese el saldo inicial (puede ser 0)';
                }
                final monto = double.tryParse(value.trim().replaceAll(',', '.'));
                if (monto == null) {
                  return 'Monto inválido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ¿Tiene comisión?
            SwitchListTile(
              title: const Text('¿Cobra comisión?'),
              subtitle: const Text('Ej: comisión bancaria por movimiento'),
              value: _tieneComision,
              onChanged: (value) {
                setState(() => _tieneComision = value);
              },
            ),

            // Porcentaje de comisión
            if (_tieneComision) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _comisionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Porcentaje de comisión *',
                  hintText: 'Ej: 0.6',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (_tieneComision) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingrese el porcentaje de comisión';
                    }
                    final porcentaje = double.tryParse(value.trim().replaceAll(',', '.'));
                    if (porcentaje == null || porcentaje <= 0) {
                      return 'Porcentaje inválido';
                    }
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),

            // Observaciones
            TextFormField(
              controller: _observacionesCtrl,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                hintText: 'Notas adicionales (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Información
            const Card(
              color: Colors.blue,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Información',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• El saldo se calculará automáticamente sumando los ingresos y restando los egresos.\n'
                      '• El saldo inicial es el punto de partida.\n'
                      '• Si la cuenta cobra comisión, se sugerirá registrarla automáticamente.',
                      style: TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Crear Cuenta'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  }

