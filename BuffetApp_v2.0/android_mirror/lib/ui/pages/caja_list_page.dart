// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../../services/export_service.dart';
import '../../services/print_service.dart';
import '../format.dart';
import 'package:printing/printing.dart';
import '../../services/usb_printer_service.dart';
import 'printer_test_page.dart';
import '../../services/supabase_sync_service.dart';

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
    setState(() {
      _cajas = r;
      _loading = false;
    });
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
                    color: abierta
                        ? Colors.lightGreen.withValues(alpha: 0.15)
                        : null,
                    child: ListTile(
                      leading: Icon(
                          abierta ? Icons.lock_open : Icons.lock_outline,
                          color: abierta ? Colors.green : null),
                      title: Text('${c['codigo_caja']}  •  ${c['fecha']}'),
                      subtitle: subt != null && subt.isNotEmpty
                          ? Text(subt,
                              maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: FutureBuilder<(int,int)>(
                        future: SupaSyncService.I
                            .cajaOutboxCounts(c['codigo_caja'] as String),
                        builder: (ctx, snap) {
                          final has = snap.hasData;
                          final pend = has ? snap.data!.$1 : null;
                          final errs = has ? snap.data!.$2 : null;
                          final synced = has && (pend == 0 && errs == 0);
                          final icon = Icon(
                            synced ? Icons.cloud_done : Icons.cloud_upload,
                            size: 18,
                            color: synced ? Colors.green : Colors.orange,
                          );
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              icon,
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right),
                            ],
                          );
                        },
                      ),
                      onTap: () async {
                        // Mostrar resumen (reutilizamos CajaPage si está abierta, o vista de solo-lectura inline)
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    CajaResumenPage(cajaId: c['id'] as int)));
                        if (!context.mounted) return;
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
  bool _syncing = false;
  // Progreso de sincronización
  int? _progTotal;
  int _progDone = 0;
  String? _progStage;
  StreamSubscription<SyncProgress>? _progSub;

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
    setState(() {
      _caja = c;
      _resumen = r;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _progSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_caja == null) {
      return const Scaffold(body: Center(child: Text('Caja no encontrada')));
    }
    final resumen = _resumen!;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Caja'),
        actions: [
          // Forzar sincronización manual (on-demand)
          IconButton(
            tooltip: 'Forzar sincronización',
            onPressed: _syncing
                ? null
                : () async {
                    setState(() {
                      _syncing = true;
                      _progTotal = null;
                      _progDone = 0;
                      _progStage = null;
                    });
                    _progSub?.cancel();
                    _progSub = SupaSyncService.I.progress$.listen((p) {
                      if (!mounted) return;
                      setState(() {
                        _progTotal = p.total;
                        _progDone = p.processed;
                        _progStage = p.stage;
                      });
                    });
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    try {
                      // Antes de enviar, encolar caja_items de esta caja
                      try {
                        await SupaSyncService.I.enqueueItemsForCajaId(_caja!['id'] as int);
                      } catch (_) {}
                      await SupaSyncService.I.syncNow();
                      final det = SupaSyncService.I.lastSyncDetails();
                      await showDialog<void>(
                        context: nav.context,
                        builder: (ctx) {
                          return AlertDialog(
                            title: const Text('Resultado de sincronización'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cajas OK: ${det.cajasOk}  •  Items OK: ${det.itemsOk}'),
                                Text('Cajas Fallidas: ${det.cajasFail}  •  Items Fallidos: ${det.itemsFail}'),
                                if (det.errorRowsOk > 0)
                                  Text('Errores reportados: ${det.errorRowsOk}'),
                                const SizedBox(height: 8),
                                if (det.errors.isNotEmpty)
                                  const Text('Detalles de errores (últimos):'),
                                ...det.errors.take(3).map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cerrar'),
                              ),
                            ],
                          );
                        },
                      );
                      if (!nav.mounted) return;
                      final codigo = (_caja?['codigo_caja'] as String?) ?? '';
                      if (codigo.isNotEmpty) {
                        final counts = await SupaSyncService.I.cajaOutboxCounts(codigo);
                        if (counts.$2 > 0) {
                          final err = await SupaSyncService.I.cajaLastError(codigo);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Error de sincronización: ${err ?? 'ver detalles en estado'}'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        } else if (counts.$1 == 0) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Sincronización completada'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Pendientes en cola: ${counts.$1}'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Sincronización ejecutada')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('No se pudo sincronizar: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _syncing = false);
                      _progSub?.cancel();
                      _progSub = null;
                      if (mounted) {
                        setState(() {
                          _progStage = null;
                          _progTotal = null;
                          _progDone = 0;
                        });
                      }
                    }
                  },
            icon: _syncing
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
          // Imprimir por USB (por defecto)
          IconButton(
            tooltip: 'Imprimir en térmica (USB)',
            icon: const Icon(Icons.print),
            onPressed: () async {
              await _printCajaConDecision();
            },
          ),
          // Exportar JSON (ya existente)
          IconButton(
            tooltip: 'Exportar/Compartir (JSON)',
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ExportService().shareCajaFile(_caja!['id'] as int);
              } catch (e) {
                if (!context.mounted) return;
                messenger.showSnackBar(const SnackBar(
                    content: Text('No se pudo exportar la caja')));
              }
            },
          ),
          // Exportar a PDF (visualización actual)
          IconButton(
            tooltip: 'Exportar a PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () async {
              try {
                await Printing.layoutPdf(
                  onLayout: (f) => PrintService().buildCajaResumenPdf(_caja!['id'] as int),
                  name: 'cierre_caja_${_caja!['id']}.pdf',
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo generar el PDF: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_progTotal != null && (_progTotal ?? 0) > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _progDone / (_progTotal!.toDouble()), minHeight: 6),
                  const SizedBox(height: 4),
                  Text('Sincronizando: $_progDone/$_progTotal${_progStage != null ? ' · $_progStage' : ''}', style: const TextStyle(fontSize: 12)),
                ],
              )
            else if (_syncing)
              const LinearProgressIndicator(minHeight: 3),
            // Encabezado con código de caja, que puede ser largo: usar wrap
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Icon(Icons.store, size: 18),
                Text('Caja:', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  _caja!['codigo_caja']?.toString() ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Fecha: ${_caja!['fecha']} • Estado: ${_caja!['estado']}'),
            const SizedBox(height: 8),
            FutureBuilder<(int,int)>(
              future: SupaSyncService.I
                  .cajaOutboxCounts(_caja!['codigo_caja'] as String),
              builder: (ctx, snap) {
                final has = snap.hasData;
                final pend = has ? snap.data!.$1 : null;
                final errs = has ? snap.data!.$2 : null;
                final synced = has && (pend == 0 && errs == 0);
                final last = SupaSyncService.I.lastSyncAt;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(synced ? Icons.cloud_done : Icons.cloud_upload,
                            color: synced ? Colors.green : Colors.orange,
                            size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                synced
                                    ? 'Sincronizado'
                                    : 'Pendientes: ${pend ?? '-'} • Errores: ${errs ?? '-'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (last != null)
                                Text(
                                  'Últ. sync: ${last.hour.toString().padLeft(2,'0')}:${last.minute.toString().padLeft(2,'0')}:${last.second.toString().padLeft(2,'0')}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!synced)
                      FutureBuilder<String?>(
                        future: SupaSyncService.I.cajaLastError(
                            _caja!['codigo_caja'] as String),
                        builder: (ctx, snapErr) {
                          final m = snapErr.data;
                          if (m == null || m.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Último error: $m',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.redAccent),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            FutureBuilder<Map<String,int>>(
              future: SupaSyncService.I.cajaSyncPlan(
                cajaId: _caja!['id'] as int,
                codigoCaja: _caja!['codigo_caja'] as String,
              ),
              builder: (ctx, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final p = snap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan → Caja: ${p['expectedCaja']} • Items: ${p['expectedItems']}', style: const TextStyle(fontSize: 12)),
                    Text('Pendientes → Caja: ${p['pendingCaja']} • Items: ${p['pendingItems']}', style: const TextStyle(fontSize: 12)),
                    if ((p['errorCaja'] ?? 0) > 0 || (p['errorItems'] ?? 0) > 0)
                      Text('Errores → Caja: ${p['errorCaja']} • Items: ${p['errorItems']}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            if ((_caja!['disciplina'] as String?)?.isNotEmpty == true)
              Text('Disciplina: ${_caja!['disciplina']}'),
            Text('Fondo inicial: ${formatCurrency((_caja!['fondo_inicial'] as num?) ?? 0)}'),
            const SizedBox(height: 8),
            if ((_caja!['descripcion_evento'] as String?)?.isNotEmpty == true)
              Text('Descripción del evento: ${_caja!['descripcion_evento']}'),
            if ((_caja!['observaciones_apertura'] as String?)?.isNotEmpty ==
                true)
              Text('Obs. apertura: ${_caja!['observaciones_apertura']}'),
            if ((_caja!['obs_cierre'] as String?)?.isNotEmpty == true)
              Text('Obs. cierre: ${_caja!['obs_cierre']}'),
            if ((_caja!['diferencia'] as num?) != null)
              Text('Diferencia: ${formatCurrency(((_caja!['diferencia'] as num?) ?? 0))}'),
            // Entradas vendidas (mostrar 0 si no hay valor)
            Text('Entradas vendidas: ${((_caja!['entradas'] as num?) ?? 0).toInt()}'),
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
          ],
        ),
      ),
    );
  }

  Future<void> _printCajaConDecision() async {
    final messenger = ScaffoldMessenger.of(context);
    final usb = UsbPrinterService();
    try {
      final connected = await usb.isConnected();
      if (!connected) {
        if (!context.mounted) return;
        await _mostrarDialogoImpresionFallback();
        return;
      }
      final ok = await PrintService()
          .printCajaResumenUsbOnly(_caja!['id'] as int);
      if (!ok) {
        if (!context.mounted) return;
        await _mostrarDialogoImpresionFallback();
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error al imprimir: $e')),
      );
    }
  }

  Future<void> _mostrarDialogoImpresionFallback() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Impresora no disponible'),
        content: const Text(
            '¿Querés ir a Configurar impresora o ver Previsualización PDF?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Printing.layoutPdf(
                onLayout: (f) => PrintService()
                    .buildCajaResumenPdf(_caja!['id'] as int),
                name: 'cierre_caja_${_caja!['id']}.pdf',
              );
            },
            child: const Text('Previsualización PDF'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PrinterTestPage()),
              );
            },
            child: const Text('Config impresora'),
          ),
        ],
      ),
    );
  }
}
