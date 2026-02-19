import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'dart:typed_data';
import '../services/usb_printer_service.dart';
import '../widgets/responsive_container.dart';

import '../services/print_service.dart';
import '../../buffet/services/caja_service.dart';
import '../../../data/dao/db.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterTestPage extends StatefulWidget {
  const PrinterTestPage({super.key});
  @override
  State<PrinterTestPage> createState() => _PrinterTestPageState();
}

class _PrinterTestPageState extends State<PrinterTestPage> {
  Printer? _selected;
  List<Printer> _printers = const [];
  final _usb = UsbPrinterService();
  List<Map<String, dynamic>> _usbDevices = const [];
  Map<String, dynamic>? _usbSel;
  bool _connected = false;
  bool _printLogoEscpos = true;
  int _paperWidthMm = 80; // 58, 75, 80

  Future<void> _refreshPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      setState(() => _printers = printers);
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'printer_test.refresh_printers', error: e, stackTrace: st);
      // Algunos dispositivos no exponen lista; seguimos con pickPrinter
      setState(() => _printers = const []);
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshPrinters();
    _refreshUsb();
    _autoConnectIfSaved();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getBool('print_logo_escpos');
      setState(() => _printLogoEscpos = v ?? true);
      final mm = sp.getInt('paper_width_mm');
      setState(
          () => _paperWidthMm = (mm == 58 || mm == 75 || mm == 80) ? mm! : 80);
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'printer_test.load_prefs', error: e, stackTrace: st);
    }
  }

  Future<void> _autoConnectIfSaved() async {
    final ok = await _usb.autoConnectSaved();
    if (!context.mounted) return;
    if (ok) {
      final saved = await _usb.getDefaultDevice();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _usbSel = saved;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impresora USB conectada automáticamente')));
    }
  }

  Future<void> _refreshUsb() async {
    try {
      final list = await _usb.listDevices();
      setState(() => _usbDevices = list);
    } catch (e, st) {
      AppDatabase.logLocalError(
          scope: 'printer_test.refresh_usb', error: e, stackTrace: st);
      setState(() => _usbDevices = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Config. impresora')),
      body: LandscapeCenteredBody(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Preferencias de impresión',
                  style: Theme.of(context).textTheme.titleMedium),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _paperWidthMm,
                    decoration: const InputDecoration(
                      labelText: 'Ancho de papel',
                      helperText: 'Afecta USB y PDF (58/75/80 mm)',
                    ),
                    items: const [58, 75, 80]
                        .map((mm) =>
                            DropdownMenuItem(value: mm, child: Text('$mm mm')))
                        .toList(),
                    onChanged: (mm) async {
                      if (mm == null) return;
                      setState(() => _paperWidthMm = mm);
                      try {
                        final sp = await SharedPreferences.getInstance();
                        await sp.setInt('paper_width_mm', mm);
                      } catch (_) {}
                    },
                  ),
                ),
              ]),
              const Divider(height: 24),
              Text('USB directa',
                  style: Theme.of(context).textTheme.titleMedium),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<Map<String, dynamic>>(
                    key: ValueKey(
                        'usb_${_usbSel != null ? '${_usbSel!['vendorId']}_${_usbSel!['productId']}' : 'none'}_${_usbDevices.length}'),
                    initialValue: _usbSel,
                    items: _usbDevices
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(
                                  '${d['deviceName']} (${d['vendorId']}:${d['productId']})'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _usbSel = v),
                    hint: const Text('Seleccioná dispositivo USB'),
                  ),
                ),
                IconButton(
                    onPressed: _refreshUsb, icon: const Icon(Icons.refresh)),
              ]),
              if (_connected && _usbSel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.usb, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              'Conectado: ${_usbSel!['deviceName']} (${_usbSel!['vendorId']}:${_usbSel!['productId']})')),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ElevatedButton(
                  onPressed: _usbSel == null
                      ? null
                      : () async {
                          final v = _usbSel!['vendorId'] as int;
                          final p = _usbSel!['productId'] as int;
                          var perm = await _usb.requestPermission(v, p);
                          if (!perm) {
                            // Reintento automático breve: algunos dispositivos requieren segundo intento
                            await Future.delayed(
                                const Duration(milliseconds: 400));
                            perm = await _usb.requestPermission(v, p);
                            if (!perm) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Permiso USB denegado. Volvé a intentar.')));
                              return;
                            }
                          }
                          final ok = await _usb.connect(v, p);
                          if (!context.mounted) return;
                          if (ok) {
                            await _usb.saveDefaultDevice(
                                vendorId: v,
                                productId: p,
                                deviceName: _usbSel!['deviceName'] as String?);
                          }
                          setState(() => _connected = ok);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'Conectado' : 'No conectó')));
                          // Refrescar lista tras intento de conexión
                          await _refreshUsb();
                        },
                  child: const Text('Conectar USB'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // ESC/POS básico
                    final b = BytesBuilder();
                    b.add([0x1B, 0x40]); // init
                    b.add([0x1B, 0x21, 0x20]); // doble alto
                    b.add('BuffetApp\n'.codeUnits);
                    b.add([0x1B, 0x21, 0x00]);
                    b.add('Prueba USB ESC/POS\n\n'.codeUnits);
                    b.add([0x1D, 0x56, 0x42, 0x00]); // corte parcial
                    try {
                      final ok = await _usb
                          .printBytes(Uint8List.fromList(b.toBytes()));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Impreso por USB'
                              : 'No se pudo imprimir por USB')));
                    } catch (e, st) {
                      AppDatabase.logLocalError(
                          scope: 'printer_test.print_usb_bytes',
                          error: e,
                          stackTrace: st);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Imprimir USB (test)'),
                ),
              ]),
              const Divider(height: 24),
              // Se quita el rótulo "Disponibles" por no aportar valor; se mantiene la lista.
              Expanded(
                child: _printers.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Ayuda para conectar la impresora USB:',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            SizedBox(height: 8),
                            Text(
                                '• Conectá la impresora por USB (OTG) y encendela.'),
                            Text('• Si Android pide permiso, tocá "Permitir".'),
                            Text(
                                '• Tocá "Conectar USB" y luego "Refrescar" si no aparece en la lista.'),
                            Text(
                                '• Probá desconectar y volver a conectar el cable USB/OTG.'),
                            Text('• Reiniciá la app si persiste el problema.'),
                            Text(
                                '• Verificá los permisos en Android: Ajustes > Apps > BuffetApp > Permisos > USB.'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _printers.length,
                        itemBuilder: (ctx, i) {
                          final p = _printers[i];
                          final selected = _selected?.name == p.name;
                          return ListTile(
                            title: Text(p.name),
                            trailing: selected
                                ? const Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: () => setState(() => _selected = p),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final connected = await _usb.isConnected();
                    if (!connected) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('No hay impresora USB conectada.')));
                      return;
                    }
                    // Si hay algún ticket real, imprimir el último; si no, imprimir ticket DEMO sin tocar DB
                    final db = await AppDatabase.instance();
                    final last = await db.query('tickets',
                        columns: ['id'], orderBy: 'id DESC', limit: 1);
                    bool ok;
                    if (last.isNotEmpty) {
                      final id = last.first['id'] as int;
                      ok = await PrintService().printTicketUsbOnly(id);
                    } else {
                      ok = await PrintService().printTicketSampleUsbOnly();
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Ticket impreso por USB'
                            : 'No se pudo imprimir por USB')));
                  } catch (e, st) {
                    AppDatabase.logLocalError(
                        scope: 'printer_test.print_ticket',
                        error: e,
                        stackTrace: st);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al imprimir: $e')));
                  }
                },
                child: const Text('Test Ticket de venta'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  // Tomar caja abierta o la última cerrada
                  final svc = CajaService();
                  final abierta = await svc.getCajaAbierta();
                  int? cajaId = abierta?['id'] as int?;
                  if (cajaId == null) {
                    final db = await AppDatabase.instance();
                    final last = await db.query('caja_diaria',
                        columns: ['id'], orderBy: 'id DESC', limit: 1);
                    cajaId = last.isNotEmpty ? last.first['id'] as int : null;
                  }
                  try {
                    final connected = await _usb.isConnected();
                    if (!connected) {
                      if (!context.mounted) return;
                      messenger.showSnackBar(const SnackBar(
                          content: Text('No hay impresora USB conectada.')));
                      return;
                    }
                    bool ok;
                    if (cajaId == null) {
                      // Imprimir ejemplo de cierre aunque no haya datos guardados
                      ok = await PrintService().printCajaResumenSampleUsbOnly();
                    } else {
                      ok = await PrintService().printCajaResumenUsbOnly(cajaId);
                    }
                    if (!context.mounted) return;
                    messenger.showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Cierre impreso por USB'
                            : 'No se pudo imprimir por USB')));
                  } catch (e, st) {
                    AppDatabase.logLocalError(
                        scope: 'printer_test.print_cierre',
                        error: e,
                        stackTrace: st,
                        payload: {'cajaId': cajaId});
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                        SnackBar(content: Text('Error al imprimir: $e')));
                  }
                },
                child: const Text('Test Cierre de caja'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Nota: se eliminó la creación de ticket DEMO para evitar consumir IDs.
}
