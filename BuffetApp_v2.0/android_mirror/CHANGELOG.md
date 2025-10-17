# Changelog

Todas las notas de cambios para BuffetApp (Android espejo).

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
