import 'package:flutter/material.dart';
import '../../app_version.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Versión: ${AppBuildInfo.version}+${AppBuildInfo.buildNumber}',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          SizedBox(height: 12),
          Text('Pantallas y funcionalidades',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('• Inicio: acceso general a la app y estado de caja.'),
          Text('• Ticket: agrega ítems al carrito y cobra la venta.'),
          Text('• Recibos: listado de tickets emitidos y anulados.'),
          Text('• Caja: apertura, totales y cierre de caja.'),
          Text('• Historial de cajas: listado de cajas con resumen e impresión.'),
          Text('• Productos (ABM): alta, baja y modificación del catálogo; podés agregar imagen desde galería o cámara. La imagen se muestra en lista (avatar) y en grilla (tile cuadrado con nombre y chips de precio/stock).'),
          Text('• Configuraciones: tema y distribución de artículos.'),
          Text('• Prueba de impresora: vista previa/impresión de prueba.'),
      SizedBox(height: 16),
      Text('Exportar caja',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('• Desde el Resumen/Cierre de caja podés exportar los datos a un archivo JSON y compartirlo (por ejemplo, por WhatsApp, Drive o correo).'),
      Text('• El archivo incluye: metadatos, resumen, totales por método de pago, tickets (incluye anulados), ventas por producto y catálogo visible.'),
      Text('• Se guarda en /Android/data/<app>/files/exports/ y mantiene las últimas copias recientes.'),
          Text('Fórmulas y criterios',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('• Total Ventas (sistema): suma de tickets no anulados en la caja.'),
          Text('• Cierre de caja: Diferencia = (Efectivo declarado - Fondo Inicial) + Transferencias - Total Ventas (sistema).'),
          Text('• Ventas por producto: ordenadas de mayor a menor por cantidad. Formato: "Item x Cantidad = \$Monto".'),
        ],
      ),
    );
  }
}
