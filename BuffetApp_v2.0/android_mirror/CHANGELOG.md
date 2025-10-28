# Changelog

Todas las notas de cambios para BuffetApp (Android espejo).

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
