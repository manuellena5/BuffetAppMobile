# Changelog

## Unreleased
- (sin cambios)

## 1.2.1+13 — 2025-12-30
- Eventos: nueva pantalla de Eventos (del día + históricos) 100% offline desde SQLite.
- Eventos: históricos con filtro (mes actual / fecha / rango) y botón manual “Refrescar desde Supabase” para bajar cajas de la nube.
- Evento (detalle): resumen global + listado de cajas con estado de sincronización y totales.
- Evento (detalle): tarjetas de caja muestran total de ventas + totales por medio de pago (Efectivo / Transferencia).
- Evento (sync): botón “Sincronizar Evento” con precheck (si no hay pendientes no vuelve a enviar) y progreso en vivo.
- Reportes: PDF sumarizado del evento muestra PV (en Movimientos Globales) en lugar de código de caja.
- Navegación: menú inferior (Inicio / Ventas / Caja / Ajustes) para acceso rápido.
- Sincronización: validación previa contra Supabase al re-sincronizar una caja ya subida; si hay diferencias, se pide confirmación antes de sobreescribir.
- Sincronización: re-encolado explícito de la caja para permitir reenvío aunque el outbox esté en estado "done".
- Supabase: `fecha_apertura`/`fecha_cierre` ahora se envían en formato timestamp local (sin conversión a UTC) para coincidir con columnas tipo `timestamp`.
- Comparación: diferencias de `fecha_apertura`/`fecha_cierre` se evalúan a nivel de minutos (YYYY-MM-DD HH:MM).
- Caja: fix para que `cajero_apertura` se tome desde DB local y se incluya en el payload sincronizado.
- Se quitaron las pantallas de Reportes y Listado de cajas. Se maneja a nivel Eventos la información ahora. 

## 1.2.0+12 — 2025-11-21
- Reportes: nueva pantalla con KPIs (total ventas, ticket promedio, cantidad ventas, entradas, tickets emitidos/anulados) y gráfico de barras por disciplina con agregaciones Día/Mes/Año.
- Reportes: manejo de estado vacío (sin cajas) mostrando calendario y KPIs en cero; placeholder "Sin datos disponibles".
- Reportes: eliminación del KPI "Conversion Personas %" de la UI (se mantiene cálculo interno para posibles usos futuros).
- Mantenimiento: botón rojo para purgar TODAS las cajas, ventas, tickets y movimientos asociados (con countdown de 5s, mensaje de cantidad a borrar y feedback éxito/fallo); preserva productos.
- Backup: botón para crear archivo físico de la base de datos y compartirlo (.db con timestamp).
- Seguridad: logs de error en purga/backup si ocurre alguna excepción.
- Tests: añadido test `reportes_page_empty_test.dart` asegurando render sin datos; fallback de inicialización limitado sólo a entorno de test (no producción).
- Versionado: bump a 1.2.0+12.

## 1.1.0+11 — 2025-11-13
- Cajas: nueva columna `visible` (solo Android). Historial con toggle “Mostrar ocultas”, filas ocultas en gris y etiqueta “(Oculta)”. En detalle de caja, menú para Ocultar/Mostrar con confirmación y validación para NO permitir ocultar una caja ABIERTA.
- POS (ventas): el botón/gesto Atrás ahora redirige siempre a Inicio.
- Impresión de prueba: ticket de muestra sin insertar en DB (no consume IDs autoincrementales).
- Cierre de caja: flujo USB-first. Primero intenta imprimir por USB (muestra aviso si no hay conexión o si falla). Luego guarda automáticamente el PDF y abre la previsualización. Se elimina el modal de compartir JSON.
- UI de caja: se quitó un encabezado que recortaba contenido en el detalle/resumen.
- Se agregó precio de compra en pantalla de productos y calculo de % de ganancia teniendo el cuenta el precio de compra.
- Versionado: bump a 1.1.0+11.

## 1.0.7+8 — 2025-10-31
- Sincronización: barra de progreso en vivo durante el envío (procesados/total y etapa), y bloqueo del botón hasta finalizar.
- Envío por lotes: la sync recorre la cola en bloques hasta vaciarla, actualizando el progreso después de cada lote (cajas, items, errores).
- Resumen de caja: muestra una barra determinística mientras se sincroniza y conserva el diálogo de resultados al finalizar.
- Versionado: bump a 1.0.7+8.

## 1.0.9+10 — 2025-11-07
- Sincronización: indicador refinado basado en pendientes reales (caja + tickets) y nueva línea "Sincronizados: Caja n/m · Tickets n/m".
- Lógica de red: manejo de errores transitorios (DNS, SocketException) sin marcar filas como errores permanentes; reintento diferido.
- Items: pospone envío si la caja aún no está confirmada en servidor; fallback de upsert mínimo si falta la caja pero está marcada como done local.
- UI Tickets: encabezado compactado ("Tk") para evitar truncamiento y reducción de tamaños tipográficos en detalle para mejorar ajuste.
- Ayuda: pendiente de actualizar sección sincronización con nuevo indicador (ver siguiente versión si se agrega más texto).
- Versionado: bump a 1.0.9+10.

## 1.0.8+9 — 2025-11-01
- Impresora: nueva preferencia de “Ancho de papel” (58/75/80 mm).
- Tickets (USB/PDF): se adaptan automáticamente al ancho 75 mm (y 58/80 mm). En ESC/POS se ajustan caracteres por línea e imágenes (58→384px, 75→512px, 80→576px). En PDF se ajusta el formato de página por mm.
- Ayuda: se documenta la preferencia y recomendaciones si el texto se corta.
- APK de release actualizado.

Todas las notas de cambios para BuffetApp (Android espejo).

## 1.0.6+7 — 2025-10-31
- Sincronización manual: ahora el resumen post-sync detalla cantidades OK/Fail y muestra el último error si lo hubo.
- caja_items: se completan campos de ticket (fecha, fecha_hora, producto_nombre, categoria, cantidad, precio_unitario, total, total_ticket, metodo_pago, metodo_pago_id) y se incluye status (también para anulados). Se resuelve caja_uuid automáticamente por codigo_caja.
- Manejo de esquemas: si el servidor no reconoce alguna columna (PGRST204), se reintenta sin columnas de conveniencia y se loguea el detalle del error.
- Errores: se registran en tabla local y se encolan para subirse a sync_error_log en el backend.
- Cierre/Resumen: se muestra “Entradas vendidas” (0 si no hay valor) en la pantalla y en el ticket (PDF y ESC/POS).
- Versionado: bump a 1.0.6+7.

## 1.0.5+6 — 2025-10-28
- Tickets de venta: se quita el logo/escudo y se restaura el formato compacto. Encabezado ahora muestra “Buffet - C.D.M”. Descripción e importe vuelven a tamaños grandes.
- Cierre de caja: se mantiene el logo en encabezado (PDF y ESC/POS).
- Indicador de impresora en POS: ícono de impresora verde/rojo en el encabezado bajo el AppBar.
- Versionado: bump a 1.0.5+6.

## 1.0.4+5 — 2025-10-28
- Home: se removió el menú lateral y el ícono de impresora del AppBar. Ahora requiere doble pulsación de “Atrás” para salir (muestra Snackbar la primera vez). Estado de impresora USB en pie de página.
- Ventas (POS): indicador de impresora USB en AppBar (verde/rojo) con acceso rápido a Config. impresora; botón para limpiar carrito con confirmación; precios más grandes en lista y grilla.
- Config. impresora: renombrada (antes “Prueba de impresora”), ayuda paso a paso para conectar USB y nueva preferencia “Imprimir logo en cierre (USB)”.
- Impresión: el cierre de caja en ESC/POS incluye logo pequeño (raster) si la preferencia está activada; el PDF de cierre ya incluía el logo.
- Resumen de caja: título corto (“Caja”). Si no hay USB o falla la impresión, se muestra un diálogo con opciones para ir a Config. impresora o abrir Previsualización PDF.
- Cierre de caja (pantalla): en el encabezado se muestra “Cajero” (apertura) en lugar de “Usuario”.
- Ayuda: se actualizó con nuevas secciones (estado de USB, doble “Atrás”, impresión USB-first con fallback PDF, solución de problemas USB).
- Versionado: bump a 1.0.4+5.

## 1.0.3+4 — 2025-10-27
- Impresora USB por defecto: validación de conexión en cobro, reimpresión y tests. Si no hay conexión o falla, se muestra mensaje y los tickets quedan "No Impreso" (sin abrir PDF).
- Reimpresión en Recibos: imprime por USB y muestra estado.
- Cierre: se agrega Estado de caja al ticket (PDF y ESC/POS) y se agranda el TOTAL (más destacado).
- Resumen de caja (pantalla): se muestra "Descripción del evento" y se agrega botón Exportar a PDF.
- POS: encabezado superior sin la palabra "Caja" (muestra código y total).
- Base de datos: nuevas columnas cajero_apertura y cajero_cierre; migración que inicializa cajero_apertura desde usuario_apertura o "admin".
- Apertura/Cierre: pedir "Cajero apertura" y "Cajero de cierre" (por defecto "admin"). Ticket de cierre muestra cajeros.
- Versión app actualizada a 1.0.3+4.

## 1.0.2+3 — 2025-10-17
- Inputs: se quitó el formateo de moneda mientras se escribe en Apertura (fondo), Cierre (efectivo/transferencias) y ABM de Productos (precio). Se valida con parser laxo (punto/coma). La UI de lectura mantiene formato.
- Cierre (diálogo): renombrado a “Efectivo en caja” y previsualización de fórmula corregida.
- PDF de cierre: se elimina “Ingresos” y “Retiros”, se muestra Fondo inicial, Diferencia y se agregan Observaciones de apertura y cierre.
- Resumen de caja (app): se muestran Obs. apertura, Obs. cierre y Diferencia.
- Post-apertura: modal para elegir ir a Cargar stock (Productos) o a Ventas.
- Ventas: alerta modal si existen productos con stock bajo (<=5 unidades).
- Versionado: bump a 1.0.2+3.

## 1.0.1+2 — 2025-10-17
- Recibos: mostrar descripción del producto/categoría.
- Detalle de recibo: robustez cuando el ticket no tiene producto asociado (usa categoría), y reposición de stock sólo si corresponde.
- POS (grilla): chips superpuestos de precio (arriba-derecha) y stock (arriba-izquierda, oculto si 999).
- Ajustes: selector de tema actualizado (SegmentedButton); textos mejorados.
- Limpieza de warnings del analizador (child last, radios deprecados, guards tras await).
- Export: metadato de versión sincronizado con build (1.0.1+2).
- Versión app: bump a 1.0.1+2.

## 1.0.0+1 — 2025-10-XX
- Versión inicial: ventas offline, tickets por ítem, caja diaria, catálogo con imágenes, impresión de prueba, exportación JSON, tema sistema/claro/oscuro.
