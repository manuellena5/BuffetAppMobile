import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:win32/win32.dart' as win;

class UsbPrinterService {
  static const MethodChannel _ch = MethodChannel('usb_printer');
  static const _kVendor = 'usb_vendor_id';
  static const _kProduct = 'usb_product_id';
  static const _kDeviceName = 'usb_device_name';

  static const _kWinPrinterName = 'win_printer_name';

  Future<List<String>> listWindowsPrinters() async {
    if (!Platform.isWindows) return const [];

    final pcbNeeded = calloc<ffi.Uint32>();
    final pcReturned = calloc<ffi.Uint32>();

    // Name: NULL para listar impresoras locales/conectadas
    final pName = ffi.nullptr.cast<Utf16>();
    final pEmpty = ffi.Pointer<ffi.Uint8>.fromAddress(0);

    try {
      const level = 4; // PRINTER_INFO_4
      final flags = win.PRINTER_ENUM_LOCAL | win.PRINTER_ENUM_CONNECTIONS;

      // 1) primer llamado para conocer tamaño
      win.EnumPrinters(flags, pName, level, pEmpty, 0, pcbNeeded, pcReturned);
      final needed = pcbNeeded.value;
      if (needed == 0) return const [];

      // 2) segundo llamado con buffer
      final buffer = calloc<ffi.Uint8>(needed);
      try {
        final ok = win.EnumPrinters(
          flags,
          pName,
          level,
          buffer,
          needed,
          pcbNeeded,
          pcReturned,
        );
        if (ok == 0) return const [];

        final count = pcReturned.value;
        final info = buffer.cast<win.PRINTER_INFO_4>();
        final names = <String>[];
        for (var i = 0; i < count; i++) {
          final name = info.elementAt(i).ref.pPrinterName.toDartString();
          final trimmed = name.trim();
          if (trimmed.isNotEmpty) names.add(trimmed);
        }
        names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return names;
      } finally {
        calloc.free(buffer);
      }
    } catch (_) {
      return const [];
    } finally {
      calloc.free(pcReturned);
      calloc.free(pcbNeeded);
    }
  }

  Future<List<Map<String, dynamic>>> listDevices() async {
    if (!Platform.isAndroid) return const [];
    final list = await _ch.invokeMethod<List<dynamic>>('listDevices');
    return (list ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<bool> requestPermission(int vendorId, int productId) async {
    if (!Platform.isAndroid) return false;
    final ok = await _ch.invokeMethod('requestPermission', {
      'vendorId': vendorId,
      'productId': productId,
    });
    return (ok as bool?) ?? false;
  }

  Future<bool> connect(int vendorId, int productId) async {
    if (!Platform.isAndroid) return false;
    final ok = await _ch.invokeMethod('connect', {
      'vendorId': vendorId,
      'productId': productId,
    });
    return (ok as bool?) ?? false;
  }

  Future<bool> printBytes(Uint8List bytes) async {
    if (Platform.isWindows) {
      final name = await getDefaultWindowsPrinterName();
      if (name == null || name.trim().isEmpty) return false;
      return _printRawWindows(printerName: name.trim(), bytes: bytes);
    }

    if (!Platform.isAndroid) return false;

    final ok = await _ch.invokeMethod('printBytes', {
      'bytes': bytes,
    });
    return (ok as bool?) ?? false;
  }

  Future<void> disconnect() async {
    if (Platform.isWindows) {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kWinPrinterName);
      return;
    }
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('disconnect');
  }

  Future<bool> isConnected() async {
    if (Platform.isWindows) {
      final name = await getDefaultWindowsPrinterName();
      if (name == null || name.trim().isEmpty) return false;
      return _canOpenWindowsPrinter(name.trim());
    }
    if (!Platform.isAndroid) return false;
    final ok = await _ch.invokeMethod('isConnected');
    return (ok as bool?) ?? false;
  }

  Future<void> saveDefaultWindowsPrinter({required String printerName}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kWinPrinterName, printerName);
  }

  Future<String?> getDefaultWindowsPrinterName() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kWinPrinterName);
    return v?.trim().isEmpty ?? true ? null : v;
  }

  // Preferencias: guardar y recuperar dispositivo por defecto
  Future<void> saveDefaultDevice(
      {required int vendorId,
      required int productId,
      String? deviceName}) async {
    if (!Platform.isAndroid) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kVendor, vendorId);
    await sp.setInt(_kProduct, productId);
    if (deviceName != null) {
      await sp.setString(_kDeviceName, deviceName);
    }
  }

  Future<Map<String, dynamic>?> getDefaultDevice() async {
    if (!Platform.isAndroid) return null;
    final sp = await SharedPreferences.getInstance();
    if (!sp.containsKey(_kVendor) || !sp.containsKey(_kProduct)) return null;
    return {
      'vendorId': sp.getInt(_kVendor)!,
      'productId': sp.getInt(_kProduct)!,
      'deviceName': sp.getString(_kDeviceName),
    };
  }

  /// Intenta conectarse automáticamente al dispositivo guardado
  Future<bool> autoConnectSaved() async {
    if (Platform.isWindows) {
      final name = await getDefaultWindowsPrinterName();
      if (name == null || name.trim().isEmpty) return false;
      return _canOpenWindowsPrinter(name.trim());
    }

    if (!Platform.isAndroid) return false;
    final saved = await getDefaultDevice();
    if (saved == null) return false;
    final v = saved['vendorId'] as int;
    final p = saved['productId'] as int;
    // solicitar permiso si hace falta
    try {
      final perm = await requestPermission(v, p);
      if (!perm) return false;
    } catch (_) {
      // algunos dispositivos ya tienen permiso
    }
    try {
      return await connect(v, p);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canOpenWindowsPrinter(String printerName) async {
    try {
      final hPrinter = calloc<win.HANDLE>();
      final pName = printerName.toNativeUtf16();
      try {
        final ok = win.OpenPrinter(pName, hPrinter, ffi.nullptr);
        if (ok == 0) return false;
        win.ClosePrinter(hPrinter.value);
        return true;
      } finally {
        calloc.free(pName);
        calloc.free(hPrinter);
      }
    } catch (_) {
      return false;
    }
  }

  Future<bool> _printRawWindows({
    required String printerName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return false;

    try {
      final hPrinter = calloc<win.HANDLE>();
      final pName = printerName.toNativeUtf16();

      final docInfo = calloc<win.DOC_INFO_1>();
      final docName = 'BuffetApp'.toNativeUtf16();
      final dataType = 'RAW'.toNativeUtf16();

      final pcbWritten = calloc<ffi.Uint32>();
      final pData = calloc<ffi.Uint8>(bytes.length);

      try {
        final opened = win.OpenPrinter(pName, hPrinter, ffi.nullptr);
        if (opened == 0) return false;

        docInfo.ref.pDocName = docName;
        docInfo.ref.pOutputFile = ffi.nullptr;
        docInfo.ref.pDatatype = dataType;

        final job = win.StartDocPrinter(hPrinter.value, 1, docInfo);
        if (job == 0) {
          win.ClosePrinter(hPrinter.value);
          return false;
        }

        final started = win.StartPagePrinter(hPrinter.value);
        if (started == 0) {
          win.EndDocPrinter(hPrinter.value);
          win.ClosePrinter(hPrinter.value);
          return false;
        }

        final dataList = pData.asTypedList(bytes.length);
        dataList.setAll(0, bytes);

        final wrote = win.WritePrinter(
          hPrinter.value,
          pData,
          bytes.length,
          pcbWritten,
        );

        win.EndPagePrinter(hPrinter.value);
        win.EndDocPrinter(hPrinter.value);
        win.ClosePrinter(hPrinter.value);

        return wrote != 0;
      } finally {
        calloc.free(pData);
        calloc.free(pcbWritten);
        calloc.free(dataType);
        calloc.free(docName);
        calloc.free(docInfo);
        calloc.free(pName);
        calloc.free(hPrinter);
      }
    } catch (_) {
      return false;
    }
  }
}
