// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/caja_service.dart';
import '../../services/export_service.dart';
import '../../services/print_service.dart';
import '../format.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/usb_printer_service.dart';
import 'printer_test_page.dart';
// import '../../services/supabase_sync_service.dart'; // Oculto sync en listado
import 'caja_tickets_page.dart';
import '../../services/movimiento_service.dart';
import '../../data/dao/db.dart';
// url_launcher y path ya no se usan para abrir carpeta; se removieron

class CajaListPage extends StatefulWidget {
  const CajaListPage({super.key});
  @override
  State<CajaListPage> createState() => _CajaListPageState();
}

class _CajaListPageState extends State<CajaListPage> {
  final _svc = CajaService();
  List<Map<String, dynamic>> _cajas = [];
  bool _loading = true;
  bool _mostrarOcultas = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.listarCajas(incluirOcultas: _mostrarOcultas);
    setState(() {
      _cajas = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de cajas'),
        actions: [
          IconButton(
            tooltip: _mostrarOcultas ? 'Ocultar cajas ocultas' : 'Mostrar cajas ocultas',
            icon: Icon(_mostrarOcultas ? Icons.visibility : Icons.visibility_off),
            onPressed: () async {
              setState(() {
                _mostrarOcultas = !_mostrarOcultas;
                _loading = true;
              });
              await _load();
            },
          ),
          IconButton(
            tooltip: 'Exportar todo (CSV)',
            icon: const Icon(Icons.file_download),
            onPressed: () async {
              // Solo exporta cajas visibles. Si el toggle muestra ocultas, igual se filtra por visible=1.
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Exportar CSV de todas las cajas visibles'),
                  content: const Text('¿Querés Compartir el archivo o Descargarlo?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    TextButton(onPressed: () => Navigator.pop(ctx, 'share'), child: const Text('Compartir')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, 'download'), child: const Text('Descargar')),
                  ],
                ),
              );
              if (choice == 'share') {
                try {
                  final file = await ExportService().exportVisibleCajasToCsvInDownloads();
                  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Cajas historial', title: 'Cajas historial'));
                } catch (e, st) {
                  AppDatabase.logLocalError(scope: 'caja_list.share_all_csv', error: e, stackTrace: st);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo compartir CSV')));
                }
              } else if (choice == 'download') {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final file = await ExportService().exportVisibleCajasToCsvInDownloads();
                  await _showExportDialog(
                    file.path,
                    hint: 'Guardado en Descargas (/storage/emulated/0/Download):',
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('CSV guardado en Descargas')),
                    );
                  }
                  final open = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Abrir archivo'),
                      content: const Text('¿Querés abrir el CSV descargado?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
                      ],
                    ),
                  );
                  if (open == true) {
                    await ExportService().openFile(file.path);
                  }
                } catch (e1, st1) {
                  AppDatabase.logLocalError(scope: 'caja_list.export_all_csv_downloads_primary_failed', error: e1, stackTrace: st1);
                  try {
                    final savedPath = await ExportService().saveVisibleCajasCsvToDownloadsViaMediaStore();
                    await _showExportDialog(
                      savedPath,
                      hint: 'Guardado en Descargas vía MediaStore:',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CSV guardado vía MediaStore')),
                      );
                    }
                    final open = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Abrir archivo'),
                        content: const Text('¿Querés abrir el CSV descargado?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
                        ],
                      ),
                    );
                    if (open == true) {
                      await ExportService().openFile(savedPath);
                    }
                  } catch (e2, st2) {
                    AppDatabase.logLocalError(scope: 'caja_list.export_all_csv_downloads_fallback_failed', error: e2, stackTrace: st2);
                    if (!context.mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('No se pudo descargar CSV: $e2')));
                  }
                }
              }
            },
          ),
        ],
      ),
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
                  final visible = ((c['visible'] as num?) ?? 1) != 0;
                  return Container(
                    color: abierta
                        ? Colors.lightGreen.withValues(alpha: 0.15)
                        : (!visible ? Colors.grey.withValues(alpha: 0.12) : null),
                    child: ListTile(
                      leading: Icon(
                          abierta ? Icons.lock_open : Icons.lock_outline,
                          color: abierta ? Colors.green : null),
                      title: Text('${c['codigo_caja']}  •  ${c['fecha']}${!visible ? '  •  (Oculta)' : ''}'),
                      subtitle: subt != null && subt.isNotEmpty
                          ? Text(subt,
                              maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
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

  Future<void> _showExportDialog(String filePath, {String? hint}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Archivo guardado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hint != null)
                SelectableText('$hint\n$filePath')
              else ...[
                const Text('La exportación se guardó en:'),
                const SizedBox(height: 8),
                SelectableText(filePath),
              ],
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
  double _movIngresos = 0.0;
  double _movRetiros = 0.0;
  // Progreso de sincronización
  

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic>? c;
    Map<String, dynamic>? r;
    try {
      c = await _svc.getCajaById(widget.cajaId);
      if (c != null) {
        r = await _svc.resumenCaja(c['id'] as int);
        try {
          final mt = await MovimientoService().totalesPorCaja(c['id'] as int);
          _movIngresos = (mt['ingresos'] as num?)?.toDouble() ?? 0.0;
          _movRetiros = (mt['retiros'] as num?)?.toDouble() ?? 0.0;
        } catch (e, st) {
          AppDatabase.logLocalError(scope: 'caja_list.totales_mov', error: e, stackTrace: st, payload: {'cajaId': c['id']});
        }
      }
    } catch (e, st) {
      AppDatabase.logLocalError(scope: 'caja_list.load', error: e, stackTrace: st, payload: {'cajaId': widget.cajaId});
    }
    setState(() {
      _caja = c;
      _resumen = r;
      _loading = false;
    });
  }

  @override
  void dispose() {
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
          //title: const Text('Caja'),
        actions: [
          // Ver tickets de la caja (solo lectura)
          IconButton(
            tooltip: 'Ver tickets de la caja',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CajaTicketsPage(
                    cajaId: _caja!['id'] as int,
                    codigoCaja: _caja!['codigo_caja'] as String,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.receipt_long),
          ),
          
          // Imprimir por USB (por defecto)
          IconButton(
            tooltip: 'Imprimir en térmica (USB)',
            icon: const Icon(Icons.print),
            onPressed: () async {
              await _printCajaConDecision();
            },
          ),
          // Exportar JSON: ocultado según requerimiento
          // Exportar CSV (modal: Compartir o Descargar)
          IconButton(
            tooltip: 'Exportar/Compartir (CSV)',
            icon: const Icon(Icons.grid_on),
            onPressed: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Exportar CSV'),
                  content: const Text('¿Querés Compartir el archivo o Descargarlo?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    TextButton(onPressed: () => Navigator.pop(ctx, 'share'), child: const Text('Compartir')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, 'download'), child: const Text('Descargar')),
                  ],
                ),
              );
              if (choice == 'share') {
                try {
                  await ExportService().shareCajaCsv(_caja!['id'] as int);
                } catch (e, st) {
                  AppDatabase.logLocalError(scope: 'caja_list.share_csv', error: e, stackTrace: st);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo compartir CSV')));
                }
              } else if (choice == 'download') {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  // Prioridad: escritura directa en /storage/emulated/0/Download
                  final file = await ExportService().exportCajaToCsvInDownloads(_caja!['id'] as int);
                  await _showExportDialog(
                    file.path,
                    hint: 'Guardado en Descargas (/storage/emulated/0/Download):',
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('CSV guardado en Descargas')),
                    );
                  }
                  final open = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Abrir archivo'),
                      content: const Text('¿Querés abrir el CSV descargado?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
                      ],
                    ),
                  );
                  if (open == true) {
                    await ExportService().openFile(file.path);
                  }
                } catch (e1, st1) {
                  // Fallback: MediaStore (FileSaver) en Descargas
                  AppDatabase.logLocalError(scope: 'caja_list.export_csv_downloads_primary_failed', error: e1, stackTrace: st1, payload: {'cajaId': _caja!['id']});
                  try {
                    final savedPath = await ExportService().saveCsvToDownloadsViaMediaStore(_caja!['id'] as int);
                    await _showExportDialog(
                      savedPath,
                      hint: 'Guardado en Descargas vía MediaStore:',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CSV guardado vía MediaStore')),
                      );
                    }
                    final open = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Abrir archivo'),
                        content: const Text('¿Querés abrir el CSV descargado?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
                        ],
                      ),
                    );
                    if (open == true) {
                      await ExportService().openFile(savedPath);
                    }
                  } catch (e2, st2) {
                    AppDatabase.logLocalError(scope: 'caja_list.export_csv_downloads_fallback_failed', error: e2, stackTrace: st2, payload: {'cajaId': _caja!['id']});
                    if (!context.mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('No se pudo descargar CSV: $e2')));
                  }
                }
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
              } catch (e, st) {
                AppDatabase.logLocalError(scope: 'caja_list.export_pdf', error: e, stackTrace: st, payload: {'cajaId': _caja!['id']});
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo generar el PDF: $e')),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'toggle_visible') {
                final currentVisible = (((_caja?['visible'] as num?) ?? 1) != 0);
                final estado = (_caja?['estado'] as String?) ?? '';
                if (estado == 'ABIERTA' && currentVisible) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se puede ocultar una caja ABIERTA')),
                  );
                  return;
                }
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(currentVisible ? 'Ocultar caja' : 'Mostrar caja'),
                    content: Text(currentVisible
                        ? '¿Querés ocultar esta caja del historial?'
                        : '¿Querés volver a mostrar esta caja en el historial?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    await CajaService().setCajaVisible(_caja!['id'] as int, !currentVisible);
                    await _load();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(!currentVisible ? 'Caja visible nuevamente' : 'Caja ocultada')),
                    );
                  } catch (e, st) {
                    AppDatabase.logLocalError(scope: 'caja_list.toggle_visible', error: e, stackTrace: st, payload: {'cajaId': _caja!['id']});
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo actualizar visibilidad: $e')),
                    );
                  }
                }
              }
            },
            itemBuilder: (ctx) {
              final currentVisible = (((_caja?['visible'] as num?) ?? 1) != 0);
              final estado = (_caja?['estado'] as String?) ?? '';
              return [
                PopupMenuItem<String>(
                  value: 'toggle_visible',
                  enabled: !(estado == 'ABIERTA' && currentVisible),
                  child: Text(currentVisible ? 'Ocultar caja' : 'Mostrar caja'),
                ),
              ];
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            
            // Se quita cabecera con código de caja para evitar recortes
            Text('Fecha: ${_caja!['fecha']} • Estado: ${_caja!['estado']}'),
            const SizedBox(height: 8),
            
            const SizedBox(height: 6),
            const SizedBox(height: 8),
            if ((_caja!['disciplina'] as String?)?.isNotEmpty == true)
              Text('Disciplina: ${_caja!['disciplina']}'),
            if ((_caja!['cajero_apertura'] as String?)?.isNotEmpty == true)
              Text('Cajero apertura: ${_caja!['cajero_apertura']}'),
            if ((_caja!['cajero_cierre'] as String?)?.isNotEmpty == true)
              Text('Cajero cierre: ${_caja!['cajero_cierre']}'),
            const SizedBox(height: 8),
            if ((_caja!['descripcion_evento'] as String?)?.isNotEmpty == true)
              Text('Descripción del evento: ${_caja!['descripcion_evento']}'),
            if ((_caja!['observaciones_apertura'] as String?)?.isNotEmpty ==
                true)
              Text('Obs. apertura: ${_caja!['observaciones_apertura']}'),
            if ((_caja!['obs_cierre'] as String?)?.isNotEmpty == true)
              Text('Obs. cierre: ${_caja!['obs_cierre']}'),
            Text('Fondo inicial: ${formatCurrency((_caja!['fondo_inicial'] as num?) ?? 0)}'),
            // Nuevos datos debajo de Fondo inicial
            Text('Efectivo declarado en caja: ${formatCurrency(((_caja!['conteo_efectivo_final'] as num?) ?? 0))}'),
            if ((_caja!['diferencia'] as num?) != null)
              Text('Diferencia: ${formatCurrency(((_caja!['diferencia'] as num?) ?? 0))}'),
            // Entradas vendidas (mostrar 0 si no hay valor)
            Text('Entradas vendidas: ${((_caja!['entradas'] as num?) ?? 0).toInt()}'),
            const SizedBox(height: 8),
            Text('Ingresos registrados: ${formatCurrency(_movIngresos)}'),
            Text('Retiros registrados: ${formatCurrency(_movRetiros)}'),
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

  Future<void> _showExportDialog(String filePath, {String? hint}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Archivo guardado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mostrar UNA sola línea con la ruta efectiva.
              // Si hay hint, combinar hint + path en un solo SelectableText.
              if (hint != null)
                SelectableText('$hint\n$filePath')
              else ...[
                const Text('La exportación se guardó en:'),
                const SizedBox(height: 8),
                SelectableText(filePath),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
            // Evitar abrir carpeta con file:// para no disparar FileUriExposedException en Android.
            // Usar el flujo previo de "Abrir archivo" que llama a ExportService.openFile(filePath).
          ],
        );
      },
    );
  }

  // Flujo anterior de selector/compartir removido según nueva especificación
}
