# Instrucciones para agentes – BuffetApp Mobile (Flutter Android POS)

## Estilo de respuesta
- Responder SIEMPRE en español, con pasos accionables y ejemplos mínimos.
- Antes de crear un archivo nuevo, PREGUNTAR y verificar si ya existe solución similar.
- Si algo no está claro, cerrar con preguntas numeradas (máx. 5).

## Contexto General (actualizado)
Aplicación Flutter (Android principal) para gestión de cajas en eventos deportivos, con múltiples dispositivos trabajando offline y sincronizando manualmente a Supabase al cerrar la caja. Arquitectura offline‑first usando SQLite vía `sqflite`. Impresión: USB + previsualización PDF como fallback.

Principios NO negociables:
- La app ya funciona y NO debe romperse el flujo actual.
- NO forzar conexión a internet (ni asumir conexión permanente).
- NO agregar autenticación/login/roles.
- La DB local es la fuente primaria mientras la caja está ABIERTA.
- Una caja CERRADA es solo lectura: NO se edita, NO se elimina.

## Estructura del Código (carpeta `lib`)
- `main.dart`: arranque, inicialización de fecha local, `SupaSyncService.init()`, reconexión impresora (`UsbPrinterService`), determina `HomePage` vs `PosMainPage` según caja abierta.
- `data/dao/db.dart`: clase `AppDatabase`. Creación/migración, índices, seeds, logging de errores y helpers de columnas.
- `services/`: lógica de negocio (caja, ventas, sync, impresora). Evitar lógica pesada en Widgets.
- `ui/pages/`: pantallas. Convención `<nombre>_page.dart`.
- `ui/state/`: `ChangeNotifier` y modelos de estado (ej. `CartModel`, `AppSettings`).
- `domain/`: entidades y lógica pura.

## Conceptos vNext (a respetar en cambios)

### 1) Dispositivo / Punto de Venta (identidad de instalación)
- Cada instalación debe tener `dispositivo_id` (UUID v4) persistente.
- Se genera una sola vez y se guarda en storage local persistente.
- Si se desinstala y reinstala, se genera uno nuevo.
- El usuario define `alias_caja` (ej. Caja 01) y queda fijo para esa instalación.
- TODO registro sincronizado a Supabase debe incluir `dispositivo_id` y debe llevar `alias_caja` para conciliación.
- NO acoplar lógica al hardware: el id identifica instalación, no el teléfono.

### 2) Evento (nuevo eje)
- Evento = `disciplina_id` + `fecha_evento`.
- `disciplina_id` es estable en todos los dispositivos (disciplinas precargadas, sin ABM).
- `fecha_evento` se toma de la FECHA de apertura (año-mes-día, sin hora/minutos).

#### evento_id determinístico
- `evento_id` debe ser determinístico y igual en todos los dispositivos.
- Preferir UUID v5 con namespace fijo, derivado de `disciplina_id` y `fecha_evento`.
- Si algo no está implementado aún, preguntar antes de elegir hash/uuid.

### 3) Caja (ajuste conceptual)
- Cada dispositivo abre su propia caja dentro de un evento.
- La caja debe guardar: `evento_id`, `disciplina_id`, `dispositivo_id`, `alias_caja`.
- Estado operativo de caja: `ABIERTA` | `CERRADA` (NO mezclar con sync).

#### Estado de sincronización (nuevo)
- Agregar columna separada en `caja_diaria` para el estado de sincronización, por ejemplo `sync_estado`:
    - `PENDIENTE` | `SINCRONIZADA` | `ERROR`
- Reglas:
    - Si la caja está `ABIERTA`, su `sync_estado` debe ser `PENDIENTE`.
    - Solo una caja `CERRADA` puede pasar a `SINCRONIZADA`.
    - Si falla la sincronización, `sync_estado` debe quedar/volver a `ERROR` y NO marcarse como sincronizada.
- Backfill:
    - Cajas existentes: completar `disciplina_id` + `evento_id`.
    - `sync_estado` debe inicializarse (por defecto `PENDIENTE`), salvo que haya una forma explícita de deducirlo sin ambigüedad.

## Pantallas (existentes + nuevas)

### Pantallas existentes (NO romper)
- Abrir caja, registrar ventas/movimientos, cerrar caja, imprimir/mostrar resumen.

### Pantallas nuevas
1) Eventos
    - Lista por defecto: eventos del día.
    - Debe funcionar 100% offline leyendo de SQLite.
    - Acceso secundario: eventos históricos.
    - Opción manual: “Refrescar desde Supabase” (NO automática).

2) Detalle de Evento
    - Muestra todas las cajas del evento (de todos los dispositivos).
    - Por caja: `alias_caja`, estado (operativo + sync), totales.
    - Permite ver detalle de una caja.
    - NO permite modificar cajas de otros dispositivos.

Reglas estrictas:
- NO mezclar datos entre eventos.
- NO modificar datos de cajas cerradas.
- NO asumir conectividad.

## Base de Datos (SQLite) – Tablas en `AppDatabase`
Mantener el esquema existente y extenderlo de forma idempotente en migraciones.

Tablas principales (existentes):
- `metodos_pago`, `Categoria_Producto`, `products`, `disciplinas`, `punto_venta`
- `caja_diaria`, `ventas`, `venta_items`, `tickets`, `caja_movimiento`
- `sync_outbox`, `sync_error_log`, `app_error_log`

Nuevas columnas (mínimo requerido) en `caja_diaria`:
- `dispositivo_id` (UUID en texto si SQLite)
- `alias_caja` (texto)
- `disciplina_id` (int)
- `evento_id` (texto/UUID)
- `sync_estado` (texto: `PENDIENTE|SINCRONIZADA|ERROR`)
- Opcional recomendado: `sync_last_error` (texto) y `sync_last_ts` (timestamp/epoch)

Migraciones (`onUpgrade`):
- Reasegurar tablas con `IF NOT EXISTS`.
- Añadir columnas nuevas idempotentes (`ensureCajaDiariaColumn`).
- Backfill para cajas viejas:
    - Resolver y completar `disciplina_id` a partir de la disciplina.
    - Calcular y completar `evento_id` determinístico a partir de `disciplina_id` y fecha (YYYY-MM-DD).
    - Inicializar `sync_estado`.

Helpers:
- `AppDatabase.logLocalError(scope, error, stackTrace?, payload?)` para no romper flujo.

## Sincronización (Supabase únicamente, migración al esquema nuevo)
Objetivo: subir datos completos al cerrar caja, sin sobrescribir remoto y sin re-subida.

### Regla de NO re-subida (estricta)
- Si la caja ya existe en Supabase (por `codigo_caja` o clave definida), mostrar mensaje “Ya fue subida” y NO permitir volver a subirla.
- No usar `upsert` para cajas/ventas/tickets/movimientos en el flujo nuevo.

### Qué se sincroniza
- Evento
- Caja
- Tickets
- Movimientos de caja
- (y las ventas/items si aplica al modelo remoto)

### Cola local (`sync_outbox`)
- Registrar envíos en `sync_outbox` con `tipo` y `ref`.
- Evitar duplicados: índice único (tipo, ref).
- Reintentos controlados centralmente en un único servicio.
- Si hay error:
    - `sync_outbox.estado='error'`, aumentar `reintentos`, guardar `last_error`.
    - `caja_diaria.sync_estado='ERROR'` (NO marcar sincronizada).

### Validaciones para marcar SINCRONIZADA
- Solo marcar `caja_diaria.sync_estado='SINCRONIZADA'` cuando:
    - la caja se insertó correctamente en Supabase, y
    - todos los registros dependientes (tickets, movimientos, etc.) se insertaron correctamente.
- Si una parte falla, la caja NO queda sincronizada.

### Supabase (esquema)
- Crear tablas en Supabase con los mismos campos que la base local, y agregados `dispositivo_id`, `alias_caja`, `evento_id`, `disciplina_id`.
- No hay datos preexistentes: se asume esquema vacío.
- No agregar autenticación por ahora.

## Impresión
- Mantener impresión térmica USB como primaria.
- Fallback: PDF (previsualización).
- Manejar errores con `AppDatabase.logLocalError(scope: 'caja_page.usb_print', ...)`.

## Flujos (no romper)
1) Apertura de caja:
    - Completar disciplina + fondo inicial + usuario/cajero.
    - Insert `caja_diaria.estado='ABIERTA'`.
    - Setear `disciplina_id`, `evento_id`, `dispositivo_id`, `alias_caja` y `sync_estado='PENDIENTE'`.
2) Venta:
    - NO cambiar la lógica existente de registro de ventas.
3) Movimientos:
    - Registrar ingresos/retiros en `caja_movimiento`.
4) Cierre:
    - Set `caja_diaria.estado='CERRADA'`.
    - Mantener solo lectura.
    - `sync_estado` queda `PENDIENTE` hasta sincronizar.

## Anulación de Tickets y Ventas
- Mantener auditoría: NO borrar filas físicas.
- Venta anulada: `ventas.activo=0`.
- Ticket anulado: `tickets.status='Anulado'`.

## Testing
- Ejecutar tests después de cambios en: caja, cierre, totales, sincronización.
- Antes de crear un test nuevo, verificar si ya existe uno similar en `test/`.
- Política: no mergear cambios críticos sin tests verdes.

## Convenciones de Código
- Nombres de archivos: snake_case; pantallas terminan en `_page.dart`.
- Evitar lógica de negocio en Widgets; mover a `services/`.
- Columnas DB en snake_case.
- No crear nuevas tablas sin actualizar `onCreate` y `onUpgrade` simultáneamente.
- Logging: `scope` granular (`caja.abrir`, `caja.cerrar`, `sync.envio`, etc.).

## Checklist antes de Commit
- Migraciones idempotentes (instalaciones previas no se rompen).
- Backfill de `disciplina_id` y `evento_id` aplicado a cajas existentes.
- `sync_estado` implementado y consistente con reglas.
- Sync nuevo no hace `upsert` y bloquea re-subida.
- UI de Eventos funciona offline; refresh Supabase es manual.
- Tests relevantes verdes.

## Preguntar Antes de
- Crear una pantalla nueva si existe una parecida.
- Añadir un paquete externo (verificar `pubspec.yaml`).
- Agregar un mecanismo alternativo de sync.

