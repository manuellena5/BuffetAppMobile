import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_version.dart';
import '../state/app_mode.dart';
import '../widgets/tesoreria_scaffold.dart';
import '../widgets/responsive_container.dart';
import '../../home/home_page.dart';
import '../../home/main_menu_page.dart';
import '../../buffet/pages/buffet_home_page.dart';
import '../../buffet/pages/caja_open_page.dart';
import '../../buffet/pages/caja_page.dart';
import '../../buffet/pages/sales_list_page.dart';
import '../../buffet/pages/products_page.dart';
import '../../buffet/services/caja_service.dart';
import '../../eventos/pages/eventos_page.dart';
import '../../tesoreria/pages/movimientos_page.dart';
import 'settings_page.dart';
import 'printer_test_page.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final iconSize = (bodyStyle?.fontSize ?? 14.0) + 2;

    Widget sectionTitle(String text, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    Widget bullet(String text) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(text)),
          ],
        ),
      );
    }

    Widget tip(String text) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4, left: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: Colors.amber.shade900)),
            ),
          ],
        ),
      );
    }

    final modeState = context.watch<AppModeState>();
    final body = ResponsiveContainer(
      maxWidth: 800,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
            // ── Versión ──
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Versión: ${AppBuildInfo.version}+${AppBuildInfo.buildNumber}',
                style: const TextStyle(color: Colors.grey),
              ),
            ),

            // ── 1. Navegación ──
            sectionTitle('Navegación', Icons.menu),
            RichText(
              text: TextSpan(
                style: bodyStyle,
                children: [
                  const TextSpan(text: 'Usá el menú inferior para moverte entre las pantallas principales: '),
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
            bullet('Para vender, primero tenés que abrir una caja. Si intentás entrar a Ventas sin caja abierta, la app te avisa.'),
            bullet('Desde Ajustes podés configurar la impresora, el tema visual, buscar actualizaciones y acceder a esta ayuda.'),

            // ── 2. Eventos y Cajas ──
            sectionTitle('Eventos y Cajas', Icons.event),
            bullet('Desde Inicio accedés a "Eventos", donde se muestran los eventos del día.'),
            bullet('En la pestaña "Históricos" podés buscar eventos pasados filtrando por mes, fecha exacta o rango de fechas.'),
            bullet('Cada evento agrupa todas las cajas que se abrieron ese día para esa disciplina.'),
            bullet('El resumen del evento muestra el total de ventas, desglose por medio de pago (efectivo y transferencias), cantidad de tickets y la diferencia global.'),
            tip('Todo funciona sin conexión a internet. Los datos se guardan en el dispositivo.'),

            // ── 3. Detalle de Cajas cerradas ──
            sectionTitle('Detalle de una Caja', Icons.storefront),
            bullet('Tocá una caja dentro de un evento para ver su detalle completo.'),
            bullet('Vas a ver: ventas realizadas (con productos y cantidades), movimientos de caja (ingresos extra y retiros), y el resumen del cierre.'),
            bullet('El resumen del cierre muestra la conciliación por medio de pago: cuánto se esperaba vs. cuánto se declaró, y la diferencia.'),
            bullet('Las cajas cerradas son de solo lectura: no se pueden modificar ni eliminar.'),
            tip('Una caja cerrada ya no se puede reabrir. Revisá bien los montos antes de cerrar.'),

            // ── 4. Impresión ──
            sectionTitle('Impresión USB y PDF', Icons.print),
            bullet('La app intenta imprimir directo por USB (impresora térmica). Si no hay impresora conectada o falla, podés usar la previsualización PDF.'),
            bullet('Podés imprimir tickets de venta y el resumen de cierre de caja.'),
            bullet('En reportes de evento podés elegir entre "Detalle por caja" o "Sumarizado".'),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                'Configurar la impresora USB:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            bullet('Conectá la impresora por cable USB (OTG) y encendela.'),
            bullet('Si el dispositivo pide permiso, tocá "Permitir".'),
            bullet('Andá a Ajustes > Config. impresora, elegí el dispositivo y tocá "Conectar USB".'),
            bullet('Si no aparece, tocá "Refrescar" o desconectá y volvé a conectar el cable.'),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                'Ancho de papel:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            bullet('En Config. impresora podés elegir el ancho: 58 mm, 75 mm o 80 mm.'),
            bullet('Los tickets se adaptan automáticamente al ancho elegido.'),
            tip('Si el texto sale cortado, probá cambiar a un ancho menor o usá la previsualización PDF.'),

            // ── 5. Exportar a Excel ──
            sectionTitle('Exportar a Excel', Icons.table_chart),
            bullet('Cuando una caja está cerrada, podés exportar su detalle completo a un archivo Excel (.xlsx).'),
            bullet('El archivo incluye: datos del evento, ventas con productos, movimientos de caja y el resumen del cierre.'),
            bullet('Tocá el botón de exportar en el detalle de la caja cerrada y elegí dónde guardar o compartir el archivo.'),
            tip('Útil para llevar un registro en la computadora o enviar el detalle por mail/WhatsApp.'),

            // ── 6. Actualizaciones ──
            sectionTitle('Actualizaciones', Icons.system_update),
            bullet('Desde Ajustes > "Buscar actualizaciones" podés verificar si hay una nueva versión disponible.'),
            bullet('Si hay una versión nueva, la app te muestra los cambios y te permite descargarla e instalarla.'),
            bullet('La descarga se hace directamente en el dispositivo. Al terminar, se abre el instalador de Android.'),
            tip('Si el instalador no se abre, verificá que la app tenga permiso para instalar aplicaciones: Ajustes del dispositivo > Apps > BuffetApp > Instalar apps desconocidas.'),

            // ── 7. Fórmulas y criterios ──
            sectionTitle('Fórmulas y criterios', Icons.calculate),
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'Estas son las fórmulas que usa la app para calcular los totales y diferencias:',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
            _formulaCard(
              'Total Ventas',
              'Suma de todos los tickets no anulados de la caja.',
            ),
            _formulaCard(
              'Efectivo esperado',
              'Fondo Inicial + Ventas en Efectivo + Ingresos en Efectivo − Retiros en Efectivo.',
            ),
            _formulaCard(
              'Transferencias esperadas',
              'Ventas por Transferencia + Ingresos por Transferencia − Retiros por Transferencia.',
            ),
            _formulaCard(
              'Diferencia (por medio de pago)',
              'Monto declarado − Monto esperado.\n'
              'Si es 0 = todo cuadra (verde).\n'
              'Si es positivo = sobra dinero (azul).\n'
              'Si es negativo = falta dinero (rojo).',
            ),
            _formulaCard(
              'Diferencia Total',
              'Diferencia Efectivo + Diferencia Transferencias.',
            ),
            _formulaCard(
              'Resultado Económico',
              'Ventas en Efectivo + Ventas por Transferencia + Otros Ingresos − Retiros.',
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'BuffetApp v${AppBuildInfo.version} — Club Deportivo Murialdo',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );

    if (modeState.isBuffetMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ayuda')),
        drawer: _buildBuffetDrawer(context),
        body: body,
      );
    }

    return TesoreriaScaffold(
      title: 'Ayuda',
      currentRouteName: '/help',
      appBarColor: Colors.blue,
      body: body,
    );
  }

  Widget _buildBuffetDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(child: Text('BuffetApp')),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Inicio'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomePage()),
                (route) => false,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.point_of_sale),
            title: const Text('Ventas'),
            onTap: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              final caja = await CajaService().getCajaAbierta();
              if (caja == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Abrí una caja para vender')),
                );
                return;
              }
              nav.push(
                MaterialPageRoute(builder: (_) => const BuffetHomePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Tickets'),
            onTap: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              final caja = await CajaService().getCajaAbierta();
              if (caja == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Abrí una caja para ver los tickets')),
                );
                return;
              }
              nav.push(
                MaterialPageRoute(builder: (_) => const SalesListPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.store),
            title: const Text('Caja'),
            onTap: () async {
              final nav = Navigator.of(context);
              nav.pop();
              final caja = await CajaService().getCajaAbierta();
              if (caja == null) {
                nav.push(
                  MaterialPageRoute(builder: (_) => const CajaOpenPage()),
                );
              } else {
                nav.push(
                  MaterialPageRoute(builder: (_) => const CajaPage()),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Eventos / Listado Cajas'),
            onTap: () async {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(
                MaterialPageRoute(builder: (_) => const EventosPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Movimientos caja'),
            onTap: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              final caja = await CajaService().getCajaAbierta();
              if (caja == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Abrí una caja para ver movimientos')),
                );
                return;
              }
              nav.push(
                MaterialPageRoute(
                  builder: (_) => MovimientosPage(cajaId: caja['id'] as int),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Productos'),
            onTap: () async {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(
                MaterialPageRoute(builder: (_) => const ProductsPage()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.home_outlined, color: Colors.deepPurple),
            title: const Text('Menú Principal'),
            subtitle: const Text('Volver al selector de módulos'),
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainMenuPage()),
                (route) => false,
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Configuraciones'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.print),
            title: const Text('Config. impresora'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(
                MaterialPageRoute(builder: (_) => const PrinterTestPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Ayuda'),
            selected: true,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  static Widget _formulaCard(String title, String description) {
    return Card(
      margin: const EdgeInsets.only(left: 8, right: 0, bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
