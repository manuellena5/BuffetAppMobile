# Instrucciones para agentes – BuffetApp Mobile (Flutter Android POS)

## Estilo de respuesta
- Responder SIEMPRE en español, con pasos accionables y ejemplos mínimos.
- Antes de crear un archivo nuevo, PREGUNTAR y verificar si ya existe solución similar.
- Si algo no está claro, cerrar con preguntas numeradas (máx. 5).

## Contexto General
Aplicación Flutter (Android principal, multiplataforma habilitada) tipo Punto de Venta (POS) de buffet. Arquitectura offline‑first utilizando SQLite vía `sqflite`. Sincronización SOLO mediante Supabase usando una cola local (`sync_outbox`). Impresión: USB + previsualización PDF como fallback. No mantener referencias al antiguo backoffice Python.

## Estructura del Código (carpeta `android_mirror/lib`)
- `main.dart`: arranque, inicialización de fecha local, `SupaSyncService.init()`, reconexión impresora (`UsbPrinterService`), determina `HomePage` vs `PosMainPage` según caja abierta.
- `data/dao/db.dart`: clase `AppDatabase`. Creación, migración, índices, semillas, logging de errores y helpers de columnas.
- `services/`: lógica de negocio (ej. `caja_service.dart`, sincronización, impresora). Evitar lógica pesada en Widgets.
- `ui/pages/`: pantallas funcionales. Mantener convención `<nombre>_page.dart`.
- `ui/state/`: `ChangeNotifier` y modelos de estado (ej. `CartModel`, `AppSettings`).
- `domain/`: entidades y lógica pura (si se añaden más modelos, mantener allí).
- `env/`: configuración/variables de entorno si se requieren.
- `app_version.dart`: control de versión mostrado en UI / soporte.

## Pantallas Principales
1. Inicio / Navegación:
    - `home_page.dart`: landing cuando NO hay caja abierta (acciones: abrir caja, ajustes).
2. Caja:
    - `caja_open_page.dart`: apertura de caja (disciplina, fondo inicial, usuario/cajero).
    - `caja_page.dart`: vista central de la caja abierta (totales, impresión cierre, conteo efectivo final, estados).
    - `caja_list_page.dart`: listado histórico de cajas.
    - `caja_tickets_page.dart`: tickets vinculados a la caja (impresión / anulación).
3. POS / Ventas:
    - `pos_main_page.dart`: hub principal si hay caja abierta (accesos rápidos).
    - `venta_page.dart`: proceso de venta (selección productos + método pago).
    - `cart_page.dart`: detalle y edición del carrito antes de confirmar.
    - `payment_method_page.dart`: selección de método de pago / confirmación.
4. Productos / Catálogo:
    - `products_page.dart`: ABM de productos (visibilidad, stock, precio, color, imagen).
    - `product_reorder_page.dart`: reorden visual (`orden_visual`).
5. Movimientos:
    - `movimientos_page.dart`: ingresos / retiros de efectivo (caja_movimiento).
6. Ventas / Historial:
    - `sales_list_page.dart`: listado de ventas (filtros, estado, método de pago).
    - `sale_detail_page.dart`: detalle venta (items, tickets, anulación).
7. Utilidades / Configuración:
    - `settings_page.dart`: tema, impresora, alias dispositivo.
    - `printer_test_page.dart`: pruebas de impresión / PDF.
    - `error_logs_page.dart`: visualización de errores (`app_error_log`).
    - `help_page.dart`: ayuda y versión.

## Base de Datos (SQLite) – Tablas en `AppDatabase`
Creación (versión 3) e índices:
- `metodos_pago(id PK, descripcion, created_ts, updated_ts)` semillas: Efectivo(1), Transferencia(2).
- `Categoria_Producto(id PK, descripcion, created_ts, updated_ts)` semillas: Comida(1), Bebidas(2).
- `products(id PK, codigo_producto UNIQUE, nombre, precio_compra, precio_venta, stock_actual, stock_minimo, orden_visual, categoria_id FK, visible, color, imagen, created_ts, updated_ts)` índice `idx_products_visible_cat_order`.
- `caja_diaria(id PK AUTOINC, codigo_caja UNIQUE, disciplina, fecha, usuario_apertura, cajero_apertura, visible, hora_apertura, apertura_dt, fondo_inicial, conteo_efectivo_final, estado, ingresos, retiros, diferencia, total_tickets, tickets_anulados, entradas, hora_cierre, cierre_dt, usuario_cierre, cajero_cierre, descripcion_evento, observaciones_apertura, obs_cierre, created_ts, updated_ts)` índice `idx_caja_estado`.
- `ventas(id PK AUTOINC, uuid UNIQUE, fecha_hora, total_venta, status, activo, metodo_pago_id FK, caja_id FK, created_ts, updated_ts)` índices: fecha_hora, caja_id, metodo_pago_id, activo.
- `venta_items(id PK AUTOINC, venta_id FK CASCADE, producto_id FK, cantidad, precio_unitario, subtotal, created_ts, updated_ts)` índice venta_id.
- `tickets(id PK AUTOINC, venta_id FK, categoria_id FK, producto_id FK, fecha_hora, status, total_ticket, identificador_ticket, created_ts, updated_ts)` índices: venta_id, categoria_id, status.
- `caja_movimiento(id PK AUTOINC, caja_id FK, tipo ('INGRESO'|'RETIRO'), monto>0, observacion, created_ts, updated_ts)` índices: caja_id, (caja_id,tipo).
- `punto_venta(codigo PK, nombre, created_ts, updated_ts)` semillas Caj01..Caj03.
- `disciplinas(id PK AUTOINC, nombre UNIQUE, created_ts, updated_ts)` semillas varias.
- `sync_outbox(id PK AUTOINC, tipo, ref, payload JSON, estado('pending'|'sent'|'error'), reintentos, last_error, created_ts)` índice único (tipo,ref).
- `sync_error_log(id PK AUTOINC, scope, message, payload, created_ts)`.
- `app_error_log(id PK AUTOINC, scope, message, stacktrace, payload, created_ts)`.

Migraciones (`onUpgrade`):
- Reasegura tablas con `IF NOT EXISTS`.
- Añade columnas nuevas idempotentes (`ensureCajaDiariaColumn`).
- Añade `orden_visual` si falta en `products` y la inicializa.
- Regenera índices ausentes.

Helpers:
- `AppDatabase.instance()` singleton.
- `AppDatabase.logLocalError(scope, error, stackTrace?, payload?)` evita romper flujo.
- `AppDatabase.ensureCajaDiariaColumn(name, ddl)` para refuerzos post-migración.

## Sincronización (Supabase Únicamente)
- Cada evento (venta, cierre de caja, anulación) se registra en `sync_outbox` con `tipo` y `ref` (ej. venta: ref=uuid).
- Servicio de sync procesa pendientes: cambia `estado` a `sent` o `error`; incrementa `reintentos`; guarda `last_error`.
- No se usan archivos JSON locales para sync en esta versión (retirar flujos previos si quedan referencias).
- Evitar enviar duplicados: índice único (tipo, ref) actúa como guardia.
- Estrategia de reintentos exponencial (si se implementa): aumentar `reintentos` y backoff; documentar si se añade.

## Impresión
- Impresión térmica primaria vía USB (autoconexión en inicio si se guardó).
- Fallback: generar PDF (previsualización) y permitir guardar / compartir.
- Probar siempre en `printer_test_page.dart` antes de integrar nuevas plantillas.
- Manejar errores con `AppDatabase.logLocalError(scope: 'caja_page.usb_print', ...)`.

## Flujos de Caja y Ventas
1. Apertura de Caja:
    - Completar disciplina, fondo inicial, usuario/cajero.
    - Insert `caja_diaria` estado 'ABIERTA'.
2. Venta:
    - Seleccionar productos -> `CartModel`.
    - Confirmar método de pago -> insert `ventas` + `venta_items` (subtotal calculado). Generar opcional `tickets`.
    - Encolar en `sync_outbox` (`tipo='venta'`).
3. Movimientos:
    - Registrar ingresos / retiros (`caja_movimiento`).
    - Recalcular totales de caja desde consultas (no triggers). Cache sólo si necesario.
4. Cierre de Caja:
    - Actualizar `caja_diaria` estado 'CERRADA', guardar `conteo_efectivo_final`, observaciones.
    - Encolar resumen (`tipo='cierre_caja'`).

## Anulación de Tickets y Ventas
- Anulación de venta: set `activo=0` en `ventas`, NO borrar `venta_items`. Registrar outbox (`tipo='venta_anulada'`). Ignorar ventas inactivas en totales.
- Anulación de ticket: actualizar `status='Anulado'` en `tickets` (mantener fila para auditoría). Encolar `tipo='ticket_anulado'`.
- Ajustar pantallas (`sales_list_page`, `caja_tickets_page`) para mostrar distinción visual (color rojo / icono). No eliminar filas físicas.

## Testing
- Ejecutar tests después de cambios significativos en: flujo de venta, cierre de caja, cálculo de totales, sincronización.
- Ubicación de tests: carpeta `test/` (ejemplos existentes: `flujo_venta_caja_test.dart`, etc.).
- Crear test nuevo: preguntar antes si ya existe uno similar. Reutilizar helpers comunes.
- Comandos básicos:
  ```powershell
  flutter test
  ```
- Para un test específico:
  ```powershell
  flutter test test/flujo_venta_caja_test.dart
  ```
- Política: no mergear PR sin tests verdes si modifica lógica critica (ventas, caja, sync).

## Convenciones de Código
- Nombres de archivos: snake_case; pantallas terminan en `_page.dart`.
- Evitar lógica de negocio en Widgets; mover a `services/`.
- Usar `ChangeNotifier` para estado interactivo (carrito, settings); evitar proliferación no justificada.
- Columnas DB en snake_case; mantener compatibilidad en migraciones.
- Reintentos de sync: centralizar en un único servicio (evitar duplicado en UI).
- Logging: `scope` granular (`venta.crear`, `caja.cerrar`, `sync.envio`, etc.).
- No crear nuevas tablas sin actualizar `onCreate` y `onUpgrade` simultáneamente.

## Extender la Base de Datos
1. Añadir tabla en batch `onCreate`.
2. Repetir con `CREATE TABLE IF NOT EXISTS` en `onUpgrade`.
3. Índices sólo si hay consultas frecuentes por esas columnas.
4. Añadir seeds mínimas si requiere FK inicial.
5. Para nueva columna en tabla existente: `ALTER TABLE` en `onUpgrade` + helper `ensure<Table>Column` si se necesita en runtime.
6. Verificar no romper lecturas previas (consultas SELECT * pueden tolerar nuevas columnas, pero JSON serializadores deben adaptarse).

## Checklist antes de Commit
- Migraciones y creación sincronizadas.
- Índices necesarios presentes (no redundantes).
- Errores críticos atrapados con `logLocalError`.
- Ventas/tickets anulados excluidos correctamente de totales.
- Tests relevantes ejecutados y verdes.
- Sin referencias al antiguo backoffice Python.
- Nuevos tipos de outbox usan nombres consistentes (`venta`, `venta_anulada`, `ticket_anulado`, `cierre_caja`).
- Registrar cambios de versión en `CHANGELOG.md` siguiendo orden cronológico y formato consistente (fecha, versión, Added/Changed/Fixed).

## Preguntar Antes de:
- Crear nueva pantalla sin reutilizar componentes existentes.
- Añadir paquete externo (evaluar si ya está en `pubspec.yaml`).
- Introducir nueva tabla / columna.
- Agregar mecanismo alternativo de sync.

## Ejemplo Rápido: Registrar Venta
```dart
final db = await AppDatabase.instance();
final ventaId = await db.insert('ventas', {
  'uuid': uuid, 'fecha_hora': DateTime.now().toIso8601String(),
  'total_venta': total, 'metodo_pago_id': metodoPagoId, 'caja_id': cajaId
});
for (final item in items) {
  await db.insert('venta_items', {
     'venta_id': ventaId,
     'producto_id': item.productoId,
     'cantidad': item.cantidad,
     'precio_unitario': item.precioUnitario,
     'subtotal': item.subtotal,
  });
}
await db.insert('sync_outbox', {
  'tipo': 'venta', 'ref': uuid, 'payload': jsonEncode({'venta_id': ventaId})
});
```

## Próximas Extensiones Sugeridas (Opcional)
- Auditoría de stock (tabla `stock_movimiento`).
- Estado de sincronización en UI (badge si `sync_outbox.estado='error'`).
- Backoff exponencial y métricas de performance.

## Última Verificación
Si detectas todavía alguna referencia obsoleta o flujo no documentado, registrarla en `error_logs_page` y actualizar este archivo.

¿Necesitas que genere ahora tests adicionales, o algún ajuste más en la sección de anulación? Indica cambios y los aplico.

