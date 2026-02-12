import 'package:flutter/material.dart';
import '../../../app_version.dart';
import '../widgets/tesoreria_scaffold.dart';
import '../widgets/responsive_container.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final iconSize = (bodyStyle?.fontSize ?? 14.0);
    return TesoreriaScaffold(
      title: 'Ayuda',
      currentRouteName: '/help',
      appBarColor: Colors.blue,
      body: ResponsiveContainer(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Versión: ${AppBuildInfo.version}+${AppBuildInfo.buildNumber}',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Navegación (menú inferior)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: bodyStyle,
              children: [
                const TextSpan(text: '• El menú inferior permite ir a '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Icon(Icons.home, size: iconSize),
                ),
                const TextSpan(text: ' Inicio, '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Icon(Icons.point_of_sale, size: iconSize),
                ),
                const TextSpan(text: ' Ventas, '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Icon(Icons.store, size: iconSize),
                ),
                const TextSpan(text: ' Caja y '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Icon(Icons.settings, size: iconSize),
                ),
                const TextSpan(text: ' Ajustes.'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '• Si intentás entrar a Ventas sin caja abierta, la app te avisa para abrir una caja primero.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Eventos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '• En Inicio tenés el acceso a “Eventos”. Por defecto se muestran los eventos del día (offline desde SQLite).',
          ),
          const Text(
            '• En “Históricos” podés filtrar por mes actual, por fecha o por un rango de fechas.',
          ),
          const Text(
            '• “Refrescar desde Supabase” es manual (no automático) y sirve para bajar cajas/eventos de la nube si hay conexión.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Detalle del evento',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '• Muestra un resumen global (total ventas, efectivo, transferencias, tickets y diferencia) y el listado de cajas del evento.',
          ),
          const Text(
            '• Cada caja muestra total de ventas y totales por medio de pago (Ef/Tr).',
          ),
          const Text(
            '• Estados de sincronización: Pendiente / Parcial / OK / Error (solo se sincronizan/imprimen reportes de cajas cerradas).',
          ),
          const SizedBox(height: 16),
          const Text(
            'Sincronización (evento)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '• Botón “Sincronizar Evento”: envía las cajas cerradas pendientes y muestra progreso en vivo.',
          ),
          const Text(
            '• Si ya no hay pendientes, avisa y no vuelve a re-enviar.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Impresión USB y PDF',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(style: bodyStyle, children: [
              const TextSpan(
                  text:
                      '• La app intenta imprimir por USB (ESC/POS). Si falla, podés usar '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Icon(Icons.picture_as_pdf, size: iconSize),
              ),
              const TextSpan(text: ' previsualización PDF.'),
            ]),
          ),
          const Text(
            '• En reportes de evento podés elegir “Detalle por caja” o “Sumarizado”.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Ancho de papel',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '• Podés elegir el ancho de papel en Config. impresora: 58 mm, 75 mm o 80 mm.',
          ),
          const Text(
            '• Los tickets y reportes se adaptan automáticamente al ancho seleccionado (USB y PDF).',
          ),
          const Text(
            '• Si ves texto cortado, probá reducir el ancho o usar previsualización PDF.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Conexión USB (pasos y solución de problemas)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('• Conectá la impresora por USB (OTG) y encendela.'),
          const Text('• Si Android pide permiso, tocá “Permitir”.'),
          const Text(
            '• En “Config. impresora”, elegí el dispositivo y tocá “Conectar USB”; luego “Refrescar” si no aparece.',
          ),
          const Text(
              '• Probá desconectar y volver a conectar el cable USB/OTG.'),
          const Text('• Reiniciá la app si persiste el problema.'),
          const Text(
            '• Verificá permisos en Android: Ajustes > Apps > BuffetApp > Permisos > USB.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Fórmulas y criterios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '• Total Ventas (sistema): suma de tickets no anulados en la caja.',
          ),
          const Text(
            '• Cierre de caja: Diferencia = ((Efectivo declarado - Fondo Inicial - Ingresos + Retiros) + Transferencias) - Total Ventas (sistema).',
          ),
          ],
        ),
      ),
    );
  }
}
