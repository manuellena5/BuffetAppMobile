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
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Versión: ${AppBuildInfo.version}+${AppBuildInfo.buildNumber}',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Sincronización',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('• La sincronización es manual desde el Resumen de caja (ícono de sync en AppBar).'),
          const Text('• Al finalizar se muestra un diálogo con totales de Cajas/Items OK y los últimos errores (si hubo).'),
      const Text('• Durante la sincronización se muestra una barra de progreso (procesados/total y etapa) y el botón queda bloqueado.'),
          const Text('• Si falta alguna columna en el servidor, la app reintenta sin esas columnas y registra el detalle del error.'),
          const Text('• Los errores se guardan en una tabla local y se suben a la tabla de sincronización (sync_error_log) cuando hay conectividad.'),
          const SizedBox(height: 12),
          const Text('Pantallas y funcionalidades',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('• Inicio: acceso general a la app, estado de impresora USB (verde/rojo) y doble “Atrás” para salir. Sin menú lateral.'),
          const Text('• Ventas (Ticket): agrega ítems al carrito, botón de limpiar carrito, estado USB en la barra superior y precios más grandes.'),
          const Text('• Recibos: listado de tickets emitidos y anulados con reimpresión.'),
          const Text('• Caja: apertura, totales y cierre de caja. En Resumen y ticket se muestra “Entradas vendidas” (0 si está vacío).'),
          const Text('• Historial de cajas: listado de cajas con resumen, impresión (USB primero) y exportación.'),
          const Text('• Productos (ABM): alta, baja y modificación del catálogo; podés agregar imagen desde galería o cámara. La imagen se muestra en lista (avatar) y en grilla (tile cuadrado con nombre y chips de precio/stock).'),
          const Text('• Config. impresora: conectar por USB (OTG), refrescar lista, pruebas de impresión y preferencia “Imprimir logo en cierre (USB)”.'),

          const SizedBox(height: 16),
      const Text('Iconos en la pantalla de ventas',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('• Ícono de ticket (arriba a la izquierda): abre el carrito. A la derecha se muestra el contador de ítems agregados.'),
      const Text('• Ícono de impresora: indica el estado de la conexión USB. Verde: conectada. Rojo: desconectada. Tocá para ir a “Config. impresora”.'),
      const Text('• Ícono de “Limpiar carrito” (tachito con carrito): borra todos los ítems del carrito (pide confirmación).'),
      const Text('• Botón “COBRAR”: inicia la selección de medio de pago y registra la venta.'),
      const Text('• Ícono de tienda junto al código de caja: muestra la caja abierta y el total acumulado.'),

      const SizedBox(height: 16),
          const Text('Impresión USB y PDF',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('• La app intenta imprimir por USB (ESC/POS) por defecto. Si falla o no hay conexión, se ofrece previsualización PDF como alternativa.'),
          const Text('• El cierre de caja puede incluir el logo en el encabezado ESC/POS. Podés habilitar/deshabilitarlo en Config. impresora.'),
          const Text('• En Resumen de caja, si no hay USB o da error, aparece un diálogo para ir a Config. impresora o abrir la previsualización PDF.'),

          const SizedBox(height: 16),
          const Text('Conexión USB (pasos y solución de problemas)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('• Conectá la impresora por USB (OTG) y encendela.'),
          const Text('• Si Android pide permiso, tocá “Permitir”.'),
          const Text('• En “Config. impresora”, elegí el dispositivo y tocá “Conectar USB”; luego “Refrescar” si no aparece.'),
          const Text('• Probá desconectar y volver a conectar el cable USB/OTG.'),
          const Text('• Reiniciá la app si persiste el problema.'),
          const Text('• Verificá permisos en Android: Ajustes > Apps > BuffetApp > Permisos > USB.'),

          const SizedBox(height: 16),
          const Text('Exportar caja',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('• Desde el Resumen/Cierre de caja podés exportar los datos a un archivo JSON y compartirlo (WhatsApp, Drive o correo).'),
          const Text('• Incluye: metadatos, resumen, totales por medio de pago, tickets (incluye anulados), ventas por producto y catálogo visible.'),
          const Text('• Se guarda en /Android/data/<app>/files/exports/ y mantiene las últimas copias recientes.'),

          const SizedBox(height: 16),
          const Text('Fórmulas y criterios',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('• Total Ventas (sistema): suma de tickets no anulados en la caja.'),
          const Text('• Cierre de caja: Diferencia = (Efectivo declarado - Fondo Inicial) + Transferencias - Total Ventas (sistema).'),
          const Text('• Ventas por producto: ordenadas de mayor a menor por cantidad. Formato: "Item x Cantidad = \$Monto".'),
        ],
      ),
    );
  }
}
