import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import 'caja_open_page.dart';
import 'caja_list_page.dart';
import 'caja_page.dart';
import 'pos_main_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _caja;
  double? _cajaTotal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = CajaService();
    final c = await svc.getCajaAbierta();
    double? total;
    if (c != null) {
      try {
        final r = await svc.resumenCaja(c['id'] as int);
        total = (r['total'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {}
    }
    setState(() { _caja = c; _cajaTotal = total; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BuffetApp')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_caja != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.store, size: 18),
                          const SizedBox(width: 6),
                          Text('Caja ${_caja!['codigo_caja']} • Total: '),
                          Text(
                            _formatCurrency((_cajaTotal ?? 0)),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  if (_caja != null) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const PosMainPage()));
                        if (!mounted) return; await _load();
                      },
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Ventas'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaPage()));
                        if (!mounted) return; await _load();
                      },
                      icon: const Icon(Icons.lock),
                      label: const Text('Cerrar caja'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaListPage()));
                        if (!mounted) return; await _load();
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Historial de cajas'),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaOpenPage()));
                        if (!mounted) return; await _load();
                      },
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Abrir caja'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaListPage()));
                        if (!mounted) return; await _load();
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('Historial de cajas'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

String _formatCurrency(num v) {
  // Simple formato para evitar depender de intl aquí; el POS ya usa utilidades más completas
  return '4 ${v.toStringAsFixed(2)}';
}
