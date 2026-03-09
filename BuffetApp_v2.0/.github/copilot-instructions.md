# CDM Gestión — Instrucciones del Proyecto
# Válido para: Claude (Project Instructions) + GitHub Copilot (.github/copilot-instructions.md)

---

## Identidad del proyecto

- **Nombre:** CDM Gestión
- **Descripción:** Sistema de gestión integral del Club Deportivo Mitre
- **Paquete Flutter:** `buffet_app` → pendiente renombrar a `cdm_gestion`
- **DB local:** `barcancha.db` → pendiente renombrar a `cdm_gestion.db`
- **Repositorio:** `manuellena5/SistemaDeGestion_CDM` (carpeta `BuffetApp_v2.0`)
- **NO llamarlo "ERP" en la UI.** Sí se puede usar el término en conversaciones técnicas.

---

## Estilo de respuesta (para agentes)

- Responder SIEMPRE en español, con pasos accionables y ejemplos concretos.
- Antes de crear un archivo nuevo, verificar si ya existe algo similar.
- Si algo no está claro, cerrar con preguntas numeradas (máx. 5).
- Comentarios en español. Código (variables, funciones, archivos) en inglés.

---

## Stack tecnológico

| Componente | Tecnología |
|---|---|
| Framework | Flutter / Dart |
| Base de datos local | SQLite via `sqflite` + `sqflite_common_ffi` (desktop) |
| Sincronización | Supabase (ya integrado, sync eventual) |
| State management | Provider (migración gradual a Riverpod al agregar módulos) |
| Plataformas actuales | Android + Windows Desktop |
| Plataformas futuras | iOS, Web |
| Reportes | `pdf` + `printing` |
| Gráficos | `fl_chart` |
| Exportación | `excel` + `file_saver` |
| Impresión | USB térmica (primaria) + PDF preview (fallback) |

---

## Principios NO negociables

- **Offline-first siempre.** Todo funciona sin conexión. Supabase es sync eventual.
- **El módulo de buffet NO debe romperse.** Está en producción. Todos los cambios son aditivos.
- **NO forzar conexión a internet** ni asumir conectividad permanente.
- **NO agregar autenticación/login/roles por ahora.** Se agrega cuando Tesorería esté estable.
- **La DB local es la fuente primaria** mientras la caja está ABIERTA.
- **Una caja CERRADA es solo lectura:** no se edita, no se elimina.
- **Soft delete siempre:** nunca borrar filas físicas de entidades (`eliminado = 1`).
- **Timestamps en UTC** para todo lo que va a Supabase. El display local se hace en la UI con `intl`.

---

## Arquitectura general

### Separación de features (ESTRICTA)
- ❌ Buffet NO conoce Tesorería
- ❌ Tesorería NO conoce Buffet
- ✅ Solo se comunican vía Evento / Contexto activo
- ✅ `shared/` contiene todo lo común (servicios, configuración, impresión, formato)

### Responsabilidades por capa
- `main.dart` → arranque, init de fecha local, `SupaSyncService.init()`, reconexión impresora, ruta inicial
- `data/database/app_database.dart` → lifecycle DB, schema, migraciones, índices, seeds
- `data/dao/<dominio>_dao.dart` → operaciones CRUD por dominio (NO mezclar dominios)
- `features/*/services/` → lógica de negocio del feature. Nunca lógica pesada en widgets.
- `features/*/pages/` → pantallas. Convención: `<nombre>_page.dart`
- `features/*/state/` → ChangeNotifier y modelos de estado del feature
- `domain/` → entidades y lógica pura sin dependencias de Flutter

---

## Estructura de carpetas (estado actual + objetivo)

```
lib/
├── core/
│   ├── theme/              # app_theme.dart — ya existe
│   ├── constants/          # colores, strings, rutas
│   └── utils/              # formatters, validators
├── data/
│   ├── database/
│   │   └── app_database.dart     # lifecycle, schema, migraciones ÚNICAMENTE
│   └── dao/
│       ├── buffet_dao.dart        # extraer de db.dart
│       ├── tesoreria_dao.dart     # extraer de db.dart ← PRIORIDAD
│       ├── cuentas_dao.dart       # extraer de db.dart
│       ├── sync_dao.dart          # extraer de db.dart
│       └── error_log_dao.dart     # extraer de db.dart
├── domain/
│   └── models.dart
├── env/
├── features/
│   ├── buffet/             # ✅ completo y funcional — NO tocar
│   │   ├── pages/
│   │   ├── services/
│   │   └── state/
│   ├── cuentas/            # ✅ existe — mantener
│   ├── eventos/            # ✅ existe — mantener
│   ├── home/               # ✅ existe — mantener
│   ├── shared/             # ✅ existe — mantener
│   └── tesoreria/          # 🔧 estructura base existe, construyendo
│       ├── pages/
│       │   ├── movimientos_page.dart    # existe
│       │   ├── movimiento_form_page.dart
│       │   └── balance_page.dart
│       ├── models/
│       │   ├── movimiento_tesoreria.dart
│       │   └── categoria_tesoreria.dart
│       ├── services/
│       │   └── tesoreria_service.dart
│       └── state/
│           └── tesoreria_state.dart
└── main.dart
```

---

## Estructura organizativa del club

**Subcomisiones (= `unidades_gestion` en la DB):**
Fútbol Mayor, Fútbol Infantil, Fútbol Senior, Vóley, Tenis, Patín, Comisión Directiva

> `disciplinas` y `unidades_gestion` son la misma entidad. La migración v14 renombró
> `disciplinas` → `unidades_gestion`. En el código siempre usar `unidades_gestion`.

**Roles (a implementar en fase futura):**
- Tesorero → editor completo (usuario primario)
- Secretario → editor limitado
- Vocal / Miembro → solo lectura
- Comisión Directiva → lectura consolidada de todo el club

---

## Estado actual del proyecto

### ✅ Funcionando en producción
- Módulo Buffet completo (caja, ventas, cierre, impresión)
- Schema SQLite v22 con migraciones
- sync_outbox pattern implementado
- Supabase inicializado
- Error logging local (`app_error_log` + `logLocalError()`)
- Backup físico de DB
- Tablas ERP existentes: `unidades_gestion`, `evento_movimiento`, `compromisos`, `acuerdos`, `acuerdos_versiones`, `presupuesto_anual`, `saldos_iniciales`, `entidades_plantel`

### 🔧 Refactoring pendiente (hacer ANTES de nueva funcionalidad)
1. Renombrar app: `buffet_app` → `cdm_gestion`, `barcancha.db` → `cdm_gestion.db`
2. Separar `data/dao/db.dart` (1870 líneas) en DAOs por dominio
3. Cambiar `nowLocalSqlString()` → `nowUtcSqlString()` (usar `DateTime.now().toUtc()`)
4. Eliminar métodos deprecated no-op (`ensureCajaDiariaColumn`, etc.)

### 📋 Módulos planificados (en orden de prioridad)
1. **Tesorería** ← PRIORIDAD ACTUAL
2. Gestión de Socios
3. Reportes consolidados (balance por subcomisión + consolidado club)
4. Dashboard Comisión Directiva
5. Histórico persistente del módulo Buffet
6. Login y roles

---

## Modelo conceptual de Tesorería

### Jerarquía (NO modificar)
- **Acuerdo** = regla/contrato repetitivo (ej: sueldo mensual del DT)
- **Compromiso** = expectativa futura concreta (ej: cuota 3 del sueldo)
- **Movimiento** = hecho real confirmado (ej: pago efectuado)

**Regla de oro:**
- Si algo puede ocurrir varias veces → Acuerdo
- Si algo se espera que ocurra → Compromiso
- Si algo ya ocurrió → Movimiento

### Reglas de negocio clave
- Acuerdos NO impactan saldo (no aparecen en balances contables)
- Compromisos con estado CONFIRMADO no se pueden editar (solo finalizar)
- Compromisos legacy (sin `acuerdo_id`) deben seguir funcionando
- El usuario confirma TODO. No hay generación automática de movimientos.
- Cada movimiento se encola en `sync_outbox` al crearse/modificarse

---

## Base de datos — reglas

### Schema
- Nunca crear tablas sin actualizar `onCreate` Y `onUpgrade` simultáneamente
- Migraciones siempre idempotentes (`IF NOT EXISTS`, `ALTER TABLE` con verificación previa)
- Columnas DB en `snake_case`
- `sync_estado` en entidades sincronizables: `PENDIENTE` | `SINCRONIZADA` | `ERROR`
- `created_ts` y `updated_ts` en milliseconds Unix (epoch). Texto SQL en UTC.

### sync_outbox pattern
- Toda operación de escritura relevante encola en `sync_outbox` con `tipo` y `ref`
- Índice único en `(tipo, ref)` para evitar duplicados
- Si falla sync: `sync_outbox.estado='error'`, aumentar `reintentos`, guardar `last_error`
- NO usar `upsert` para cajas/ventas/movimientos — insert-only
- Solo marcar `SINCRONIZADA` cuando TODOS los registros dependientes se insertaron correctamente

### Método de timestamp (fix pendiente)
```dart
// ❌ Actual — NO usar para datos que van a Supabase:
static String nowLocalSqlString() {
  final d = DateTime.now(); // hora local
  ...
}

// ✅ Correcto — siempre UTC:
static String nowUtcSqlString() {
  final d = DateTime.now().toUtc();
  ...
}
```

---

## Manejo de errores (OBLIGATORIO en todas las pantallas)

### Reglas NO negociables

**1. Try-catch en TODA operación async crítica:**
```dart
try {
  // operación
} catch (e, stack) {
  await AppDatabase.logLocalError(
    scope: 'pantalla.operacion',  // ej: 'tesoreria.guardar_movimiento'
    error: e.toString(),
    stackTrace: stack,             // StackTrace, NO String
    payload: {'context': 'data'},
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

**2. Mensajes al usuario en español y amigables:**
- ❌ `"type 'Null' is not a subtype of type 'String'"`
- ✅ `"No se pudo guardar el movimiento. Intentá nuevamente."`

**3. Modal de confirmación para TODA transacción:**
Crear, editar, eliminar, confirmar pago, sincronizar, abrir/cerrar caja → siempre `showDialog` con resultado detallado.

**4. Null-safety en datos de UI:**
```dart
campo?.toString() ?? 'valor_por_defecto'
(valor as num?)?.toDouble() ?? 0.0
```

**5. Scope naming granular:**
Formato: `feature.operacion` — ejemplos: `tesoreria.guardar_movimiento`, `buffet.abrir_caja`, `sync.enviar_caja`

**6. Try-catch en renderizado de listas:**
```dart
itemBuilder: (context, index) {
  try {
    return Card(...);
  } catch (e, stack) {
    AppDatabase.logLocalError(scope: 'pantalla.render_item', error: e.toString(), stackTrace: stack, payload: {'index': index});
    return const Card(child: ListTile(leading: Icon(Icons.warning), title: Text('Error al mostrar elemento')));
  }
}
```

### Checklist antes de dar una pantalla por completa
- [ ] Todos los métodos async tienen try-catch
- [ ] Todos los errores se loguean con `logLocalError`
- [ ] Mensajes al usuario en español y amigables
- [ ] Campos de datos con null-safety (`?.`, `??`)
- [ ] Scopes descriptivos y granulares
- [ ] stackTrace pasado como `StackTrace`, no como `String`
- [ ] La app NO crashea con datos malformados o nulls inesperados
- [ ] Toda transacción muestra modal final con resultado

---

## Cómo debe ayudar el agente

1. **Código siempre completo y funcional.** Si modificás un archivo existente, mostrá el archivo completo o indicá claramente con comentarios `// INICIO CAMBIO` / `// FIN CAMBIO` dónde va cada parte.
2. **Ante cambios de schema,** incluir siempre el script de migración (incrementar versión DB) + backfill si aplica.
3. **Ante decisiones de arquitectura,** proponer opciones con pros/contras y recomendar una con justificación breve.
4. **Antes de desarrollar un módulo nuevo,** proponer estructura de archivos y modelo de datos. Esperar confirmación antes de escribir código.
5. **El módulo Buffet está en producción.** Cualquier cambio en `app_database.dart` o el schema NO debe romperlo.
6. **Sync siempre presente:** al crear/modificar/eliminar entidades relevantes, incluir el encolado en `sync_outbox`.
7. **Preguntar antes de:** crear pantalla similar a una existente, agregar paquete externo, agregar mecanismo alternativo de sync.

---

## Checklist antes de commit

- [ ] Migraciones idempotentes (instalaciones previas no se rompen)
- [ ] `sync_estado` implementado y consistente con las reglas
- [ ] Sync nuevo no hace `upsert` y bloquea re-subida
- [ ] Tests relevantes verdes (`flutter analyze` + `flutter test`)
- [ ] Módulo Buffet probado manualmente y funcionando
- [ ] No hay `print()` nuevos — usar `AppDatabase.logLocalError()`

---

## Prompt de inicio de sesión diaria

Al empezar cada sesión de trabajo con Claude, usar este formato:

```
Hoy quiero trabajar en: [DESCRIBIR TAREA]
Estado actual del módulo: [QUÉ ESTÁ HECHO, QUÉ FALTA]
Duda o bloqueo puntual: [SI APLICA]
```
