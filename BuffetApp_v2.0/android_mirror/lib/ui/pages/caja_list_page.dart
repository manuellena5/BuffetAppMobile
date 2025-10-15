import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../format.dart';

class CajaListPage extends StatefulWidget {
  const CajaListPage({super.key});
  @override
  State<CajaListPage> createState() => _CajaListPageState();
}

class _CajaListPageState extends State<CajaListPage> {
  final _svc = CajaService();
  List<Map<String, dynamic>> _cajas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.listarCajas();
    setState(() { _cajas = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de cajas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _cajas.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final c = _cajas[i];
                  final subt = c['observaciones_apertura'] as String?;
                  final abierta = c['estado'] == 'ABIERTA';
                  return Container(
                    color: abierta ? Colors.lightGreen.withOpacity(0.15) : null,
                    child: ListTile(
                      leading: Icon(abierta ? Icons.lock_open : Icons.lock_outline, color: abierta ? Colors.green : null),
                      title: Text('${c['codigo_caja']}  •  ${c['fecha']}'),
                      subtitle: subt != null && subt.isNotEmpty ? Text(subt, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                      // Mostrar resumen (reutilizamos CajaPage si está abierta, o vista de solo-lectura inline)
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => CajaResumenPage(cajaId: c['id'] as int)));
                        if (!mounted) return;
                        await _load();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class CajaResumenPage extends StatefulWidget {
  final int cajaId;
  const CajaResumenPage({super.key, required this.cajaId});
  @override
  State<CajaResumenPage> createState() => _CajaResumenPageState();
}

class _CajaResumenPageState extends State<CajaResumenPage> {
  final _svc = CajaService();
  Map<String, dynamic>? _caja;
  Map<String, dynamic>? _resumen;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _svc.getCajaById(widget.cajaId);
    Map<String, dynamic>? r;
    if (c != null) {
      r = await _svc.resumenCaja(c['id'] as int);
    }
    setState(() { _caja = c; _resumen = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_caja == null) return const Scaffold(body: Center(child: Text('Caja no encontrada')));
    final resumen = _resumen!;
    return Scaffold(
      appBar: AppBar(title: Text('Resumen ${_caja!['codigo_caja']}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Fecha: ${_caja!['fecha']} • Estado: ${_caja!['estado']}'),
            const SizedBox(height: 8),
            if ((_caja!['observaciones_apertura'] as String?)?.isNotEmpty == true) Text('Descripción: ${_caja!['observaciones_apertura']}'),
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
            Text('Ventas por producto', style: Theme.of(context).textTheme.titleMedium),
            ...(resumen['por_producto'] as List).map<Widget>((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${e['nombre']}: ${e['cantidad']} un. • ${formatCurrency((e['total'] as num?) ?? 0)}'),
            )),
          ],
        ),
      ),
    );
  }
}
