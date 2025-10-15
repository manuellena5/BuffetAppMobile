import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import 'pos_main_page.dart';

class CajaOpenPage extends StatefulWidget {
  const CajaOpenPage({super.key});
  @override
  State<CajaOpenPage> createState() => _CajaOpenPageState();
}

class _CajaOpenPageState extends State<CajaOpenPage> {
  final _form = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _fondo = TextEditingController(text: '0');
  final _desc = TextEditingController();
  final _obs = TextEditingController();
  String _disciplina = 'Futbol Infantil';
  String _puntoVenta = 'Caja1 (Caj01)';
  final _svc = CajaService();

  @override
  void dispose() {
    _usuario.dispose(); _fondo.dispose(); _desc.dispose(); _obs.dispose();
    super.dispose();
  }

  Future<void> _abrir() async {
    if (!_form.currentState!.validate()) return;
    final fondo = double.tryParse(_fondo.text.trim()) ?? 0;
    final pvCode = _puntoVenta.contains('Caj01') ? 'Caj01' : (_puntoVenta.contains('Caj02') ? 'Caj02' : 'Caj03');

    try {
      // Verificar si ya hay una caja abierta
      final abierta = await _svc.getCajaAbierta();
      if (abierta != null) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Caja ya abierta'),
            content: Text('Ya existe una caja abierta: ${abierta['codigo_caja']}. Cerrala o usá otra.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
            ],
          ),
        );
        return;
      }

      await _svc.abrirCaja(
        usuario: _usuario.text.trim(),
        fondoInicial: fondo,
        disciplina: _disciplina,
        descripcionEvento: _desc.text.trim(),
        observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
        puntoVentaCodigo: pvCode,
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosMainPage()));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      String uiMsg = 'No se pudo abrir la caja.';
      if (msg.contains('UNIQUE') && msg.contains('codigo_caja')) {
        uiMsg = 'Ya existe una caja con el mismo código para hoy. Probá con otro Punto de venta o disciplina.';
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al abrir caja'),
          content: Text(uiMsg),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apertura de caja')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              TextFormField(
                controller: _usuario,
                decoration: const InputDecoration(labelText: 'Usuario apertura'),
                validator: (v) => (v==null||v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fondo,
                decoration: const InputDecoration(labelText: 'Fondo inicial'),
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse(v??'') == null || (double.tryParse(v!) ?? -1) < 0) ? '>= 0' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _disciplina,
                items: const [
                  DropdownMenuItem(value: 'Futbol Infantil', child: Text('Futbol Infantil')),
                  DropdownMenuItem(value: 'Futbol Mayor', child: Text('Futbol Mayor')),
                  DropdownMenuItem(value: 'Evento', child: Text('Evento')),
                  DropdownMenuItem(value: 'Otros', child: Text('Otros')),
                ],
                onChanged: (v) => setState(() => _disciplina = v ?? 'Otros'),
                decoration: const InputDecoration(labelText: 'Disciplina'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _puntoVenta,
                items: const [
                  DropdownMenuItem(value: 'Caja1 (Caj01)', child: Text('Caja1 (Caj01)')),
                  DropdownMenuItem(value: 'Caja2 (Caj02)', child: Text('Caja2 (Caj02)')),
                  DropdownMenuItem(value: 'Caja3 (Caj03)', child: Text('Caja3 (Caj03)')),
                ],
                onChanged: (v) => setState(() => _puntoVenta = v ?? 'Caja1 (Caj01)'),
                decoration: const InputDecoration(labelText: 'Punto de venta'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Descripción del evento'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _obs,
                decoration: const InputDecoration(labelText: 'Observación'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _abrir, child: const Text('Abrir caja')),
            ],
          ),
        ),
      ),
    );
  }
}
