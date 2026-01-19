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

### Arquitectura por Features (ACTUAL)
La aplicación utiliza arquitectura modular basada en features para separar responsabilidades:

```
lib/
 ├── features/
 │    ├── home/                     # Selector de modo (Buffet/Tesorería)
 │    │    └── home_page.dart
 │    │
 │    ├── buffet/                   # Módulo de ventas de productos
 │    │    ├── pages/              # Pantallas de buffet
 │    │    │    ├── buffet_home_page.dart (antes pos_main_page)
 │    │    │    ├── cart_page.dart
 │    │    │    ├── products_page.dart
 │    │    │    ├── caja_open_page.dart
 │    │    │    ├── caja_page.dart
 │    │    │    ├── sales_list_page.dart
 │    │    │    └── ...
 │    │    ├── services/           # Lógica de negocio buffet
 │    │    │    ├── caja_service.dart
 │    │    │    └── venta_service.dart
 │    │    └── state/              # Estado específico buffet
 │    │         └── cart_model.dart
 │    │
 │    ├── tesoreria/               # Módulo de movimientos financieros
 │    │    ├── pages/              # Pantallas de tesorería
 │    │    │    └── movimientos_page.dart
 │    │    ├── services/           # Lógica de tesorería
 │    │    └── state/              # Estado de tesorería
 │    │
 │    ├── eventos/                 # Gestión de eventos
 │    │    └── pages/
 │    │         ├── eventos_page.dart
 │    │         └── detalle_evento_page.dart
 │    │
 │    └── shared/                  # Componentes compartidos
 │         ├── pages/              # Páginas compartidas (settings, help, etc.)
 │         ├── services/           # Servicios compartidos (print, sync, export, etc.)
 │         ├── state/              # Estado compartido (app_settings)
 │         └── format.dart         # Utilidades de formato
 │
 ├── data/                         # Capa de datos
 │    └── dao/
 │         └── db.dart             # AppDatabase (SQLite)
 │
 ├── domain/                       # Entidades y lógica pura
 │    └── models.dart
 │
 ├── env/                          # Configuración de entorno
 │
 └── main.dart                     # Entry point
```

### Principios de Arquitectura

**Separación de Features:**
- ❌ Buffet NO conoce Tesorería
- ❌ Tesorería NO conoce Buffet
- ✅ Solo se comunican vía Evento / Contexto activo
- ✅ Shared contiene todo lo común (servicios, configuración, impresión)

**Responsabilidades:**
- `main.dart`: arranque, inicialización de fecha local, `SupaSyncService.init()`, reconexión impresora (`UsbPrinterService`), determina ruta inicial según estado de caja.
- `data/dao/db.dart`: clase `AppDatabase`. Creación/migración, índices, seeds, logging de errores y helpers de columnas.
- `features/*/services/`: lógica de negocio específica del feature. Evitar lógica pesada en Widgets.
- `features/*/pages/`: pantallas del feature. Convención `<nombre>_page.dart`.
- `features/*/state/`: `ChangeNotifier` y modelos de estado del feature.
- `domain/`: entidades y lógica pura sin dependencias de Flutter.

## Arquitectura vNext (multi-subcomisión sin romper Buffet)

### 🎯 Objetivo
Extender la app existente para soportar múltiples subcomisiones (Fútbol Mayor, Infantil, Patín, etc.) de modo que:
- Cada subcomisión vea solo sus eventos y movimientos.
- La comisión del club pueda obtener reportes mensuales consolidados (desde Supabase).
- El flujo operativo del buffet NO se complique: sigue siendo rápido y “modo cancha”.

### 🔑 Principio rector (NO negociable)
> La subcomisión es el eje organizativo,
> el evento es el contexto operativo,
> la caja buffet NO conoce de balances generales.

## Modelo conceptual (nuevo)

### Subcomisión = Disciplina (ya existente)
Se reutiliza `disciplinas` como subcomisiones.

Ejemplos:
- Fútbol Mayor
- Fútbol Infantil
- Patín
- Vóley
- Comisión Club (disciplina especial)

📌 NO crear una nueva entidad para subcomisión si no es estrictamente necesario.

### Entidades clave (resumen)
```
Disciplina (Subcomisión)
│
├── Evento
│   ├── Cajas (buffet)
│   └── Movimientos financieros (no buffet)
│
└── Reportes mensuales (solo Supabase)
```

## Conceptos vNext (a respetar en cambios)

### 1) Dispositivo / Punto de Venta (identidad de instalación)
- Cada instalación debe tener `dispositivo_id` (UUID v4) persistente.
- Se genera una sola vez y se guarda en storage local persistente.
- Si se desinstala y reinstala, se genera uno nuevo.
- El usuario define `alias_caja` (ej. Caja 01) y queda fijo para esa instalación.
- TODO registro sincronizado a Supabase debe incluir `dispositivo_id` y debe llevar `alias_caja` para conciliación.
- NO acoplar lógica al hardware: el id identifica instalación, no el teléfono.

### 2) Evento (contexto operativo)
- Evento = `disciplina_id` + `fecha_evento`.
- `disciplina_id` es estable en todos los dispositivos (disciplinas precargadas, sin ABM).
- `fecha_evento` se toma de la FECHA de apertura (YYYY-MM-DD, sin hora/minutos).

#### `evento_id` determinístico
- `evento_id` debe ser determinístico e igual en todos los dispositivos.
- Preferir UUID v5 con namespace fijo, derivado de `disciplina_id` y `fecha_evento`.
- Si algo no está implementado aún, preguntar antes de elegir hash/uuid.

### 3) Caja (buffet) — no mezclar con finanzas generales
- Cada dispositivo abre su propia caja dentro de un evento.
- La caja debe guardar: `evento_id`, `disciplina_id`, `dispositivo_id`, `alias_caja`.
- Estado operativo de caja: `ABIERTA` | `CERRADA` (NO mezclar con sync).

#### Estado de sincronización (para cajas)
- Columna separada en `caja_diaria`: `sync_estado` = `PENDIENTE` | `SINCRONIZADA` | `ERROR`.
- Reglas:
  - Si la caja está `ABIERTA`, su `sync_estado` debe ser `PENDIENTE`.
  - Solo una caja `CERRADA` puede pasar a `SINCRONIZADA`.
  - Si falla la sincronización, `sync_estado` debe quedar/volver a `ERROR` y NO marcarse como sincronizada.

### 4) Movimientos financieros externos al Buffet (NUEVO)

#### Nueva tabla: `evento_movimiento` (local + Supabase)
Movimiento financiero externo al buffet (ingresos/egresos de la subcomisión), NO depende de `caja_diaria`.

Campos mínimos:
- `id`
- `evento_id` (nullable)
- `disciplina_id` (OBLIGATORIO)
- `tipo` → `INGRESO` | `EGRESO`
- `categoria`
- `monto`
- `medio_pago_id`
- `observacion`
- `dispositivo_id`
- `created_ts`
- `sync_estado`

Reglas:
- Si hay evento activo → se asigna automáticamente.
- Si no hay evento → movimiento semanal/mensual (queda con `evento_id` null).
- Insert-only, sin upsert.

### 5) Contexto activo (clave para UX)
Agregar concepto explícito:
- `disciplina_activa`
- `evento_activo` (opcional)

Reglas:
- Al abrir caja: disciplina obligatoria; evento implícito (se deriva de disciplina + fecha de apertura).
- Al cargar movimiento: disciplina por contexto; evento si existe contexto activo.

📌 La UX debe permitir operar “sin pensar en módulos”: buffet queda igual.

## Pantallas (existentes + nuevas)

### Pantallas existentes (NO romper)
- Abrir caja, registrar ventas/movimientos, cerrar caja, imprimir/mostrar resumen.

### Pantallas nuevas
#### Mobile (operativa)
1) Home
    - Selector de `disciplina_activa`.
    - Indicador de `evento_activo` (si existe).
    - Acciones: Buffet, Cargar movimiento, Pendientes de sincronizar.

2) Selector de Evento
    - Lista de eventos del día (offline).
    - Opción: “Evento semanal / sin partido” (equivale a `evento_activo = null`).
    - Mostrar disciplina y fecha.

3) Cargar Movimiento
    - Formulario rápido: Tipo (Ingreso/Egreso), Categoría, Monto, Medio de pago, Observación opcional.
    - Disciplina automática por contexto.
    - Evento automático si hay evento activo.
    - Guardado local inmediato.

4) Buffet
    - Mantener flujo actual.
    - No mostrar conceptos financieros generales.

5) Pendientes
    - Listado de cajas pendientes y movimientos (`evento_movimiento`) pendientes.
    - Estados: pendiente, error, sincronizado.

#### Mobile (gestión offline de eventos)
6) Eventos
    - Lista por defecto: eventos del día.
    - 100% offline leyendo de SQLite.
    - Acceso secundario: eventos históricos.
    - Opción manual: “Refrescar desde Supabase” (NO automática).

7) Detalle de Evento
    - Muestra todas las cajas del evento (de todos los dispositivos).
    - Por caja: `alias_caja`, estado (operativo + sync), totales.
    - Permite ver detalle de una caja.
    - NO permite modificar cajas de otros dispositivos.

Reglas estrictas:
- NO mezclar datos entre eventos.
- NO modificar datos de cajas cerradas.
- NO asumir conectividad.

### Estado Actual de Implementación (Fase 1 Completada)

✅ **Arquitectura por Features**
- Estructura de carpetas creada
- Código migrado y organizado por módulos
- Imports actualizados
- Tests de buffet funcionando

✅ **Módulos Implementados:**
- `features/buffet/` - Completo y funcional
- `features/shared/` - Servicios compartidos funcionando
- `features/eventos/` - Gestión básica de eventos
- `features/tesoreria/` - Estructura base (solo movimientos_page)

⏳ **Próximas Fases:**
- Fase 2: Mode Selector (Home mejorada)
- Fase 3: Tesorería completa
- Fase 4: Sincronización unificada

## Base de Datos (SQLite) – Tablas en `AppDatabase`
Mantener el esquema existente y extenderlo de forma idempotente en migraciones.

Tablas principales (existentes):
- `metodos_pago`, `Categoria_Producto`, `products`, `disciplinas`, `punto_venta`
- `caja_diaria`, `ventas`, `venta_items`, `tickets`, `caja_movimiento`
- `sync_outbox`, `sync_error_log`, `app_error_log`

Nueva tabla (vNext):
- `evento_movimiento`

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

Migraciones para `evento_movimiento`:
- Crear tabla con `IF NOT EXISTS`.
- Índices recomendados: (`disciplina_id`, `created_ts`) y (`evento_id`) si aplica.
- `sync_estado` default `PENDIENTE`.

Helpers:
- `AppDatabase.logLocalError(scope, error, stackTrace?, payload?)` para no romper flujo.

## Sincronización (Supabase únicamente, migración al esquema nuevo)
Objetivo: subir datos completos (cajas y movimientos) sin sobrescribir remoto y sin re-subida.

### Regla de NO re-subida (estricta)
- Si la caja ya existe en Supabase (por `codigo_caja` o clave definida), mostrar mensaje “Ya fue subida” y NO permitir volver a subirla.
- No usar `upsert` para cajas/ventas/tickets/movimientos en el flujo nuevo.

### Qué se sincroniza
- Evento
- Caja
- Tickets
- Movimientos de caja
- Movimientos financieros externos (`evento_movimiento`)
- (y las ventas/items si aplica al modelo remoto)

### Cola local (`sync_outbox`)
- Registrar envíos en `sync_outbox` con `tipo` y `ref`.
- Evitar duplicados: índice único (tipo, ref).
- Reintentos controlados centralmente en un único servicio.
- Si hay error:
    - `sync_outbox.estado='error'`, aumentar `reintentos`, guardar `last_error`.
    - `caja_diaria.sync_estado='ERROR'` (NO marcar sincronizada).

Reglas para `evento_movimiento`:
- Integrar a `sync_outbox` (tipo sugerido: `evento_movimiento`).
- Insert-only (sin upsert).
- Si falla sync: dejar `evento_movimiento.sync_estado='ERROR'` y registrar en `sync_outbox`.

### Validaciones para marcar SINCRONIZADA
- Solo marcar `caja_diaria.sync_estado='SINCRONIZADA'` cuando:
    - la caja se insertó correctamente en Supabase, y
    - todos los registros dependientes (tickets, movimientos, etc.) se insertaron correctamente.
- Si una parte falla, la caja NO queda sincronizada.

### Supabase (esquema)
- Crear tablas en Supabase con los mismos campos que la base local, y agregados `dispositivo_id`, `alias_caja`, `evento_id`, `disciplina_id`.
- No hay datos preexistentes: se asume esquema vacío.
- No agregar autenticación por ahora.

Reportes:
- Reportes mensuales consolidados se generan SOLO desde Supabase (desktop/web o consultas externas), no en mobile.

## Compatibilidad hacia atrás (NO romper)
- Eventos históricos: si `disciplina_id` falta, inferir si hay forma no ambigua; si no, pedir confirmación antes de asumir.
- Cajas viejas: no se tocan salvo backfill de columnas nuevas idempotentes.
- Buffet: no se ve afectado.

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

## Manejo de Errores (OBLIGATORIO en todas las pantallas)

### Principio rector
> TODO error debe ser capturado, logueado y presentado al usuario de forma amigable.

### Reglas NO negociables

**1. Try-Catch en operaciones críticas:**
- Wrap SIEMPRE las operaciones async en try-catch (cargar datos, guardar, actualizar, eliminar)
- Incluir stack trace en el catch: `catch (e, stack)`
- NO mostrar stacktraces técnicos al usuario

**2. Logging automático con AppDatabase.logLocalError:**
```dart
try {
  // operación crítica
} catch (e, stack) {
  await AppDatabase.logLocalError(
    scope: 'nombre_pantalla.operacion',  // Ej: 'detalle_jugador.cargar_datos'
    error: e.toString(),
    stackTrace: stack,                    // StackTrace, NO String
    payload: {'context': 'data'},         // Información de contexto
  );
  
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mensaje amigable al usuario'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

**3. Mensajes amigables al usuario:**
- ❌ MAL: `"type 'Null' is not a subtype of type 'String'"`
- ✅ BIEN: `"Error al cargar datos. Por favor, intente nuevamente."`
- ✅ MEJOR: `"No se pudieron cargar los jugadores. Verifique su conexión e intente nuevamente."`

**4. Null-safety en datos de UI:**
- NUNCA asumir que un campo existe o no es null
- Usar operadores seguros: `campo?.toString() ?? 'valor_por_defecto'`
- Casteos seguros: `(valor as num?)?.toDouble() ?? 0.0`

**5. Scope naming (granular):**
- Formato: `pantalla.operacion`
- Ejemplos válidos:
  - `detalle_jugador.cargar_datos`
  - `plantel_page.render_tarjeta`
  - `crear_compromiso.guardar`
  - `sync.enviar_caja`
  - `buffet.abrir_caja`

**6. Try-catch individual en renderizado:**
Para listas/iteraciones, wrap cada item:
```dart
itemBuilder: (context, index) {
  try {
    final item = items[index];
    // renderizar item
    return Card(...);
  } catch (e, stack) {
    AppDatabase.logLocalError(
      scope: 'pantalla.render_item',
      error: e.toString(),
      stackTrace: stack,
      payload: {'index': index},
    );
    return Card(
      child: ListTile(
        leading: Icon(Icons.warning),
        title: Text('Error al mostrar elemento'),
      ),
    );
  }
}
```

**7. Estados de error en la UI:**
- Agregar variables de estado: `String? _errorMessage;`
- Mostrar widgets de error condicionalmente: `if (_errorMessage != null) _buildError()`
- Permitir reintentos: botón "Reintentar" que llama nuevamente a `_cargarDatos()`

### Checklist de implementación

Antes de dar por completa una pantalla, verificar:
- [ ] Todos los métodos async tienen try-catch
- [ ] Todos los errores se loguean con `AppDatabase.logLocalError`
- [ ] Los mensajes al usuario son en español y amigables
- [ ] Los campos de datos usan null-safety (`?.`, `??`)
- [ ] Los scopes de error son específicos y descriptivos
- [ ] El stackTrace se pasa como `StackTrace`, no como `String`
- [ ] La app NO crashea si hay datos malformados o nulls inesperados

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

---

# 2) PROMPT PARA STITCH

*(Wireframe – pantallas nuevas / ajustes)*

## 🎯 Contexto para Stitch
Aplicación mobile + desktop para gestión financiera de un club deportivo con múltiples subcomisiones.
Uso principal en eventos deportivos, a veces sin internet (offline-first).

## 🧱 Objetivo del wireframe
Diseñar pantallas simples y operativas, donde:
- El usuario no piense en módulos.
- El sistema use: subcomisión (disciplina), evento (opcional), origen del movimiento.

## 🖥️ WIREFRAME – APP MOBILE (OPERATIVA)

### 🏠 Home
- Selector de Disciplina activa.
- Indicador de Evento activo (si existe).
- Acciones: Buffet, Cargar movimiento, Pendientes de sincronizar.

### ⚽ Selector de Evento
- Lista de eventos del día (offline).
- Opción: “Evento semanal / sin partido”.
- Nota: usar un “evento especial” (no `null`) cuando no haya partido.
- Mostrar disciplina y fecha.

### ➕ Cargar Movimiento
Formulario rápido:
- Tipo: Ingreso / Egreso
- Categoría (según disciplina)
- Monto
- Medio de pago
- Observación (opcional)

Comportamiento:
- Disciplina automática.
- Evento automático si activo.
- Guardado local inmediato.

### 🍔 Buffet
- Mantener flujo actual.
- No mostrar conceptos financieros generales.

### 📦 Pendientes
- Listado de: cajas pendientes, movimientos pendientes.
- Estados: pendiente, error, sincronizado.

## 🖥️ WIREFRAME – APP DESKTOP / WEB (GESTIÓN)

### 📊 Dashboard
- Filtro por: subcomisión, mes.
- KPIs: ingresos, egresos, resultado neto.

### ⚽ Eventos
- Lista por disciplina.
- Detalle: total buffet, gastos externos, resultado del evento.

### 💰 Movimientos
- Tabla filtrable: disciplina, categoría, fecha.
- Export Excel.

### 📑 Reportes Mensuales
- Balance por subcomisión.
- Consolidado del club.
- Export PDF / Excel.

## 🎨 Lineamientos UX
- Mobile: 1 mano, 2 toques máximo.
- Desktop: foco en lectura, no carga de datos.

## 📌 Resultado esperado
- Simple en cancha, poderosa en escritorio.
- Escalable a todas las subcomisiones.
- Sin romper el buffet.

---
## Modelo Conceptual de Tesorería (Acuerdos, Compromisos, Movimientos)

### 🎯 Conceptos Fundamentales (NO MODIFICAR)

**Jerarquía de abstracción:**
- **Acuerdo** = regla / contrato / condición repetitiva (ej: sueldo mensual de un DT)
- **Compromiso** = expectativa futura concreta (ej: cuota 3 del sueldo del DT)
- **Movimiento** = hecho real confirmado (ej: pago confirmado de la cuota 3)

**Regla de oro:**
- Si algo puede ocurrir varias veces → **Acuerdo**
- Si algo se espera que ocurra → **Compromiso**
- Si algo ya ocurrió → **Movimiento**

### 📊 Tabla `acuerdos` (FASE 18)

**Propósito:** Representar reglas o contratos económicos que generan compromisos automáticamente.

**Características:**
- NO impacta saldo (no aparece en reportes contables)
- NO es un evento (es una regla)
- Genera 1 o más compromisos según modalidad y frecuencia
- Puede asociarse a `entidad_plantel` (jugador/DT) o ser general

**Estructura:**
```sql
acuerdos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  unidad_gestion_id INTEGER NOT NULL,      -- FK a unidades_gestion
  entidad_plantel_id INTEGER,              -- FK a entidades_plantel (opcional)
  nombre TEXT NOT NULL,
  tipo TEXT NOT NULL,                      -- 'INGRESO' | 'EGRESO'
  modalidad TEXT NOT NULL,                 -- 'MONTO_TOTAL_CUOTAS' | 'RECURRENTE'
  monto_total REAL,                        -- Para MONTO_TOTAL_CUOTAS
  monto_periodico REAL,                    -- Para RECURRENTE
  frecuencia TEXT NOT NULL,                -- FK a frecuencias.codigo
  frecuencia_dias INTEGER,
  cuotas INTEGER,                          -- Solo para MONTO_TOTAL_CUOTAS
  fecha_inicio TEXT NOT NULL,              -- YYYY-MM-DD
  fecha_fin TEXT,                          -- YYYY-MM-DD (opcional)
  categoria TEXT NOT NULL,
  observaciones TEXT,
  activo INTEGER NOT NULL DEFAULT 1,
  archivo_local_path TEXT,                 -- Adjuntos (contratos)
  archivo_remote_url TEXT,
  archivo_nombre TEXT,
  archivo_tipo TEXT,
  archivo_size INTEGER,
  dispositivo_id TEXT,
  eliminado INTEGER NOT NULL DEFAULT 0,
  sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE',
  created_ts INTEGER NOT NULL,
  updated_ts INTEGER NOT NULL,
  FOREIGN KEY (unidad_gestion_id) REFERENCES unidades_gestion(id),
  FOREIGN KEY (entidad_plantel_id) REFERENCES entidades_plantel(id),
  FOREIGN KEY (frecuencia) REFERENCES frecuencias(codigo),
  CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
  CHECK ((modalidad = 'MONTO_TOTAL_CUOTAS' AND monto_total IS NOT NULL AND cuotas IS NOT NULL) 
         OR (modalidad = 'RECURRENTE' AND monto_periodico IS NOT NULL))
)
```

**Modalidades:**
- `MONTO_TOTAL_CUOTAS`: Monto total dividido en X cuotas iguales (ej: $100.000 en 10 cuotas de $10.000)
- `RECURRENTE`: Mismo monto cada período hasta fecha_fin o indefinidamente (ej: sueldo mensual de $50.000)

**Relación con Compromisos:**
- Tabla `compromisos` tiene columna `acuerdo_id INTEGER` (FK a acuerdos, nullable)
- Si `acuerdo_id IS NOT NULL` → compromiso generado automáticamente por un acuerdo
- Si `acuerdo_id IS NULL` → compromiso creado manualmente (legacy)

### 🔄 Flujo de Trabajo con Acuerdos

1. **Crear Acuerdo:** Usuario crea acuerdo (ej: Sueldo DT - $50.000/mes - 12 meses)
2. **Preview:** Sistema muestra preview de compromisos a generar (12 compromisos de $50.000)
3. **Confirmar:** Usuario confirma → sistema genera compromisos con `acuerdo_id` y `estado='ESPERADO'`
4. **Confirmación de pago:** En la fecha real, usuario confirma compromiso → genera `evento_movimiento` con `estado='CONFIRMADO'`
5. **Actualización:** Sistema marca compromiso como `CONFIRMADO` y actualiza `cuotas_confirmadas` en acuerdo

### ⚠️ Reglas NO Negociables

1. **Acuerdo ≠ Compromiso ≠ Movimiento:** Tres entidades distintas con responsabilidades claras
2. **Acuerdos NO impactan saldo:** Solo aparecen en pantallas de gestión, no en balances
3. **Compromisos legacy:** Mantener compatibilidad con compromisos sin `acuerdo_id`
4. **No editar con confirmados:** Acuerdos con compromisos CONFIRMADO no se pueden editar (solo finalizar)
5. **Soft delete:** Acuerdos nunca se eliminan físicamente (`eliminado=1`)
6. **Usuario confirma todo:** No hay generación automática de movimientos
7. **Auditable:** Cada compromiso conoce su acuerdo origen (`acuerdo_id`)

### 🚫 Fuera de Alcance (NO Implementar)

- ❌ Recalcular automáticamente cuotas futuras
- ❌ Ajustar acuerdos retroactivamente
- ❌ Compartir un mismo acuerdo entre varios jugadores
- ❌ Automatismos contables
- ❌ Eliminaciones físicas
- ❌ Generación automática de movimientos en DB

### 📋 Pantallas de Acuerdos (FASE 18)

1. **`acuerdos_page.dart`:** Listado con filtros (tipo, unidad, entidad, activo/finalizado)
2. **`crear_acuerdo_page.dart`:** Formulario guiado con preview de compromisos
3. **`detalle_acuerdo_page.dart`:** Info + compromisos generados + acciones
4. **`editar_acuerdo_page.dart`:** Solo si no tiene compromisos confirmados

### 🔗 Relación con Módulos Existentes

- **Compromisos:** Se crean desde acuerdos O manualmente (compatibilidad)
- **Movimientos:** Se generan al confirmar compromisos (flujo existente)
- **Plantel:** Acuerdos pueden asociarse a `entidad_plantel_id`
- **Unidades de Gestión:** Todo acuerdo pertenece a una unidad

---
## Backlog incremental (lista de cambios por complejidad)

### Fase 0 — Alinear modelos (bajo riesgo)
1) Confirmar criterios: disciplina “Comisión Club”, categorías por disciplina, y qué significa “Evento semanal/sin partido”.
2) Definir nombres exactos de columnas y defaults (`created_ts` epoch ms, `monto` REAL, y “Evento semanal/sin partido” como evento especial determinístico).

### Fase 1 — Base de datos local (medio)
3) Agregar tabla `evento_movimiento` en `AppDatabase.onCreate`.
4) Agregar migración idempotente en `onUpgrade` + índices.

### Fase 2 — DAO / servicios (medio)
5) Crear DAO para CRUD local de `evento_movimiento` (insert, list por disciplina/evento/fecha, update sync_estado).
6) Crear servicio `EventoMovimientoService` (aplicar reglas de contexto activo y validaciones).

### Fase 3 — UX mínima mobile (medio/alto)
7) Guardar/leer `disciplina_activa` y `evento_activo` en un estado central (ej. `ui/state/`), sin romper Home/Pos.
8) Nueva pantalla “Cargar movimiento” usando el contexto activo (sin tocar flujo buffet).
9) Ajustar Home para permitir seleccionar disciplina + entrar a “Cargar movimiento” y “Pendientes”.

### Fase 4 — Sync (alto)
10) Integrar `evento_movimiento` a `sync_outbox` (insert-only, sin upsert).
11) Implementar marcado de `sync_estado` (`PENDIENTE→SINCRONIZADA` solo en éxito total; `ERROR` si falla).
12) Pantalla “Pendientes” que muestre cajas y movimientos con su estado.

### Fase 5 — Supabase (alto)
13) Definir/crear tabla `evento_movimiento` en Supabase (campos espejo + restricciones mínimas).
14) Asegurar que reportes mensuales se calculan en Supabase (consultas/vistas), no en mobile.

### Fase 6 — Tests (medio)
15) Agregar/ajustar tests unitarios para: inserción movimiento, filtrado por disciplina, transición de `sync_estado` y “no mezclar eventos”.

📌 Regla de trabajo: implementar por fases, correr tests existentes y preguntar si hay ambigüedad.

