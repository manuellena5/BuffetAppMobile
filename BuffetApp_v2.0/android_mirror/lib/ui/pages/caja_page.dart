import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../format.dart';
import 'home_page.dart';
import '../../services/export_service.dart';
import '../../services/print_service.dart';

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

  final _usuario = TextEditingController(text: '');
  final _efectivo = TextEditingController(text: '');
  final _transfer = TextEditingController(text: '');
  final _obs = TextEditingController();
  final _entradas = TextEditingController(text: '');

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
    setState(() {
      _caja = caja;
      _resumen = resumen;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _usuario.dispose();
    _efectivo.dispose();
    _transfer.dispose();
    _obs.dispose();
    _entradas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_caja == null) {
      return const Scaffold(body: Center(child: Text('No hay caja abierta')));
    }
    final resumen = _resumen!;
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
      Text(
        '${_caja!['codigo_caja']} • Disciplina: ${_caja!['disciplina']} • Cajero: ${_caja!['cajero_apertura'] ?? ''}'),
            const SizedBox(height: 6),
            if (((_caja!['observaciones_apertura'] as String?) ?? '').isNotEmpty)
              Text('Obs. apertura: ${_caja!['observaciones_apertura']}'),
            const SizedBox(height: 8),
      Text(
        'Fondo inicial: ${formatCurrency(_caja!['fondo_inicial'] as num)}'),
            const Divider(height: 24),
      Text('Totales', style: Theme.of(context).textTheme.titleMedium),
      Text('Total ventas: ${formatCurrency(resumen['total'] as num)}',
        style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
            const SizedBox(height: 6),
            Text('Ventas por método de pago',
                style: Theme.of(context).textTheme.titleMedium),
            ...(resumen['por_mp'] as List).map<Widget>((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                      '• ${(e['mp_desc'] as String?) ?? 'MP ${e['mp']}'}: ${formatCurrency((e['total'] as num?) ?? 0)}'),
                )),
            const SizedBox(height: 10),
            Text('Tickets', style: Theme.of(context).textTheme.titleMedium),
            Text(
                'Emitidos: ${(resumen['tickets']['emitidos'] ?? 0)} • Anulados: ${(resumen['tickets']['anulados'] ?? 0)}'),
            const SizedBox(height: 10),
      Text('Ventas por producto',
        style: Theme.of(context).textTheme.titleMedium),
      ...(() {
        final list = List<Map<String, dynamic>>.from(
          (resumen['por_producto'] as List?) ?? const []);
        list.sort((a, b) {
        final an = (a['cantidad'] as num?) ?? 0;
        final bn = (b['cantidad'] as num?) ?? 0;
        return bn.compareTo(an);
        });
        return list
          .map<Widget>((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${(e['nombre'] ?? '')} x ${(e['cantidad'] ?? 0)} = ${formatCurrency(((e['total'] as num?) ?? 0))}'),
            ))
          .toList();
      }()),
            const Divider(height: 24),
            Text('Cierre de caja',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
      TextField(
        controller: _usuario,
        decoration: const InputDecoration(labelText: 'Cajero de cierre')),
            const SizedBox(height: 6),
            TextField(
                controller: _efectivo,
                decoration:
                    const InputDecoration(labelText: 'Efectivo en caja'),
                keyboardType: TextInputType.number,
        ),
            const SizedBox(height: 6),
            TextField(
                controller: _transfer,
                decoration: const InputDecoration(labelText: 'Transferencias'),
                keyboardType: TextInputType.number,
        ),
            const SizedBox(height: 6),
            TextField(
                controller: _obs,
                decoration: const InputDecoration(labelText: 'Observación')),
            const SizedBox(height: 6),
            TextField(
                controller: _entradas,
                decoration: const InputDecoration(labelText: 'Entradas vendidas (opcional)'),
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final nav = Navigator.of(context);
                final eff = parseLooseDouble(_efectivo.text);
                final tr = parseLooseDouble(_transfer.text);
                final entradas = int.tryParse(_entradas.text.trim());
                if ((_usuario.text.trim()).isEmpty) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Usuario cierre requerido')));
                  return;
                }
                // calcular diferencia antes de confirmar (ya excluye anulados desde resumen)
                final totalVentas =
                    (resumen['total'] as num?)?.toDouble() ?? 0.0;
                // Fórmula pedida: Total Ventas = (Efectivo - Fondo Inicial) + Transferencias
                final fondo =
                    (_caja!['fondo_inicial'] as num?)?.toDouble() ?? 0.0;
                final totalPorFormula = (eff - fondo) + tr;
                final diferencia = totalPorFormula - totalVentas;
                if (!context.mounted) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirmar cierre de caja'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Total ventas (sistema): ${formatCurrency(totalVentas)}'),
                        Text('Efectivo en caja: ${formatCurrency(eff)}'),
                        Text('Fondo inicial: ${formatCurrency(fondo)}'),
                        Text('Transferencias: ${formatCurrency(tr)}'),
                        Text(
                            'Total por fórmula: ${formatCurrency(totalPorFormula)}'),
                        Text('Diferencia: ${formatCurrency(diferencia)}'),
                        const SizedBox(height: 8),
                        const Text('¿Deseás cerrar la caja?'),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cerrar caja')),
                    ],
                  ),
                );
                if (ok != true) return;
                await _svc.cerrarCaja(
                  cajaId: _caja!['id'] as int,
                  efectivoEnCaja: eff,
                  transferencias: tr,
                  usuarioCierre: _usuario.text.trim(),
                  observacion:
                      _obs.text.trim().isEmpty ? null : _obs.text.trim(),
                  entradas: entradas,
                );
                // Intentar imprimir el cierre/resumen (USB por defecto, mostrar mensaje si no se pudo)
                try {
                  final ok = await PrintService().printCajaResumenUsbOrPdf(_caja!['id'] as int);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No se pudo imprimir por USB. Se abrió PDF como alternativa.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al imprimir: $e')),
                    );
                  }
                }
                // Export automático y opción de compartir
                try {
                  final file = await ExportService()
                      .exportCajaToJson(_caja!['id'] as int);
                  if (!context.mounted) return;
                  // ignore: use_build_context_synchronously
                  final share = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Caja exportada'),
                      content: Text(
                          'Se generó el archivo:\n${file.path}\n\n¿Compartir ahora?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cerrar')),
                        ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Compartir')),
                      ],
                    ),
                  );
                  if (share == true) {
                    await ExportService().shareCajaFile(_caja!['id'] as int);
                  }
                } catch (_) {
                  // Si falla export/compartir no bloqueamos el cierre
                }
                if (!context.mounted) return;
                nav.pushAndRemoveUntil(
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
