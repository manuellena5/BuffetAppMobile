import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../format.dart';
import 'home_page.dart';
// import '../../services/export_service.dart';
import '../../services/print_service.dart';
import '../../services/usb_printer_service.dart';
import 'movimientos_page.dart';
import '../../services/movimiento_service.dart';
import '../../data/dao/db.dart';
import 'package:printing/printing.dart';
import 'printer_test_page.dart';

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
  double _movIngresos = 0.0;
  double _movRetiros = 0.0;

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
      // Cargar totales de movimientos
      try {
        final mt = await MovimientoService().totalesPorCaja(caja['id'] as int);
        _movIngresos = (mt['ingresos'] as num?)?.toDouble() ?? 0.0;
        _movRetiros = (mt['retiros'] as num?)?.toDouble() ?? 0.0;
      } catch (e, st) {
        AppDatabase.logLocalError(scope: 'caja_page.totales_movimientos', error: e, stackTrace: st, payload: {'cajaId': caja['id']});
      }
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
      appBar: AppBar(
        title: const Text('Caja'),
        actions: [
          StatefulBuilder(
            builder: (ctx, setLocal) {
              int tick = 0;
              Future<(bool,String?)> loadPrinter() async {
                final svc = UsbPrinterService();
                final connected = await svc.isConnected();
                final saved = await svc.getDefaultDevice();
                final name = saved?['deviceName'] as String?;
                return (connected, name);
              }
              return FutureBuilder<(bool,String?)>(
                future: loadPrinter(),
                key: ValueKey('printer-status-$tick'),
                builder: (ctx, snap) {
                  final connected = snap.data?.$1 ?? false;
                  final devName = snap.data?.$2;
                  final icon = connected ? Icons.print : Icons.print_disabled;
                  final color = connected ? Colors.green : Colors.redAccent;
                  final tooltip = connected
                      ? 'Impresora: Conectada${devName != null && devName.isNotEmpty ? ' ($devName)' : ''}\nTocar para configurar'
                      : 'Impresora: No conectada\nTocar para configurar';
                  return IconButton(
                    tooltip: tooltip,
                    icon: Icon(icon, color: color),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PrinterTestPage()),
                      );
                      if (!context.mounted) return;
                      setLocal(() => tick++); // refrescar estado al volver
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
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
            //Text('Totales', style: Theme.of(context).textTheme.titleMedium),
            Text('Total ventas: ${formatCurrency(resumen['total'] as num)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700)),
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
            // Resumen rápido de movimientos (cierre)
            Text('Ingresos registrados: ${formatCurrency(_movIngresos)}'),
            Text('Retiros registrados: ${formatCurrency(_movRetiros)}'),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final cajaId = _caja!['id'] as int;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MovimientosPage(cajaId: cajaId),
                      ),
                    );
                    if (mounted) _load();
                  },
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Movimientos (Ingresos/Retiros)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              keyboardType: TextInputType.number,
              onChanged: (v) {
                if (v.isEmpty) return; // permitir vacío (opcional)
                final parsed = int.tryParse(v);
                if (parsed == null || parsed < 0) {
                  // revertir a positivo previo o limpiar
                  final limpio = v.replaceAll(RegExp(r'[^0-9]'), '');
                  final safe = limpio.isEmpty ? '' : int.parse(limpio).toString();
                  if (_entradas.text != safe) {
                    _entradas.text = safe;
                    _entradas.selection = TextSelection.fromPosition(TextPosition(offset: _entradas.text.length));
                  }
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sólo números enteros ≥ 0')));
                }
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final nav = Navigator.of(context);
                final eff = parseLooseDouble(_efectivo.text);
                final tr = parseLooseDouble(_transfer.text);
                final entradasRaw = _entradas.text.trim();
                final entradas = entradasRaw.isEmpty ? null : int.tryParse(entradasRaw);
                if (entradasRaw.isNotEmpty && entradas == null) {
                  messenger.showSnackBar(const SnackBar(content: Text('Entradas debe ser un entero ≥ 0')));
                  return;
                }
                if (entradas != null && entradas < 0) {
                  messenger.showSnackBar(const SnackBar(content: Text('Entradas no puede ser negativo')));
                  return;
                }
                if ((_usuario.text.trim()).isEmpty) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Usuario cierre requerido')));
                  return;
                }
                // calcular diferencia antes de confirmar (ya excluye anulados desde resumen)
                final totalVentas =
                    (resumen['total'] as num?)?.toDouble() ?? 0.0;
                // Fórmula (ajustada): Total Ventas ≈ (Efectivo - Fondo - Ingresos + Retiros) + Transferencias
                final fondo =
                    (_caja!['fondo_inicial'] as num?)?.toDouble() ?? 0.0;
                // Obtener totales de movimientos (ingresos / retiros) para mostrar en el modal
                final movTotals = await MovimientoService()
                    .totalesPorCaja(_caja!['id'] as int);
                final ingresos =
                    (movTotals['ingresos'] as num?)?.toDouble() ?? 0.0;
                final retiros =
                    (movTotals['retiros'] as num?)?.toDouble() ?? 0.0;
                // Ajuste por movimientos al teórico: efectivo teórico = fondo + ventas_efectivo + ingresos - retiros
                // Despejando ventas_efectivo ≈ eff - fondo - ingresos + retiros
                final totalPorFormula = (eff - fondo - ingresos + retiros) + tr;
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
                        Text('Efectivo declarado en caja: ${formatCurrency(eff)}'),
                        Text('Fondo inicial: ${formatCurrency(fondo)}'),
                        // Ventas en efectivo
                        () {
                          final porMp = List<Map<String, dynamic>>.from(
                              (resumen['por_mp'] as List?) ?? const []);
                          final ventasEfectivo = porMp.fold<double>(
                              0.0, (acc, e) => (e['mp_desc']?.toString() ?? '')
                                      .toLowerCase() ==
                                  'efectivo'
                                  ? acc + ((e['total'] as num?)?.toDouble() ?? 0.0)
                                  : acc);
                          return Text(
                              'Ventas en efectivo: ${formatCurrency(ventasEfectivo)}');
                        }(),
                        Text('Transferencias: ${formatCurrency(tr)}'),
                        const SizedBox(height: 8),
                        Text('Ingresos registrados: ${formatCurrency(ingresos)}'),
                        Text('Retiros registrados: ${formatCurrency(retiros)}'),
                        Text(
                          'Diferencia: ${formatCurrency(diferencia)}',
                          style: TextStyle(
                            color: diferencia == 0
                                ? Colors.green
                                : (diferencia > 0
                                    ? Colors.blue
                                    : Colors.red),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                // 1) Intentar imprimir por USB; si no hay impresora, mostrar mensaje
                try {
                  final connected = await UsbPrinterService().isConnected();
                  if (!connected) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No hay impresora USB conectada.')),
                      );
                    }
                  } else {
                    final usbOk = await PrintService().printCajaResumenUsbOnly(_caja!['id'] as int);
                    if (!usbOk && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No se pudo imprimir por USB.')),
                      );
                    }
                  }
                } catch (e, st) {
                  AppDatabase.logLocalError(scope: 'caja_page.usb_print', error: e, stackTrace: st, payload: {'cajaId': _caja!['id']});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al imprimir: $e')),
                    );
                  }
                }

                // 2) Guardar automáticamente el PDF y abrir previsualización
                try {
                  final file = await PrintService().saveCajaResumenPdfFile(_caja!['id'] as int);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF guardado: ${file.path}')),
                    );
                  }
                  await Printing.layoutPdf(
                    onLayout: (format) => PrintService().buildCajaResumenPdf(_caja!['id'] as int),
                    name: 'cierre_caja_${_caja!['id']}.pdf',
                  );
                } catch (e, st) {
                  AppDatabase.logLocalError(scope: 'caja_page.save_preview_pdf', error: e, stackTrace: st, payload: {'cajaId': _caja!['id']});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo generar/abrir el PDF: $e')),
                    );
                  }
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
