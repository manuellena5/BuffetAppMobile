import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsbPrinterService {
  static const MethodChannel _ch = MethodChannel('usb_printer');
  static const _kVendor = 'usb_vendor_id';
  static const _kProduct = 'usb_product_id';
  static const _kDeviceName = 'usb_device_name';

  Future<List<Map<String, dynamic>>> listDevices() async {
    final list = await _ch.invokeMethod<List<dynamic>>('listDevices');
    return (list ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<bool> requestPermission(int vendorId, int productId) async {
    final ok = await _ch.invokeMethod('requestPermission', {
      'vendorId': vendorId,
      'productId': productId,
    });
    return (ok as bool?) ?? false;
  }

  Future<bool> connect(int vendorId, int productId) async {
    final ok = await _ch.invokeMethod('connect', {
      'vendorId': vendorId,
      'productId': productId,
    });
    return (ok as bool?) ?? false;
  }

  Future<bool> printBytes(Uint8List bytes) async {
    final ok = await _ch.invokeMethod('printBytes', {
      'bytes': bytes,
    });
    return (ok as bool?) ?? false;
  }

  Future<void> disconnect() async {
    await _ch.invokeMethod('disconnect');
  }

  Future<bool> isConnected() async {
    final ok = await _ch.invokeMethod('isConnected');
    return (ok as bool?) ?? false;
  }

  // Preferencias: guardar y recuperar dispositivo por defecto
  Future<void> saveDefaultDevice({required int vendorId, required int productId, String? deviceName}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kVendor, vendorId);
    await sp.setInt(_kProduct, productId);
    if (deviceName != null) {
      await sp.setString(_kDeviceName, deviceName);
    }
  }

  Future<Map<String, dynamic>?> getDefaultDevice() async {
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
}
