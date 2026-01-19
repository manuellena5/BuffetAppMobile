import 'package:flutter/material.dart';
import '../../../data/dao/db.dart';
import '../../../features/shared/services/plantel_service.dart';
import '../../shared/widgets/responsive_container.dart';

/// FASE 17.7: Formulario para crear una nueva entidad del plantel.
class CrearJugadorPage extends StatefulWidget {
  const CrearJugadorPage({Key? key}) : super(key: key);

  @override
  State<CrearJugadorPage> createState() => _CrearJugadorPageState();
}

class _CrearJugadorPageState extends State<CrearJugadorPage> {
  final _formKey = GlobalKey<FormState>();
  final _plantelSvc = PlantelService.instance;

  final _nombreController = TextEditingController();
  final _contactoController = TextEditingController();
  final _dniController = TextEditingController();
  final _observacionesController = TextEditingController();

  String _rolSeleccionado = 'JUGADOR';
  DateTime? _fechaNacimiento;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _contactoController.dispose();
    _dniController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime(hoy.year - 25),
      firstDate: DateTime(1950),
      lastDate: hoy,
      locale: const Locale('es'),
      helpText: 'Fecha de nacimiento',
    );

    if (fecha != null) {
      setState(() => _fechaNacimiento = fecha);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      String? fechaNacStr;
      if (_fechaNacimiento != null) {
        fechaNacStr =
            '${_fechaNacimiento!.year}-${_fechaNacimiento!.month.toString().padLeft(2, '0')}-${_fechaNacimiento!.day.toString().padLeft(2, '0')}';
      }

      await _plantelSvc.crearEntidad(
        nombre: _nombreController.text.trim(),
        rol: _rolSeleccionado,
        contacto: _contactoController.text.trim().isEmpty
            ? null
            : _contactoController.text.trim(),
        dni: _dniController.text.trim().isEmpty ? null : _dniController.text.trim(),
        fechaNacimiento: fechaNacStr,
        observaciones: _observacionesController.text.trim().isEmpty
            ? null
            : _observacionesController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entidad creada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Retorna true para recargar lista
      }
    } catch (e, stack) {
      await AppDatabase.logLocalError(
        scope: 'crear_jugador.guardar',
        error: e.toString(),
        stackTrace: stack,
        payload: {'nombre': _nombreController.text.trim(), 'rol': _rolSeleccionado},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('Ya existe')
                ? 'Ya existe una entidad con ese nombre'
                : 'Error al crear entidad. Por favor, intente nuevamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Entidad del Plantel'),
        actions: [
          if (_guardando)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Guardar',
              onPressed: _guardar,
            ),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: 800,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            // Nombre (requerido)
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre completo *',
                hintText: 'Ej: Juan Pérez',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es requerido';
                }
                return null;
              },
              enabled: !_guardando,
            ),

            const SizedBox(height: 16),

            // Rol (requerido)
            DropdownButtonFormField<String>(
              value: _rolSeleccionado,
              decoration: const InputDecoration(
                labelText: 'Rol *',
                prefixIcon: Icon(Icons.badge),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'JUGADOR', child: Text('Jugador')),
                DropdownMenuItem(value: 'DT', child: Text('Director Técnico')),
                DropdownMenuItem(value: 'AYUDANTE', child: Text('Ayudante de Campo')),
                DropdownMenuItem(value: 'PF', child: Text('Preparador Físico')),
                DropdownMenuItem(value: 'OTRO', child: Text('Otro')),
              ],
              onChanged: _guardando
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _rolSeleccionado = value);
                      }
                    },
            ),

            const SizedBox(height: 16),

            // Contacto (opcional)
            TextFormField(
              controller: _contactoController,
              decoration: const InputDecoration(
                labelText: 'Contacto (teléfono/email)',
                hintText: 'Ej: 3512345678',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              enabled: !_guardando,
            ),

            const SizedBox(height: 16),

            // DNI (opcional)
            TextFormField(
              controller: _dniController,
              decoration: const InputDecoration(
                labelText: 'DNI',
                hintText: 'Ej: 12345678',
                prefixIcon: Icon(Icons.credit_card),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              enabled: !_guardando,
            ),

            const SizedBox(height: 16),

            // Fecha de nacimiento (opcional)
            InkWell(
              onTap: _guardando ? null : _seleccionarFecha,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha de nacimiento',
                  prefixIcon: Icon(Icons.cake),
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fechaNacimiento == null
                          ? 'Sin fecha'
                          : '${_fechaNacimiento!.day.toString().padLeft(2, '0')}/${_fechaNacimiento!.month.toString().padLeft(2, '0')}/${_fechaNacimiento!.year}',
                      style: TextStyle(
                        color: _fechaNacimiento == null ? Colors.grey : Colors.black87,
                      ),
                    ),
                    if (_fechaNacimiento != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: _guardando
                            ? null
                            : () => setState(() => _fechaNacimiento = null),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Observaciones (opcional)
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                hintText: 'Información adicional...',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              enabled: !_guardando,
            ),

            const SizedBox(height: 24),

            // Botón guardar (alternativo al AppBar)
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando...' : 'Guardar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 8),

            // Nota informativa
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Los campos marcados con * son obligatorios. '
                        'Podrás asociar compromisos a esta entidad después de crearla.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
