package com.buffetApp

import android.app.PendingIntent
import android.content.*
import android.hardware.usb.*
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "usb_printer"
		private const val ACTION_USB_PERMISSION = "com.buffetApp.USB_PERMISSION"
	}

	private lateinit var usbManager: UsbManager
	private var connection: UsbDeviceConnection? = null
	private var endpointOut: UsbEndpoint? = null
	private var claimedInterface: UsbInterface? = null
	private var currentDevice: UsbDevice? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		usbManager = getSystemService(USB_SERVICE) as UsbManager

		val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
		channel.setMethodCallHandler { call, result ->
			when (call.method) {
				"isConnected" -> {
					result.success(connection != null && endpointOut != null)
				}
				"listDevices" -> {
					val list = usbManager.deviceList.values.map {
						mapOf(
							"vendorId" to it.vendorId,
							"productId" to it.productId,
							"deviceName" to it.deviceName,
							"manufacturerName" to try { it.manufacturerName } catch (_: Exception) { null }
						)
					}
					result.success(list)
				}
				"requestPermission" -> {
					val vendorId = call.argument<Int>("vendorId")
					val productId = call.argument<Int>("productId")
					if (vendorId == null || productId == null) {
						result.error("bad_args", "vendorId/productId requeridos", null)
						return@setMethodCallHandler
					}
					val device = findDevice(vendorId, productId)
					if (device == null) {
						result.error("not_found", "Dispositivo no encontrado", null)
						return@setMethodCallHandler
					}
					if (usbManager.hasPermission(device)) {
						result.success(true); return@setMethodCallHandler
					}
					val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
					val intent = PendingIntent.getBroadcast(this, 0, Intent(ACTION_USB_PERMISSION), piFlags)
					val receiver = object : BroadcastReceiver() {
						override fun onReceive(ctx: Context?, intent: Intent?) {
							if (intent?.action == ACTION_USB_PERMISSION) {
								unregisterReceiver(this)
								val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
								result.success(granted)
							}
						}
					}
					registerReceiver(receiver, IntentFilter(ACTION_USB_PERMISSION))
					usbManager.requestPermission(device, intent)
				}
				"connect" -> {
					val vendorId = call.argument<Int>("vendorId")
					val productId = call.argument<Int>("productId")
					if (vendorId == null || productId == null) {
						result.error("bad_args", "vendorId/productId requeridos", null)
						return@setMethodCallHandler
					}
					val ok = connectToDevice(vendorId, productId)
					if (ok) result.success(true) else result.error("connect_failed", "No se pudo abrir/claim la interfaz", null)
				}
				"printBytes" -> {
					val bytes = call.argument<ByteArray>("bytes")
					if (bytes == null) {
						result.error("bad_args", "bytes requeridos", null)
						return@setMethodCallHandler
					}
					val ok = bulkWrite(bytes)
					if (!ok) result.error("write_failed", "Falló bulkTransfer", null) else result.success(true)
				}
				"disconnect" -> {
					disconnect(); result.success(true)
				}
				else -> result.notImplemented()
			}
		}

		// Limpieza al desconectar
		registerReceiver(object : BroadcastReceiver() {
			override fun onReceive(context: Context?, intent: Intent?) {
				if (intent?.action == UsbManager.ACTION_USB_DEVICE_DETACHED) {
					val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
					if (device != null && device == currentDevice) disconnect()
				}
			}
		}, IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED))
	}

	private fun findDevice(vendorId: Int, productId: Int): UsbDevice? =
		usbManager.deviceList.values.firstOrNull { it.vendorId == vendorId && it.productId == productId }

	private fun connectToDevice(vendorId: Int, productId: Int): Boolean {
		val device = findDevice(vendorId, productId) ?: return false
		if (!usbManager.hasPermission(device)) return false
		// Buscar interfaz con endpoint bulk OUT
		for (i in 0 until device.interfaceCount) {
			val intf = device.getInterface(i)
			var outEp: UsbEndpoint? = null
			for (e in 0 until intf.endpointCount) {
				val ep = intf.getEndpoint(e)
				if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) { outEp = ep; break }
			}
			if (outEp != null) {
				val conn = usbManager.openDevice(device) ?: return false
				if (!conn.claimInterface(intf, true)) { conn.close(); continue }
				connection = conn; claimedInterface = intf; endpointOut = outEp; currentDevice = device
				return true
			}
		}
		return false
	}

	private fun bulkWrite(data: ByteArray): Boolean {
		val conn = connection ?: return false
		val out = endpointOut ?: return false
		var offset = 0
		while (offset < data.size) {
			val chunk = minOf(4096, data.size - offset)
			val sent = conn.bulkTransfer(out, data, offset, chunk, 3000)
			if (sent <= 0) return false
			offset += sent
		}
		return true
	}

	private fun disconnect() {
		try { connection?.releaseInterface(claimedInterface) } catch (_: Exception) {}
		try { connection?.close() } catch (_: Exception) {}
		connection = null; endpointOut = null; claimedInterface = null; currentDevice = null
	}
}
