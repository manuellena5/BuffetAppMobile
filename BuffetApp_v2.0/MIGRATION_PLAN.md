# Plan de Migración - Reestructuración Features

## 📁 Nueva Estructura

```
lib/
 ├── features/
 │    ├── home/                  # Selector de modo (Buffet/Tesorería)
 │    ├── buffet/               # Todo lo relacionado a ventas de productos
 │    │    ├── pages/
 │    │    ├── services/
 │    │    └── state/
 │    ├── tesoreria/            # Movimientos financieros externos
 │    │    ├── pages/
 │    │    ├── services/
 │    │    └── state/
 │    ├── eventos/              # Gestión de eventos (compartido conceptualmente)
 │    │    └── pages/
 │    └── shared/               # Componentes compartidos
 │         ├── services/
 │         ├── widgets/
 │         └── state/
 ├── data/                      # Queda igual (DAO, DB)
 ├── domain/                    # Queda igual (Models)
 └── env/                       # Queda igual (Config)
```

## 🎯 Mapeo de Archivos

### features/shared/ (Compartidos entre Buffet y Tesorería)

**Services:**
- ✅ `services/print_service.dart`
- ✅ `services/usb_printer_service.dart`
- ✅ `services/export_service.dart`
- ✅ `services/supabase_sync_service.dart`
- ✅ `services/sync_service.dart`
- ✅ `services/seed_service.dart`

**State:**
- ✅ `ui/state/app_settings.dart`

**Pages:**
- ✅ `ui/pages/settings_page.dart`
- ✅ `ui/pages/printer_test_page.dart`
- ✅ `ui/pages/help_page.dart`
- ✅ `ui/pages/error_logs_page.dart`
- ✅ `ui/pages/punto_venta_setup_page.dart`

**Otros:**
- ✅ `ui/format.dart`

### features/buffet/ (Específico de ventas de productos)

**Pages:**
- ✅ `ui/pages/pos_main_page.dart` → `buffet_home_page.dart` (renombrar)
- ✅ `ui/pages/cart_page.dart`
- ✅ `ui/pages/products_page.dart`
- ✅ `ui/pages/product_reorder_page.dart`
- ✅ `ui/pages/venta_page.dart`
- ✅ `ui/pages/sales_list_page.dart`
- ✅ `ui/pages/sale_detail_page.dart`
- ✅ `ui/pages/payment_method_page.dart`
- ✅ `ui/pages/caja_open_page.dart`
- ✅ `ui/pages/caja_page.dart`
- ✅ `ui/pages/caja_tickets_page.dart`

**Services:**
- ✅ `services/caja_service.dart`
- ✅ `services/venta_service.dart`

**State:**
- ✅ `ui/state/cart_model.dart`

### features/tesoreria/ (Movimientos financieros)

**Pages (NUEVAS):**
- ⭐ `tesoreria_home_page.dart` (nuevo)
- ⭐ `crear_movimiento_page.dart` (nuevo)
- ⭐ `movimientos_list_page.dart` (adaptado de `movimientos_page.dart`)
- ⭐ `movimiento_detalle_page.dart` (nuevo)

**Services:**
- ✅ `services/movimiento_service.dart`

**State (NUEVO):**
- ⭐ `tesoreria_state.dart` (nuevo - contexto activo de disciplina/evento)

### features/eventos/ (Gestión de eventos)

**Pages:**
- ✅ `ui/pages/eventos_page.dart`
- ✅ `ui/pages/detalle_evento_page.dart`

### features/home/ (Nueva pantalla de selección)

**Pages (NUEVAS):**
- ⭐ `mode_selector_page.dart` (selector Buffet/Tesorería)

## 🔄 Flujo de Navegación NUEVO

```
App Start
    ↓
mode_selector_page (Home)
    ├─→ Buffet
    │    ├─→ buffet_home_page (reemplaza pos_main_page)
    │    │    ├─→ Abrir Caja
    │    │    ├─→ Ventas
    │    │    └─→ Caja
    │    │         └─→ (Gasto del partido → redirige a Tesorería)
    │    └─→ Menú lateral Buffet
    │
    └─→ Tesorería
         ├─→ tesoreria_home_page
         │    ├─→ Crear movimiento
         │    ├─→ Listar movimientos
         │    └─→ Detalle
         └─→ Menú lateral Tesorería
```

## 📝 Notas Importantes

### Reglas de Separación
- ❌ Buffet NO conoce Tesorería
- ❌ Tesorería NO conoce Buffet
- ✅ Solo se comunican vía Evento / Contexto activo

### Compartido
- Configuraciones (impresora, UI scale, etc.)
- Servicios de impresión
- Servicios de sincronización
- Base de datos (data/dao/db.dart)

### Estado del Modo
- Se guarda en `SharedPreferences`: `current_mode` = 'buffet' | 'tesoreria'
- Una vez elegido, la app se mantiene en ese modo
- Se puede cambiar desde configuraciones o menú

## ✅ Checklist de Migración

### Fase 1: Preparación ✅ COMPLETADA
- [x] Crear estructura de carpetas
- [x] Crear documento de mapeo (este archivo)

### Fase 2: Mover Shared ✅ COMPLETADA
- [x] Mover servicios compartidos a `features/shared/services/`
- [x] Mover `app_settings.dart` a `features/shared/state/`
- [x] Mover `format.dart` a `features/shared/`
- [x] Mover páginas compartidas a `features/shared/pages/`
- [x] Agregar clase `Format` con método estático `money()`

### Fase 3: Mover Buffet ✅ COMPLETADA
- [x] Mover páginas de buffet a `features/buffet/pages/`
- [x] Renombrar `pos_main_page.dart` a `buffet_home_page.dart`
- [x] Mover `cart_model.dart` a `features/buffet/state/`
- [x] Mover `caja_service.dart` y `venta_service.dart` a `features/buffet/services/`
- [x] Actualizar todos los imports en módulo buffet

### Fase 4: Crear Home Nueva ✅ COMPLETADA
- [x] Crear `mode_selector_page.dart`
- [x] Implementar lógica de selección de modo
- [x] Guardar modo activo en SharedPreferences
- [x] Crear `AppModeState` para gestión de estado del modo
- [x] Integrar selector en navegación principal

### Fase 5: Crear Tesorería (base) ✅ COMPLETADA
- [x] Crear `tesoreria_home_page.dart`
- [x] Crear `crear_movimiento_page.dart`
- [x] Crear `movimientos_list_page.dart` con filtros por tipo (Ingreso/Egreso/Todos)
- [x] Mover `movimiento_service.dart` a `features/shared/services/`
- [x] Implementar KPIs (ingresos, egresos, saldo)
- [x] Integrar en drawer y navegación

### Fase 6: Actualizar Imports ✅ COMPLETADA
- [x] Actualizar imports en todos los archivos
- [x] Actualizar `main.dart` con navegación por modo
- [x] Implementar `_SeedGate` para verificar configuración de modo

### Fase 7: Testing ✅ COMPLETADA
- [x] Ejecutar tests existentes (19/19 pasando)
- [x] Validar flujo Buffet completo
- [x] Validar navegación entre modos
- [x] Corregir errores de compilación

### Fase 8: Mejoras Tesorería ✅ COMPLETADA
- [x] Agregar filtro por mes en `movimientos_list_page.dart`
- [x] Actualizar KPIs según filtro de mes
- [x] Mejorar UX con selector de mes/año
- [x] Implementar adjuntos de archivos (galería/cámara)
- [x] Validación de tamaño de archivos (25MB)
- [x] Preview de imágenes adjuntas
- [x] Indicador de adjuntos en lista de movimientos

### Fase 9: Separación Buffet/Tesorería y Unidades de Gestión ✅ COMPLETADA

**Contexto:**
- Buffet y Tesorería deben funcionar independientemente
- No todos los usuarios usarán ambos módulos
- Cada módulo tiene diferentes requisitos de configuración inicial

**Cambios de Concepto:**
- ❌ **Disciplina** (concepto limitado a deportes)
- ✅ **Unidad de Gestión** (concepto general que abarca disciplinas, comisiones y eventos)

#### 9.1: Nueva Tabla `unidades_gestion` ✅ COMPLETADO
- [x] Crear tabla con campos:
  - `id` INTEGER PRIMARY KEY
  - `nombre` TEXT NOT NULL (ej: "Fútbol Mayor", "Comisión Directiva")
  - `tipo` TEXT NOT NULL CHECK (tipo IN ('DISCIPLINA','COMISION','EVENTO'))
  - `disciplina_ref` TEXT (referencia a tipo de deporte: FUTBOL, VOLEY, PATIN, etc.)
  - `activo` INTEGER DEFAULT 1
  - `created_ts`, `updated_ts`
- [x] Seed inicial con datos de ejemplo:
  - Fútbol Mayor (DISCIPLINA, FUTBOL)
  - Fútbol Infantil (DISCIPLINA, FUTBOL)
  - Vóley (DISCIPLINA, VOLEY)
  - Patín (DISCIPLINA, PATIN)
  - Comisión Directiva (COMISION, null)
  - Evento Especial (EVENTO, null)
- [ ] Migración de datos existentes desde tabla `disciplinas` (pendiente)
- [x] Mantener tabla `disciplinas` por compatibilidad (deprecated)

#### 9.2: Flujos de Inicio Diferenciados ✅ COMPLETADO
- [x] **Sin Punto de Venta al inicio:** Remover validación global de punto_venta en main.dart
- [x] **Buffet:**
  - Verificar punto_venta solo al entrar a buffet_home_page
  - Si no existe: mostrar punto_venta_setup_page
  - Si existe: continuar flujo normal (abrir caja, ventas, etc.)
- [x] **Tesorería:**
  - NO requiere punto de venta
  - Verificar unidad_gestion_activa al entrar a tesoreria_home_page
  - Si no existe: mostrar selector de Unidad de Gestión
  - Si existe: continuar con la unidad previamente seleccionada

#### 9.3: Gestión de Unidad de Gestión en Tesorería ✅ COMPLETADO
- [x] Crear `UnidadGestionSelectorPage` con agrupación por tipo
- [x] Guardar selección en `AppSettings.unidadGestionActivaId`
- [x] Permitir cambiar Unidad de Gestión desde:
  - AppBar de Tesorería (tap en indicador)
  - Drawer de Tesorería
- [x] Mostrar Unidad de Gestión activa en UI de Tesorería

#### 9.4: Reemplazo de "Disciplina" por "Unidad de Gestión" ✅ COMPLETADO
- [x] Actualizar textos en UI:
  - Labels de formularios
  - Títulos de pantallas
  - Mensajes de validación
- [x] Renombrar variables en código de Tesorería:
  - `_disciplinaNombre` → `_unidadGestionNombre`
  - Validaciones usando `unidadGestionActivaId`
- [x] Mantener compatibilidad con `disciplinaId` para tabla `evento_movimiento`

#### 9.5: Roles y Permisos (Futuro)
- [ ] Diseñar sistema de roles:
  - Usuario normal: solo ve su Unidad de Gestión
  - Comisión Directiva: ve todas las Unidades de Gestión
  - Admin: acceso total
- [ ] Implementar filtros condicionales según rol
- [ ] Pantalla de administración de roles (desktop/web)

#### 9.6: Migración de Datos Existentes (Pendiente)
- [ ] Script de migración `disciplinas` → `unidades_gestion`:
  - Mapear cada disciplina a tipo DISCIPLINA
  - Inferir `disciplina_ref` desde nombre
  - Preservar IDs para compatibilidad
- [ ] Actualizar registros de `evento_movimiento`:
  - Agregar columna `unidad_gestion_id` 
  - Backfill usando `disciplina_id`
- [ ] Validar integridad referencial

## 🚀 Orden de Ejecución

1. ✅ Crear carpetas (COMPLETADO)
2. ✅ Mover shared (COMPLETADO)
3. ✅ Mover buffet (COMPLETADO)
4. ✅ Crear home selector (COMPLETADO)
5. ✅ Crear tesorería base (COMPLETADO)
6. ✅ Actualizar imports (COMPLETADO)
7. ✅ Testing (COMPLETADO - 22/22 tests passing)
8. ✅ Mejoras Tesorería (COMPLETADO - filtros, adjuntos)
9. ✅ Separación Buffet/Tesorería y Unidades de Gestión (COMPLETADO)
10. ✅ Unidad de Gestión en Buffet y navegación directa (COMPLETADO)

---

**Estado:** ✅ Fase 10 Completada - Unidad de Gestión en Buffet
**Última actualización:** Enero 2026

### Resumen de Cambios en Fase 9

1. **main.dart:** Eliminada validación global de punto_venta
2. **buffet_home_page.dart:** Agregada validación de punto_venta específica para Buffet
3. **punto_venta_setup_page.dart:** Agregado callback `onComplete` para flujo desde Buffet
4. **AppSettings:** Nueva propiedad `unidadGestionActivaId` para Tesorería
5. **UnidadGestionSelectorPage:** Nueva página para seleccionar Unidad de Gestión
6. **tesoreria_home_page.dart:** 
   - Verificación de Unidad de Gestión al entrar
   - Indicador de Unidad de Gestión activa en AppBar
   - Opción para cambiar Unidad de Gestión desde drawer
7. **movimientos_list_page.dart:** Actualizado para usar Unidad de Gestión
8. **crear_movimiento_page.dart:** Actualizado para usar Unidad de Gestión
9. **db.dart:** Nueva tabla `unidades_gestion` con seed de 8 unidades

### Resumen de Cambios en Fase 10

1. **caja_open_page.dart:**
   - Selector de Unidad de Gestión obligatorio al abrir caja nueva
   - Campo "Disciplina" reemplazado por "Unidad de Gestión" (solo lectura)
   - Botón "Modificar" para cambiar la Unidad de Gestión seleccionada
   - Validación antes de abrir la caja

2. **Navegación entre módulos corregida:**
   - "Cambiar a Tesorería" desde HomePage ahora va directo a TesoreriaHomePage
   - "Cambiar a Buffet" desde TesoreriaHomePage ahora va directo a BuffetHomePage
   - Eliminada redirección innecesaria a ModeSelectorPage
   - Se actualiza el modo en AppModeState antes de navegar

### Fase 11 ✅ COMPLETADA - Mejoras UX Tesorería y Gestión de Datos

#### 11.1: Visualización de Archivos Adjuntos ✅ COMPLETADO
- **detalle_movimiento_page.dart:**
  - Al tocar una imagen adjunta, se abre con las apps disponibles del dispositivo
  - Usa `open_filex` para abrir archivos con gestor de intents de Android
  - Indicador visual "Toca para abrir" sobre las imágenes
  - Manejo de errores si no se puede abrir el archivo

#### 11.2: Export de Movimientos Mejorado ✅ COMPLETADO
- **movimientos_list_page.dart:**
  - Modal de progreso mientras se exporta
  - Modal de resultado mostrando:
    - Cantidad de movimientos exportados
    - Ubicación del archivo
    - Botón para abrir el archivo directamente
  - Manejo de errores con diálogo descriptivo
  - Integración con `open_filex` para abrir CSV generado

#### 11.3: Doble Tap para Salir ✅ COMPLETADO
- **tesoreria_home_page.dart:**
  - Implementado `PopScope` con lógica de doble tap
  - Mensaje "Presioná nuevamente para salir" en SnackBar
  - Timeout de 2 segundos entre taps
  - Previene salida accidental de la app

#### 11.4: Vista de Tabla para Movimientos ✅ COMPLETADO
- **movimientos_list_page.dart:**
  - Reemplazada vista de lista por `DataTable`
  - Columnas: Fecha, Tipo, Categoría, Monto, Medio Pago, Observación, Adjunto, Estado
  - Scroll horizontal y vertical para tablas grandes
  - Indicadores visuales:
    - Color de fila según estado de sincronización (pendiente/error)
    - Badges de tipo (ingreso/egreso)
    - Iconos para adjuntos
    - Estados de sync con colores
  - Tap en fila abre detalle del movimiento

#### 11.5: Seed de Unidades de Gestión ✅ COMPLETADO
- **db.dart:**
  - Función `_seedUnidadesGestion()` extraída como método separado
  - Se ejecuta en `onCreate` (instalación nueva)
  - Se ejecuta en `onUpgrade` (actualización de DB existente)
  - Garantiza que las 8 unidades de gestión base estén siempre presentes:
    1. Fútbol Mayor
    2. Fútbol Infantil
    3. Vóley
    4. Patín
    5. Tenis
    6. Fútbol Senior
    7. Comisión Directiva
    8. Evento Especial
  - Usa `ConflictAlgorithm.ignore` para no duplicar

#### 11.6: Alternancia entre Vista Tabla y Tarjetas ✅ COMPLETADO
- **movimientos_list_page.dart:**
  - Variable de estado `_vistaTabla` para controlar el tipo de vista
  - Botón toggle en AppBar con icono dinámico
  - Vista de tabla: formato profesional con todas las columnas y scroll
  - Vista de tarjetas: formato compacto con información esencial
  - Método `_buildMovimientoCard()` restaurado para vista de tarjetas
  - Ambas vistas mantienen funcionalidad de tap para ver detalles
  - Los filtros y datos se preservan al cambiar de vista

### Fase 12 🚧 EN PROGRESO - Sincronización de Tesorería con Supabase

#### Análisis del Esquema Actual

**Tu esquema de Supabase YA TIENE:**
- ✅ `metodos_pago`
- ✅ `categoria_producto`
- ✅ `products`
- ✅ `punto_venta`
- ✅ `disciplinas`
- ✅ `eventos` (nueva - con evento_id, disciplina_id, fecha_evento)
- ✅ `caja_diaria` (con campos adicionales: disciplina_id, evento_id, dispositivo_id, alias_caja)
- ✅ `ventas`, `venta_items`, `tickets`, `caja_movimiento`
- ✅ `sync_error_log`, `app_error_log`

**LO QUE FALTA para Tesorería:**
- ❌ Tabla `unidades_gestion` (reemplaza/extiende disciplinas)
- ❌ Tabla `evento_movimiento` (movimientos financieros externos al buffet)

#### 12.1: Script SQL para Supabase ✅ COMPLETADO
- **Archivo:** `tools/supabase_tesoreria_schema.sql`
- **Contenido:**
  - Tabla `unidades_gestion`:
    - Campos: id, nombre, tipo (DISCIPLINA/COMISION/EVENTO), disciplina_ref, activo
    - Seed de 8 unidades base
    - Índice por tipo y estado activo
  - Tabla `evento_movimiento`:
    - Campos básicos: evento_id, disciplina_id, tipo, categoria, monto, medio_pago_id, observacion
    - Soporte adjuntos: archivo_local_path, archivo_remote_url, archivo_nombre, archivo_tipo, archivo_size
    - Soft delete: eliminado (0/1)
    - Tracking: dispositivo_id, sync_estado, created_ts, updated_ts
    - Índices optimizados para consultas por disciplina, evento, tipo
  - Documentación completa del flujo de sincronización
  - Comentarios SQL explicativos

#### 12.2: Servicio de Sincronización ✅ COMPLETADO
- [x] Crear `TesoreriaSyncService` en `features/shared/services/`
- [x] Implementar método `syncMovimiento(int movimientoId)`
- [x] Implementar método `syncUnidadGestion(int unidadId)`
- [x] Subir archivos adjuntos a Supabase Storage
- [x] Actualizar `archivo_remote_url` después de subir
- [x] Manejar estados de sincronización (PENDIENTE → SINCRONIZADA/ERROR)
- [x] Integrar con `sync_outbox` para reintentos
- [x] Implementar `syncMovimientosPendientes()` para sincronización masiva
- [x] Implementar `contarPendientes()` para UI
- [x] Implementar `verificarConexion()` para validar conectividad

**Archivos creados:**
- `lib/features/shared/services/tesoreria_sync_service.dart` (330 líneas)

#### 12.3: UI de Sincronización Manual ✅ COMPLETADO
- [x] Agregar botón "Sincronizar" en `movimientos_list_page.dart` con badge de pendientes
- [x] Modal de progreso durante sincronización
- [x] Modal de resultado (éxitos, errores, advertencias)
- [x] Indicador visual de movimientos pendientes de sincronizar
- [x] Opción para sincronizar movimiento individual desde detalle
- [x] Validación de conexión antes de sincronizar
- [x] Recarga automática de lista después de sincronizar
- [x] Badges visuales en tabla y tarjetas (PENDIENTE/SINCRONIZADA/ERROR)

**Archivos modificados:**
- `lib/features/tesoreria/pages/movimientos_list_page.dart`
  - Agregado `_syncSvc` y `_pendientesCount`
  - Método `_sincronizarPendientes()` con validación y feedback
  - Botón de sincronización en AppBar con badge numérico
  - Badges de estado en vista de tabla y tarjetas
- `lib/features/tesoreria/pages/detalle_movimiento_page.dart`
  - Agregado `_syncSvc`
  - Método `_sincronizar()` para sincronización individual
  - Botón de sincronización en AppBar (solo si pendiente)

#### 12.4: Supabase Storage para Adjuntos ⏳ MANUAL
- [ ] Configurar bucket `movimientos-adjuntos` en Supabase (Manual en UI)
- [x] Implementar upload de imágenes (en `TesoreriaSyncService._uploadArchivo()`)
- [x] Generar URLs públicas para acceso (automático con Storage)
- [ ] Implementar download de adjuntos (opcional - futuro)
- [ ] Validación de tamaño y tipo de archivo (25MB configurado en bucket)

**Nota:** El bucket debe crearse manualmente en Supabase Dashboard con:
- Nombre: `movimientos-adjuntos`
- Público: Sí
- Tamaño máximo: 25MB
- Ver instrucciones en `SUPABASE_TESORERIA_SETUP.md`

#### 12.5: Testing de Sincronización ✅ COMPLETADO
- [x] Test: estructura de servicio singleton
- [x] Test: contarPendientes() sin errores
- [x] Test: verificarConexion() sin excepciones
- [ ] Test: sincronización exitosa de movimiento (requiere Supabase configurado)
- [ ] Test: manejo de errores de red (requiere mock)
- [ ] Test: sincronización con adjuntos (requiere Supabase configurado)

**Archivos creados:**
- `test/tesoreria_sync_service_test.dart` (tests básicos)

#### Consideraciones Importantes

**Diferencias entre Buffet y Tesorería:**
- **Buffet (caja_diaria):** Requiere caja abierta, sin adjuntos, sin soft delete
- **Tesorería (evento_movimiento):** NO requiere caja, soporta adjuntos, soft delete

**Flujo de Sincronización:**
1. Usuario presiona "Sincronizar" en la app
2. App valida conectividad a Supabase
3. Por cada movimiento pendiente:
   - Sube archivo adjunto a Storage (si existe)
   - Inserta registro en `evento_movimiento` con URL del adjunto
   - Marca como SINCRONIZADA en local
4. Si falla alguno, marca como ERROR y registra en `sync_outbox`

**Política de Sincronización:**
- ✅ Insert-only (NO upsert)
- ✅ Manual por ahora (NO automática)
- ✅ Por demanda (usuario decide cuándo sincronizar)
- ✅ Validación antes de sincronizar (no duplicar)

### Fase 13 🚧 EN PROGRESO - Modelo de Datos de Compromisos

#### Objetivo
Crear la infraestructura base para gestionar compromisos (obligaciones financieras recurrentes como sueldos, sponsors, seguros).

#### 13.1: Nueva Tabla `compromisos` ✅ COMPLETADO
- [x] Crear tabla en SQLite con campos:
  - `id` INTEGER PRIMARY KEY AUTOINCREMENT
  - `unidad_gestion_id` INTEGER NOT NULL (FK a unidades_gestion)
  - `nombre` TEXT NOT NULL (ej: "Seguro Federación")
  - `tipo` TEXT NOT NULL CHECK (tipo IN ('INGRESO','EGRESO'))
  - `monto` REAL NOT NULL CHECK (monto > 0)
  - `frecuencia` TEXT NOT NULL (enum: ver seed)
  - `frecuencia_dias` INTEGER (solo para PERSONALIZADA)
  - `cuotas` INTEGER (cantidad total de pagos esperados, nullable)
  - `cuotas_confirmadas` INTEGER DEFAULT 0 (contador de movimientos confirmados)
  - `fecha_inicio` TEXT NOT NULL (formato YYYY-MM-DD)
  - `fecha_fin` TEXT (nullable, formato YYYY-MM-DD)
  - `categoria` TEXT NOT NULL
  - `observaciones` TEXT
  - `activo` INTEGER DEFAULT 1 (1=activo, 0=pausado)
  - `archivo_local_path` TEXT (adjunto: contrato PDF, etc.)
  - `archivo_remote_url` TEXT (URL en Supabase Storage)
  - `archivo_nombre` TEXT
  - `archivo_tipo` TEXT
  - `archivo_size` INTEGER
  - `dispositivo_id` TEXT (UUID del dispositivo origen)
  - `eliminado` INTEGER DEFAULT 0 (soft delete)
  - `sync_estado` TEXT DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE','SINCRONIZADA','ERROR'))
  - `created_ts` INTEGER NOT NULL
  - `updated_ts` INTEGER NOT NULL
- [x] Índices:
  - `idx_compromisos_unidad` ON (unidad_gestion_id, activo)
  - `idx_compromisos_tipo` ON (tipo, activo)
  - `idx_compromisos_sync` ON (sync_estado)
  - `idx_compromisos_eliminado` ON (eliminado, activo)
- [x] Validación CHECK: `fecha_fin >= fecha_inicio` (si no es NULL)

**Archivos modificados:**
- `lib/data/dao/db.dart`:
  - Tabla `compromisos` creada en `onCreate` (líneas ~280-335)
  - Tabla `compromisos` idempotente en `onUpgrade` (líneas ~410-420)
  - Método helper `ensureCompromisosTablas()` (líneas ~910-940)

#### 13.2: Seed de Frecuencias ✅ COMPLETADO
- [x] Crear tabla `frecuencias` (catálogo estático):
  - `codigo` TEXT PRIMARY KEY (MENSUAL, BIMESTRAL, etc.)
  - `descripcion` TEXT NOT NULL
  - `dias` INTEGER (para cálculos automáticos)
- [x] Seed inicial:
  - MENSUAL → 30 días
  - BIMESTRAL → 60 días
  - TRIMESTRAL → 90 días
  - CUATRIMESTRAL → 120 días
  - SEMESTRAL → 180 días
  - ANUAL → 365 días
  - UNICA → NULL (pago único)
  - PERSONALIZADA → NULL (requiere frecuencia_dias)

**Archivos modificados:**
- `lib/data/dao/db.dart`:
  - Tabla `frecuencias` creada en `onCreate` (líneas ~275-278)
  - Tabla `frecuencias` idempotente en `onUpgrade` (líneas ~405-408)
  - Método `_seedFrecuencias()` (líneas ~710-730)
  - Seed ejecutado en `onCreate` y `onUpgrade`

#### 13.3: Actualizar Tabla `evento_movimiento` ✅ COMPLETADO
- [x] Agregar columnas:
  - `compromiso_id` INTEGER (FK a compromisos, nullable)
  - `estado` TEXT DEFAULT 'CONFIRMADO' CHECK (estado IN ('ESPERADO','CONFIRMADO','CANCELADO'))
- [x] Migración idempotente:
  - Movimientos existentes (sin compromiso_id) → `estado='CONFIRMADO'`
- [x] Índice:
  - `idx_evento_mov_compromiso` ON (compromiso_id, estado)
  - `idx_evento_mov_estado` ON (estado, created_ts)

**Archivos modificados:**
- `lib/data/dao/db.dart`:
  - Campos agregados en `onCreate` (líneas ~235-265)
  - Columnas agregadas idempotentemente en `onUpgrade` (líneas ~500-510)
  - Método helper `ensureEventoMovimientoCompromisosColumns()` (líneas ~942-965)

#### 13.4: Servicio `CompromisosService` ✅ COMPLETADO
- [x] Crear `lib/features/shared/services/compromisos_service.dart`
- [x] Métodos CRUD básicos:
  - `crearCompromiso(...)` → insert con validaciones
  - `obtenerCompromiso(id)` → read
  - `listarCompromisos({unidadId, tipo, activo})` → list con filtros
  - `actualizarCompromiso(id, datos)` → update
  - `pausarCompromiso(id)` → set activo=0
  - `reactivarCompromiso(id)` → set activo=1
  - `desactivarCompromiso(id)` → set eliminado=1 (soft delete)
- [x] Métodos de cálculo:
  - `calcularProximoVencimiento(compromiso)` → DateTime?
  - `contarCuotasConfirmadas(compromiso)` → int
  - `calcularCuotasRestantes(compromiso)` → int? (cuotas - confirmadas)
- [x] Métodos adicionales:
  - `incrementarCuotasConfirmadas(id)` → actualiza contador
  - `listarVencimientosEnRango(desde, hasta)` → compromisos con vencimiento en período
  - `sincronizarCuotasConfirmadas(id)` → corrige inconsistencias
- [x] Validaciones:
  - No desactivar si tiene movimientos ESPERADOS pendientes
  - fecha_inicio <= fecha_fin
  - monto > 0
  - unidad_gestion_id existe y está activa
  - frecuencia existe en catálogo

**Archivos creados:**
- `lib/features/shared/services/compromisos_service.dart` (550 líneas)
  - Singleton con patrón `instance`
  - 14 métodos públicos
  - Validaciones completas
  - Manejo de errores con excepciones descriptivas
  - Documentación detallada en cada método

**Características implementadas:**
- CRUD completo con validaciones de negocio
- Cálculo dinámico de próximo vencimiento según frecuencia
- Contador automático de cuotas confirmadas
- Soporte para todas las frecuencias (MENSUAL, BIMESTRAL, TRIMESTRAL, etc.)
- Soft delete (nunca borrado físico)
- Actualización automática de sync_estado y updated_ts
- Filtros avanzados (unidad, tipo, activo/pausado)
- Listado de vencimientos por rango de fechas
- [ ] Crear `lib/features/shared/services/compromisos_service.dart`
- [ ] Métodos CRUD básicos:
  - `crearCompromiso(...)` → insert con validaciones
  - `obtenerCompromiso(id)` → read
  - `listarCompromisos({unidadId, tipo, activo})` → list con filtros
  - `actualizarCompromiso(id, datos)` → update
  - `pausarCompromiso(id)` → set activo=0
  - `reactivarCompromiso(id)` → set activo=1
  - `desactivarCompromiso(id)` → set eliminado=1 (soft delete)
- [ ] Métodos de cálculo:
  - `calcularProximoVencimiento(compromiso)` → Date
  - `contarCuotasConfirmadas(compromiso)` → int
  - `calcularCuotasRestantes(compromiso)` → int (cuotas - confirmadas)
- [ ] Validaciones:
  - No desactivar si tiene movimientos ESPERADOS pendientes
  - fecha_inicio <= fecha_fin
  - monto > 0
  - unidad_gestion_id existe y está activa

#### 13.5: Servicio `MovimientosProyectadosService` ✅ COMPLETADO
- [x] Crear `lib/features/shared/services/movimientos_proyectados_service.dart`
- [x] Método principal:
  - `calcularMovimientosEsperados(compromiso, fechaDesde, fechaHasta)` → List<MovimientoProyectado>
- [x] Lógica de proyección:
  - Partir de `fecha_inicio`
  - Generar vencimientos según `frecuencia` y `frecuencia_dias`
  - Filtrar por rango (fechaDesde, fechaHasta)
  - Limitar por `fecha_fin` (si existe) o `cuotas` (si existe)
  - Excluir vencimientos ya confirmados (consultar evento_movimiento)
  - Devolver objetos en memoria (NO insertar en DB)
- [x] Objeto `MovimientoProyectado` (modelo transient):
  - `compromiso_id`
  - `fecha_vencimiento`
  - `monto`
  - `numero_cuota` (si aplica)
  - `tipo`, `categoria`, `observaciones` (heredados del compromiso)
- [x] Métodos adicionales:
  - `calcularMovimientosEsperadosGlobal(fechaDesde, fechaHasta, {filtros})` → todos los compromisos
  - `calcularMovimientosEsperadosMes(year, month, {filtros})` → movimientos del mes
  - `calcularTotalEsperado(fechaDesde, fechaHasta)` → suma de montos por tipo
  - `tieneMovimientosEsperados(compromisoId)` → validación bool
- [x] Protecciones:
  - Loop infinito (máx 1000 iteraciones)
  - Comparación de fechas sin hora (solo día/mes/año)
  - Manejo de frecuencia UNICA (un solo vencimiento)

**Archivos creados:**
- `lib/features/shared/services/movimientos_proyectados_service.dart` (380 líneas)
  - Singleton con patrón `instance`
  - 8 métodos públicos
  - Clase `MovimientoProyectado` (modelo transient)
  - Documentación completa

**Características implementadas:**
- **Cálculo dinámico** de vencimientos sin persistir en DB
- **Exclusión automática** de vencimientos ya confirmados o cancelados
- **Soporte completo** para todas las frecuencias (8 tipos)
- **Filtros avanzados** por unidad, tipo, rango de fechas
- **Cálculo de totales** (ingresos, egresos, saldo esperado)
- **Validación** de movimientos esperados pendientes
- **Protección** contra loops infinitos
- **Comparación precisa** de fechas (sin hora)

**Algoritmo de proyección:**
```
1. Obtener compromiso y validar activo
2. Consultar movimientos existentes (CONFIRMADO/CANCELADO)
3. Extraer fechas para exclusión
4. Obtener frecuencia (días entre pagos)
5. Si UNICA: generar solo vencimiento en fecha_inicio
6. Si periódica: loop desde fecha_inicio
   - Validar fecha_fin
   - Validar cuotas
   - Validar rango solicitado
   - Excluir si ya existe
   - Agregar a lista
   - Avanzar según frecuencia
7. Retornar lista ordenada
```
- [ ] Crear `lib/features/shared/services/movimientos_proyectados_service.dart`
- [ ] Método principal:
  - `calcularMovimientosEsperados(compromiso, fechaDesde, fechaHasta)` → List<MovimientoProyectado>
- [ ] Lógica de proyección:
  - Partir de `fecha_inicio`
  - Generar vencimientos según `frecuencia` y `frecuencia_dias`
  - Filtrar por rango (fechaDesde, fechaHasta)
  - Limitar por `fecha_fin` (si existe) o `cuotas` (si existe)
  - Excluir vencimientos ya confirmados (consultar evento_movimiento)
  - Devolver objetos en memoria (NO insertar en DB)
- [ ] Objeto `MovimientoProyectado` (modelo transient):
  - `compromiso_id`
  - `fecha_vencimiento`
  - `monto`
  - `numero_cuota` (si aplica)
  - `tipo`, `categoria`, `observaciones` (heredados del compromiso)

#### 13.6: Tests Unitarios ✅ COMPLETADO
- [x] `test/compromisos_service_test.dart` creado con 28 tests (todos pasan)
  - CompromisosService - CRUD (11 tests):
    - Crear compromiso válido
    - Crear compromiso con cuotas
    - Validaciones (monto > 0, tipo válido, fechas, FK, frecuencia PERSONALIZADA)
    - Listar con filtros (unidad, tipo, activo)
    - Pausar/reactivar
    - Desactivar (soft delete)
    - Actualizar (marca sync_estado=PENDIENTE)
  - CompromisosService - Cálculos (5 tests):
    - Contar cuotas confirmadas
    - Calcular cuotas restantes
    - Calcular próximo vencimiento (MENSUAL, con movimiento previo)
    - Validaciones (pausado, cuotas completas)
  - MovimientosProyectadosService (12 tests):
    - Proyección MENSUAL (3 meses, algoritmo de días)
    - Excluir confirmados/cancelados
    - Respetar límites (cuotas, fecha_fin)
    - Frecuencia UNICA
    - Calcular global/por mes
    - Totales (ingresos, egresos, saldo)
    - Modelo MovimientoProyectado (toMap, descripcion)
    - Protección loop infinito (máx 1000)

**Comando**: `flutter test test/compromisos_service_test.dart`

---

### Fase 14 🚧 EN PROGRESO - UI Gestión de Compromisos

#### Objetivo
Crear las pantallas para administrar compromisos (listar, crear, editar, pausar, ver historial).

#### 14.1: Página `compromisos_page.dart` ✅ COMPLETADO
- [x] Crear `lib/features/tesoreria/pages/compromisos_page.dart`
- [x] Funcionalidades implementadas:
  - Listar compromisos activos de la unidad de gestión actual
  - Filtros: Tipo (Ingreso/Egreso/Todos), Estado (Activos/Pausados/Todos)
  - Vista de tabla Y vista de tarjetas (toggle funcional)
  - Columnas mostradas: Nombre, Tipo, Monto, Frecuencia, Próximo vencimiento, Cuotas, Estado, Acciones
  - Tap en fila → abrir `detalle_compromiso_page`
  - Pausar/reactivar compromiso directamente desde la lista
- [x] FAB "➕ Nuevo Compromiso" → `crear_compromiso_page`

#### 14.2: Página `crear_compromiso_page.dart` ✅ COMPLETADO
- [x] Crear `lib/features/tesoreria/pages/crear_compromiso_page.dart`
- [x] Formulario completo implementado:
  - Nombre (TextField con validación)
  - Tipo (Radio: Ingreso / Egreso)
  - Monto base (TextField numérico validado)
  - Frecuencia (Dropdown cargado desde DB: MENSUAL, BIMESTRAL, etc.)
  - Frecuencia personalizada (días) - solo si frecuencia=PERSONALIZADA
  - Cantidad de cuotas (TextField opcional)
  - Fecha de inicio (DatePicker)
  - Fecha de fin (DatePicker opcional con clear)
  - Unidad de gestión (Dropdown cargado desde DB)
  - Categoría (TextField opcional)
  - Observaciones (TextField multilinea opcional)
- [x] Validaciones implementadas:
  - Campos obligatorios (nombre, monto, tipo, frecuencia)
  - monto > 0
  - días > 0 si frecuencia PERSONALIZADA
  - fecha_inicio <= fecha_fin
- [x] Guardado funcional con CompromisosService
- [x] Navegación de vuelta a `compromisos_page`

#### 14.3: Página `detalle_compromiso_page.dart` ✅ COMPLETADO
- [x] Implementar vista completa con RefreshIndicator
- [x] Secciones implementadas:
  - **Información general:**
    - Nombre, Tipo, Monto, Frecuencia, Categoría
    - Fecha inicio, Fecha fin
    - Estado visual (Activo/Pausado/Desactivado) con chips de colores
    - Observaciones
  - **Estado del compromiso:**
    - Cuotas confirmadas de totales (o "Sin límite" si recurrente)
    - Cuotas restantes calculadas
    - Próximo vencimiento calculado dinámicamente
  - **Historial de movimientos:**
    - Lista completa de movimientos asociados (compromiso_id)
    - Estados: CONFIRMADO, ESPERADO, CANCELADO con badges
    - Tap en movimiento → `detalle_movimiento_page`
    - Mensaje si no hay movimientos registrados
- [x] Acciones en AppBar:
  - Editar (ícono lápiz) → `editar_compromiso_page`
  - Pausar/Reactivar (menú contextual)
  - Desactivar (menú contextual con confirmación)
- [x] Manejo de errores completo con logging
- [x] UX optimizada con estados de carga e indicadores visuales

#### 14.4: Página `editar_compromiso_page.dart` ✅ COMPLETADO
- [x] Crear `lib/features/tesoreria/pages/editar_compromiso_page.dart`
- [x] Formulario completo con validaciones:
  - Pre-carga de datos del compromiso existente
  - Información de solo lectura (ID, cuotas confirmadas, estado)
  - Campos editables: nombre, tipo, monto, frecuencia, cuotas, fechas, categoría, observaciones
  - Validaciones: monto > 0, fechas coherentes, frecuencia personalizada con días
- [x] Botón "GUARDAR" en AppBar
- [x] Actualización mediante `CompromisosService.actualizarCompromiso()`
- [x] Marca automática `sync_estado='PENDIENTE'` al guardar
- [x] Navegación de vuelta con confirmación de éxito
- [x] Manejo de errores con logging local

#### 14.5: Navegación e Integración ✅ COMPLETADO
- [x] Drawer de Tesorería:
  - Agregado ítem "Compromisos" con ícono `event_note`
  - Subtítulo "Obligaciones recurrentes"
  - Ubicación: entre Eventos y Configuración
- [x] `tesoreria_home_page.dart`:
  - Agregada tarjeta "Compromisos" en la página principal
  - Descripción: "Gestionar compromisos financieros"
  - Navegación funcional a `CompromisosPage`
- [x] Navegación completa implementada:
  - `TesoreriaHomePage` → `CompromisosPage`
  - `CompromisosPage` → `DetalleCompromisoPage` (tap en compromiso)
  - `CompromisosPage` → `CrearCompromisoPage` (FAB)
  - `DetalleCompromisoPage` → `EditarCompromisoPage` (botón editar)
  - `DetalleCompromisoPage` → `DetalleMovimientoPage` (tap en movimiento)
- [x] Sin errores de compilación, integración fluida

**Archivos creados/modificados:**
- `lib/features/tesoreria/pages/detalle_compromiso_page.dart` (446 líneas)
- `lib/features/tesoreria/pages/editar_compromiso_page.dart` (494 líneas - nuevo)
- `lib/features/tesoreria/pages/tesoreria_home_page.dart` (actualizado con navegación)

---

### Fase 15 ✅ COMPLETADA - Generación y Confirmación de Movimientos

**Completada el:** Enero 14, 2026

#### Objetivo
Calcular movimientos esperados dinámicamente y permitir su confirmación manual.

#### 15.1: ✅ Actualizar `movimientos_list_page.dart`
- ✅ Integrado `MovimientosProyectadosService`
- ✅ Al cargar lista del mes:
  - Consulta movimientos reales (tabla `evento_movimiento`)
  - Calcula movimientos esperados (de compromisos activos)
  - Combina ambas listas en orden cronológico
- ✅ Estilos diferenciados:
  - **CONFIRMADO:** estilo normal, fondo blanco
  - **ESPERADO:** fondo gris claro, ícono ⏳ pending, chip "ESPERADO" naranja
  - **CANCELADO:** incluido en filtros (texto tachado, fondo rojo claro)
- ✅ Filtro adicional por estado con SegmentedButton:
  - "Todos" (default)
  - "Confirmados"
  - "Esperados"
  - "Cancelados"
- ✅ Vista unificada mezclando movimientos cronológicamente
- ✅ Al tocar movimiento ESPERADO:
  - Navega a `confirmar_movimiento_page` con datos pre-cargados
- ✅ Long-press en movimiento ESPERADO:
  - Muestra diálogo de cancelación
  - Registra movimiento cancelado

#### 15.2: ✅ Página `confirmar_movimiento_page.dart`
- ✅ Creado `lib/features/tesoreria/pages/confirmar_movimiento_page.dart` (398 líneas)
- ✅ Recibe parámetros:
  - `compromisoId`
  - `fechaVencimiento` (sugerida)
  - `montoSugerido` (editable)
  - `tipo` (INGRESO/EGRESO)
  - `categoria`
- ✅ Formulario completo:
  - Fecha real (DatePicker, default: fecha_vencimiento)
  - Monto real (TextField, default: monto del compromiso)
  - Medio de pago (Dropdown desde metodos_pago)
  - Observaciones adicionales (TextArea)
  - Adjunto (camera/gallery con preview y límite 25MB)
- ✅ Al confirmar:
  - Insert en `evento_movimiento` con:
    - `compromiso_id`
    - `estado='CONFIRMADO'`
    - `sync_estado='PENDIENTE'`
  - Incrementa `cuotas_confirmadas` en tabla `compromisos`
  - Retorna a lista con recarga automática
- ✅ Validaciones:
  - Monto > 0
  - Medio de pago requerido
  - Límite de archivo 25MB

#### 15.3: ✅ Acción "Registrar pago/cobro" desde `detalle_compromiso_page`
- ✅ Botón verde con ícono en sección de estado
- ✅ Solo visible si:
  - Hay próximo vencimiento calculado
  - Compromiso activo (`activo=1`)
  - No eliminado (`eliminado=0`)
- ✅ Texto dinámico:
  - "Registrar cobro" para INGRESO
  - "Registrar pago" para EGRESO
- ✅ Navega a `confirmar_movimiento_page` con datos del compromiso
- ✅ Al regresar, recarga y actualiza vista del detalle

#### 15.4: ✅ Cancelar Movimientos Esperados
- ✅ Implementado en `movimientos_list_page`:
  - Long-press en tarjeta de movimiento ESPERADO
  - Muestra diálogo "¿Cancelar este pago/cobro?"
  - Al confirmar:
    - Insert en `evento_movimiento` con `estado='CANCELADO'`
    - Observación automática: "Movimiento esperado cancelado - Cuota X"
  - El movimiento ya no aparece como ESPERADO (excluido del cálculo)
  - Recarga automática de lista
- ✅ Hint visual en tarjeta: "Toque para confirmar • Mantenga presionado para cancelar"
- ✅ Feedback con SnackBar verde/rojo según resultado

#### 15.5: ✅ KPIs Actualizados en `movimientos_list_page`
- ✅ Balance del mes actual dividido:
  - **Saldo Real:** suma de movimientos CONFIRMADO
  - **Proyección:** suma de movimientos ESPERADO
- ✅ Muestra ambos separados en tarjetas distintas:
  - Tarjeta "Saldo Real" con totales de ingresos/egresos confirmados
  - Tarjeta "Proyección" con totales esperados
- ✅ Indicadores visuales:
  - Verde: ingresos confirmados/esperados
  - Rojo: egresos confirmados/esperados
  - Íconos diferenciados (check_circle vs pending)

#### 15.6: ✅ Pausar Compromiso y Ocultar Esperados
- ✅ Lógica implementada en `MovimientosProyectadosService`:
  - Filtra compromisos con `activo=1` y `eliminado=0`
  - Los compromisos pausados NO generan movimientos esperados
  - Al reactivar, vuelven a calcularse automáticamente
- ✅ Excluye movimientos CANCELADO de cálculos futuros

**Resumen de implementación:**
- ✅ Visualización dinámica de movimientos reales + esperados combinados
- ✅ Confirmación de movimientos esperados con formulario completo (vista tarjetas + tabla)
- ✅ Cancelación de movimientos esperados con auditoría
- ✅ KPIs separados para balances reales vs proyecciones
- ✅ Navegación integrada desde detalle de compromiso
- ✅ Validación de estados de compromiso (activo/pausado)
- ✅ Interacción completa en ambas vistas (tabla y tarjetas):
  - Tap en esperado → confirmar movimiento
  - Long-press en esperado → cancelar movimiento (solo tarjetas)

**Archivos creados/modificados:**
- `lib/features/tesoreria/pages/movimientos_list_page.dart` (1550 líneas - actualizado)
- `lib/features/tesoreria/pages/confirmar_movimiento_page.dart` (398 líneas - nuevo)
- `lib/features/tesoreria/pages/detalle_compromiso_page.dart` (563 líneas - actualizado)
- `lib/features/shared/services/movimiento_service.dart` (312 líneas - actualizado)

---
  - Volver a calcular movimientos esperados desde la fecha actual

---

### Fase 16 ⏳ EN PLANIFICACIÓN - Sincronización de Compromisos con Supabase

#### Objetivo
Sincronizar compromisos y sus adjuntos con Supabase para acceso desde múltiples dispositivos.

#### 16.1: Script SQL para Supabase ⏳ PENDIENTE
- [ ] Crear `tools/supabase_compromisos_schema.sql`
- [ ] Contenido:
  - Tabla `frecuencias` (catálogo estático, mismo seed que local)
  - Tabla `compromisos` (espejo de tabla local)
  - Índices: unidad_gestion_id, tipo, activo, sync_estado
  - Comentarios SQL explicativos
- [ ] Ejecutar en Supabase SQL Editor

#### 16.2: Bucket de Storage para Adjuntos de Compromisos ⏳ PENDIENTE
- [ ] Crear bucket `compromisos-adjuntos` en Supabase Dashboard:
  - Público: Sí
  - Tamaño máximo: 50MB
  - Tipos permitidos: `application/pdf,image/jpeg,image/png`
- [ ] Políticas de acceso público (sin autenticación):
  - INSERT: permitir subida
  - SELECT: permitir lectura
  - DELETE: permitir borrado (opcional)

#### 16.3: Actualizar `TesoreriaSyncService` ⏳ PENDIENTE
- [ ] Agregar métodos:
  - `syncCompromiso(int compromisoId)`
  - `syncCompromisosPendientes()`
  - `contarCompromisosPendientes()`
- [ ] Flujo de sincronización:
  1. Verificar conectividad
  2. Por cada compromiso pendiente:
     - Subir adjunto a `compromisos-adjuntos` (si existe)
     - Insert en tabla `compromisos` (insert-only, NO upsert)
     - Actualizar `archivo_remote_url` en local
     - Marcar `sync_estado='SINCRONIZADA'`
  3. Si falla:
     - Marcar `sync_estado='ERROR'`
     - Registrar en `sync_outbox` y `sync_error_log`

#### 16.4: UI de Sincronización ⏳ PENDIENTE
- [ ] `compromisos_page.dart`:
  - Botón "Sincronizar" en AppBar (con badge de pendientes)
  - Modal de progreso durante sync
  - Modal de resultado (éxitos/errores)
  - Badges visuales por compromiso (PENDIENTE/SINCRONIZADA/ERROR)
- [ ] `detalle_compromiso_page.dart`:
  - Botón "Sincronizar" individual (si pendiente)
  - Indicador de estado de sync en información general

#### 16.5: Validación Contra Duplicados ⏳ PENDIENTE
- [ ] Antes de sincronizar:
  - Generar hash único del compromiso (nombre + unidad + fecha_inicio)
  - Consultar Supabase si ya existe
  - Si existe: mostrar error "Compromiso ya sincronizado"
  - NO permitir re-subida

#### 16.6: Tests de Sincronización ⏳ PENDIENTE
- [ ] `test/compromisos_sync_test.dart`:
  - Estructura de servicio singleton
  - Contar pendientes sin errores
  - Verificar conectividad
  - (Sincronización real requiere Supabase configurado)

#### 16.7: Documentación de Setup ⏳ PENDIENTE
- [ ] Actualizar `SUPABASE_TESORERIA_SETUP.md`:
  - Sección "Compromisos"
  - Instrucciones para ejecutar `supabase_compromisos_schema.sql`
  - Instrucciones para crear bucket `compromisos-adjuntos`
  - Consultas útiles (listar compromisos, resumen por unidad, etc.)

---

## 🎯 Resumen de Fases de Compromisos

| Fase | Objetivo | Componentes Principales |
|------|----------|------------------------|
| **13** | Modelo de datos | Tablas, servicios, lógica de proyección |
| **14** | UI de gestión | Pantallas CRUD, navegación, filtros |
| **15** | Confirmación | Calcular esperados, registrar reales, KPIs |
| **16** | Sincronización | Supabase, Storage, validaciones |

---

## 🚧 Consideraciones Técnicas

### Reglas de Negocio (NO negociables)
1. **Compromiso ≠ Movimiento:** Un compromiso es una obligación, un movimiento es un hecho.
2. **Solo CONFIRMADO impacta balances:** Movimientos ESPERADO son informativos.
3. **Soft delete:** Compromisos nunca se eliminan físicamente (`eliminado=1`).
4. **El pasado no se recalcula:** Ediciones solo afectan períodos futuros.
5. **Usuario confirma todo:** No hay generación automática de movimientos en DB.
6. **Auditable:** Cada movimiento conoce su origen (`compromiso_id`).
7. **Claridad visual:** UI diferencia claramente real vs esperado.

### Cálculo de Movimientos Esperados (Opción B - Dinámico)
- NO se insertan en `evento_movimiento` hasta confirmar
- Se calculan on-demand al consultar un período
- Ventajas:
  - Flexibilidad total al editar compromisos
  - No consume espacio innecesario
  - No requiere proceso de recalcular periódicamente
- Algoritmo:
  1. Obtener compromisos activos (`activo=1`, `eliminado=0`)
  2. Por cada compromiso:
     - Calcular vencimientos según frecuencia
     - Filtrar por rango de fechas solicitado
     - Excluir vencimientos ya confirmados (consultar DB)
     - Limitar por `fecha_fin` o `cuotas`
  3. Devolver objetos en memoria (no persistir)

### Adjuntos en Compromisos
- Similar a movimientos de tesorería
- Bucket separado: `compromisos-adjuntos`
- Tipos permitidos: PDF, imágenes (contratos, acuerdos)
- Tamaño máximo: 50MB (mayor que movimientos por ser documentos legales)

### Sincronización Multi-Dispositivo
- Los compromisos se crean en cualquier dispositivo
- Al sincronizar, se suben a Supabase
- Otros dispositivos NO los descargan automáticamente (por ahora)
- Futuro (con roles): permitir descargar compromisos de otras unidades

### Fuera de Alcance (Fases Futuras)
- ❌ Generación automática de movimientos en DB
- ❌ Recordatorios/notificaciones de vencimientos
- ❌ Presupuestos anuales
- ❌ Dashboard financiero avanzado
- ❌ Roles y permisos (se implementará después)
- ❌ Descarga de compromisos desde Supabase
- ❌ Reportes de flujo de caja proyectado

---

**Estado:** ✅ Fase 14 COMPLETADA - UI Gestión de Compromisos (14.1-14.5 ✅ Completadas)
**Última actualización:** Enero 14, 2026

### Resumen de Logros - Fase 14:
- ✅ **compromisos_page.dart**: Lista con filtros, tabla/tarjetas, pausar/reactivar
- ✅ **crear_compromiso_page.dart**: Formulario completo con todas las validaciones
- ✅ **detalle_compromiso_page.dart**: Vista completa con historial de movimientos
- ✅ **editar_compromiso_page.dart**: Edición funcional con pre-carga de datos
- ✅ **Navegación integrada**: Drawer, home, y flujos entre pantallas
- ✅ **Sin errores**: Todas las páginas compilando correctamente
- ✅ **UX profesional**: RefreshIndicator, estados de carga, confirmaciones, badges visuales
