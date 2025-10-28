import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'dart:typed_data';
import '../../services/usb_printer_service.dart';

import '../../services/print_service.dart';
import '../../services/caja_service.dart';
import '../../data/dao/db.dart';
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

  Future<void> _refreshPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      setState(() => _printers = printers);
    } catch (_) {
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
    } catch (_) {}
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impresora USB conectada automáticamente')));
    }
  }

  Future<void> _refreshUsb() async {
    try {
      final list = await _usb.listDevices();
      setState(() => _usbDevices = list);
    } catch (_) {
      setState(() => _usbDevices = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Config. impresora')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Preferencias de impresión', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Imprimir logo en cierre (USB)'),
              value: _printLogoEscpos,
              onChanged: (v) async {
                setState(() => _printLogoEscpos = v);
                try {
                  final sp = await SharedPreferences.getInstance();
                  await sp.setBool('print_logo_escpos', v);
                } catch (_) {}
              },
            ),
            const Divider(height: 24),
            Text('USB directa', style: Theme.of(context).textTheme.titleMedium),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<Map<String, dynamic>>(
                  key: ValueKey('usb_${_usbSel != null ? '${_usbSel!['vendorId']}_${_usbSel!['productId']}' : 'none'}_${_usbDevices.length}'),
                  initialValue: _usbSel,
                  items: _usbDevices.map((d) => DropdownMenuItem(
                    value: d,
                    child: Text('${d['deviceName']} (${d['vendorId']}:${d['productId']})'),
                  )).toList(),
                  onChanged: (v) => setState(() => _usbSel = v),
                  hint: const Text('Seleccioná dispositivo USB'),
                ),
              ),
              IconButton(onPressed: _refreshUsb, icon: const Icon(Icons.refresh)),
            ]),
            if (_connected && _usbSel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.usb, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Conectado: ${_usbSel!['deviceName']} (${_usbSel!['vendorId']}:${_usbSel!['productId']})')),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ElevatedButton(
                onPressed: _usbSel == null ? null : () async {
                  final v = _usbSel!['vendorId'] as int;
                  final p = _usbSel!['productId'] as int;
                  var perm = await _usb.requestPermission(v, p);
                  if (!perm) {
                    // Reintento automático breve: algunos dispositivos requieren segundo intento
                    await Future.delayed(const Duration(milliseconds: 400));
                    perm = await _usb.requestPermission(v, p);
                    if (!perm) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso USB denegado. Volvé a intentar.')));
                      return;
                    }
                  }
                  final ok = await _usb.connect(v, p);
                    if (!context.mounted) return;
                  if (ok) {
                    await _usb.saveDefaultDevice(vendorId: v, productId: p, deviceName: _usbSel!['deviceName'] as String?);
                  }
                  setState(() => _connected = ok);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Conectado' : 'No conectó')));
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
                    final ok = await _usb.printBytes(Uint8List.fromList(b.toBytes()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Impreso por USB' : 'No se pudo imprimir por USB')));
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
                          Text('Ayuda para conectar la impresora USB:', style: TextStyle(fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text('• Conectá la impresora por USB (OTG) y encendela.'),
                          Text('• Si Android pide permiso, tocá "Permitir".'),
                          Text('• Tocá "Conectar USB" y luego "Refrescar" si no aparece en la lista.'),
                          Text('• Probá desconectar y volver a conectar el cable USB/OTG.'),
                          Text('• Reiniciá la app si persiste el problema.'),
                          Text('• Verificá los permisos en Android: Ajustes > Apps > BuffetApp > Permisos > USB.'),
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
                // Buscar último ticket o generar uno de prueba en memoria
        final db = await AppDatabase.instance();
        final last = await db.query('tickets',
                    columns: ['id'], orderBy: 'id DESC', limit: 1);
                final id = last.isNotEmpty ? last.first['id'] as int : await _crearTicketDummy();
                try {
                  final connected = await _usb.isConnected();
                  if (!connected) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay impresora USB conectada.')));
                    return;
                  }
                  final ok = await PrintService().printTicketUsbOnly(id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Ticket impreso por USB' : 'No se pudo imprimir por USB')));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al imprimir: $e')));
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
                if (cajaId == null) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('No hay cajas para imprimir.')));
                  return;
                }
                try {
                  final connected = await _usb.isConnected();
                  if (!connected) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('No hay impresora USB conectada.')));
                    return;
                  }
                  final ok = await PrintService().printCajaResumenUsbOnly(cajaId);
                  if (!context.mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text(ok ? 'Cierre impreso por USB' : 'No se pudo imprimir por USB')));
                } catch (e) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text('Error al imprimir: $e')));
                }
              },
              child: const Text('Test Cierre de caja'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _crearTicketDummy() async {
    // Genera un ticket temporal con producto/ticket de prueba si el DB está vacío
    final db = await AppDatabase.instance();
    final p = await db.query('products', columns: ['id'], limit: 1);
    int productoId;
    if (p.isEmpty) {
      productoId = await db.insert('products', {
        'codigo_producto': 'DEMO',
        'nombre': 'Hamburguesa',
        'precio_venta': 1500,
        'stock_actual': 999,
        'stock_minimo': 0,
        'categoria_id': null,
        'visible': 1,
        'color': null,
      });
    } else {
      productoId = p.first['id'] as int;
    }
    final now = DateTime.now();
    final fecha =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final hora =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final ventaId = await db.insert('ventas', {
      'uuid': 'demo',
      'fecha_hora': '$fecha $hora',
      'total_venta': 1500,
      'status': 'No impreso',
      'activo': 1,
      'metodo_pago_id': 1,
      'caja_id': null,
    });
    final ticketId = await db.insert('tickets', {
      'venta_id': ventaId,
      'categoria_id': null,
      'producto_id': productoId,
      'fecha_hora': '$fecha $hora',
      'status': 'Impreso',
      'total_ticket': 1500,
      'identificador_ticket': null,
    });
    await db.update(
        'tickets',
        {
          'identificador_ticket':
              'DEMO-${now.year}${now.month}${now.day}-$ticketId'
        },
        where: 'id=?',
        whereArgs: [ticketId]);
    return ticketId;
  }
}
