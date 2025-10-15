import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../format.dart';
import 'home_page.dart';

class CajaPage extends StatefulWidget {
  const CajaPage({super.key});
  @override
  State<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends State<CajaPage> {
  final _svc = CajaService();
  Map<String, dynamic>? _caja;
  Map<String, dynamic>? _resumen;
  bool _loading = true;

  final _usuario = TextEditingController();
  final _efectivo = TextEditingController(text: '0');
  final _transfer = TextEditingController(text: '0');
  final _obs = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final caja = await _svc.getCajaAbierta();
    Map<String, dynamic>? resumen;
    if (caja != null) {
      resumen = await _svc.resumenCaja(caja['id'] as int);
    }
    setState(() { _caja = caja; _resumen = resumen; _loading = false; });
  }

  @override
  void dispose() {
    _usuario.dispose(); _efectivo.dispose(); _transfer.dispose(); _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_caja == null) return const Scaffold(body: Center(child: Text('No hay caja abierta')));
    final resumen = _resumen!;
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Código: ${_caja!['codigo_caja']} • Disciplina: ${_caja!['disciplina']} • Usuario: ${_caja!['usuario_apertura']}'),
            const SizedBox(height: 8),
            Text('Fondo inicial: ${formatCurrency(_caja!['fondo_inicial'] as num)}'),
            const Divider(height: 24),
            Text('Totales', style: Theme.of(context).textTheme.titleMedium),
            Text('Total ventas: ${formatCurrency(resumen['total'] as num)}'),
            const SizedBox(height: 6),
            Text('Por método de pago:'),
            ...(resumen['por_mp'] as List).map<Widget>((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${(e['mp_desc'] as String?) ?? 'MP ${e['mp']}'}: ${formatCurrency((e['total'] as num?) ?? 0)}'),
            )),
            const SizedBox(height: 10),
            Text('Tickets', style: Theme.of(context).textTheme.titleMedium),
            Text('Emitidos: ${(resumen['tickets']['emitidos'] ?? 0)} • Anulados: ${(resumen['tickets']['anulados'] ?? 0)}'),
            const SizedBox(height: 10),
            Text('Ventas por producto', style: Theme.of(context).textTheme.titleMedium),
            ...(resumen['por_producto'] as List).map<Widget>((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${e['nombre']}: ${e['cantidad']} un. • ${formatCurrency((e['total'] as num?) ?? 0)}'),
            )),
            const Divider(height: 24),
            Text('Cierre de caja', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            TextField(controller: _usuario, decoration: const InputDecoration(labelText: 'Usuario cierre')),
            const SizedBox(height: 6),
            TextField(controller: _efectivo, decoration: const InputDecoration(labelText: 'Efectivo en caja'), keyboardType: TextInputType.number),
            const SizedBox(height: 6),
            TextField(controller: _transfer, decoration: const InputDecoration(labelText: 'Transferencias'), keyboardType: TextInputType.number),
            const SizedBox(height: 6),
            TextField(controller: _obs, decoration: const InputDecoration(labelText: 'Observación')),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final eff = double.tryParse(_efectivo.text.trim()) ?? 0;
                final tr = double.tryParse(_transfer.text.trim()) ?? 0;
                if ((_usuario.text.trim()).isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuario cierre requerido'))); return; }
                // calcular diferencia antes de confirmar (ya excluye anulados desde resumen)
                final totalVentas = (resumen['total'] as num?)?.toDouble() ?? 0.0;
                final diferencia = (eff + tr) - totalVentas;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirmar cierre de caja'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total ventas sistema: ${formatCurrency(totalVentas)}'),
                        Text('Declarado por usuario: ${formatCurrency(eff + tr)}'),
                        Text('Diferencia: ${formatCurrency(diferencia)}'),
                        const SizedBox(height: 8),
                        const Text('¿Deseás cerrar la caja?'),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar')),
                    ],
                  ),
                );
                if (ok != true) return;
                await _svc.cerrarCaja(
                  cajaId: _caja!['id'] as int,
                  efectivoEnCaja: eff,
                  transferencias: tr,
                  usuarioCierre: _usuario.text.trim(),
                  observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
                );
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomePage()),
                  (route) => false,
                );
              },
              child: const Text('Cerrar caja'),
            ),
          ],
        ),
      ),
    );
  }
}
