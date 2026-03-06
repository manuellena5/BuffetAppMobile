# TODO — Módulo Tesorería (Planificación Marzo 2026)

> Este archivo es la lista de trabajo priorizada para llevar el módulo de Tesorería
> a un nivel de calidad profesional. Actualizar conforme se avance.

---

## ✅ FASE A — HOTFIX BUGS CRÍTICOS (COMPLETADA — 2026-03-03)

- [x] **A.1** — Agregar `unidad_gestion_id` al CREATE TABLE de `evento_movimiento` en db.dart
- [x] **A.2** — Pasar `unidadGestionId` a `ReporteCategoriasService` desde `reporte_categorias_page.dart`
- [x] **A.3** — Corregir `verificarIntegridad` en `transferencia_service.dart` (soportar 2-4 movimientos con comisiones)
- [x] **A.4** — Cambiar `MovimientoService.eliminar` a soft delete (`eliminado=1`)
- [x] **A.5** — Tests de regresión para los 4 fixes (parcial: A.3 cubierto en transferencia_service_test + fase_22_test)
  - ⚠️ Nota: `CajaMovimientoService.eliminar` (buffet) sigue usando hard delete — verificar si es intencional

---

## ✅ FASE B — SOLIDEZ Y CALIDAD (COMPLETADA — 2026-03-03)

- [x] **B.1** — Error handling completo en `movimientos_proyectados_service.dart` (0% → 100%)
- [x] **B.2** — Error handling completo en `saldo_inicial_service.dart` (0% → 100%)
- [x] **B.3** — Error handling faltante en `compromisos_service.dart` (~50% → 100%)
- [x] **B.4** — Error handling faltante en `plantel_service.dart` (~30% → 100%)
- [x] **B.5** — Reemplazar `$e` por mensajes amigables en páginas (incluye `detalle_compromiso_page`, `editar_compromiso_page`, `unidad_gestion_selector_page`)
- [x] **B.6** — Resolver N+1 en `calcularResumenGeneral` (PlantelService) — JOIN batch
- [x] **B.7** — Resolver N+1 en `obtenerResumenMensual` (ReporteResumenService) — GROUP BY
- [x] **B.8** — Integrar `SaldoInicialService` con `ReporteResumenService` (eliminar TODO saldo=0)
- [x] **B.9** — Fix `_loading` y `_loadVersion` en `tesoreria_home_page.dart` (loading indicator + initState)
- [x] **B.10** — Tests de `PlantelService` ⚠️ Pendiente: no existe `plantel_service_test.dart` — crear cuando se trabaje plantel

---

## ✅ FASE C — COMPLETAR FASE 21 (COMPLETADA — 2026-03-03)

- [x] **C.1** — 21.2: Correcciones en categorías de movimientos
- [x] **C.2** — 21.3: Adjuntos PDF en movimientos
- [x] **C.3** — 21.4: Responsive en páginas de cuentas
- [x] **C.4** — 21.5: Carrusel de meses en detalle de cuenta
- [x] **C.5** — 21.6: Comisión en transferencias (3 movimientos)
- [x] **C.6** — 21.7: Modal editable para comisión
- [x] **C.7** — 21.8: Editar movimiento desde detalle
- [x] **C.8** — 21.9: Mejoras acuerdos grupales paso 4
- [x] **C.9** — 21.10: Preview acuerdos grupales paso 5

---

## ✅ FASE D — REPORTES Y DASHBOARDS (COMPLETADA — 2026-03-03)

- [x] **D.1** — Selector de año en reporte resumen mensual (carrusel con flechas + botón "Hoy")
- [x] **D.2** — Completar reporte plantel mensual + detalle por entidad (fix bug doble acumulación pagado/pendiente)
- [x] **D.3** — Generación PDF reporte mensual (nuevo `ReportePdfService` + botón PDF en AppBar)
- [x] **D.4** — Generación PDF reporte por categorías (botón PDF + KPIs en encabezado)
- [x] **D.5** — Generación PDF reporte plantel mensual (botón PDF en AppBar)
- [x] **D.6** — Dashboard visual con gráficos (nueva `DashboardPage`: torta egresos, barras evolución, línea saldo)
- [x] **D.7** — Indicadores de vencimiento en home (badge rojo + `contarVencidos()` + `contarProximosAVencer()` en service)

---

## ✅ FASE E — PRESUPUESTO Y PROYECCIÓN (COMPLETADA — 2026-03-03)

- [x] **E.1** — Nueva tabla `presupuesto_anual` (DB v22, migración idempotente, índices)
- [x] **E.2** — Pantalla `presupuesto_page.dart` — CRUD de partidas presupuestarias (crear, editar, soft-delete, filtro por tipo, KPIs)
- [x] **E.3** — Comparativa presupuesto vs ejecución: `comparativa_presupuesto_page.dart` + método `comparativaVsEjecucion()` en `PresupuestoService`
- [x] **E.4** — Flujo de caja proyectado: `ProyeccionFlujoService` (saldo actual + compromisos esperados + presupuesto como fallback)
- [x] **E.5** — Pantalla `proyeccion_flujo_page.dart` con tabla, gráfico lineal (fl_chart), selector horizonte 3/6/12 meses, KPIs

---

## 🔄 FASE F — SINCRONIZACIÓN COMPLETA (Prioridad: Baja-Media)

- [ ] **F.1-F.4** — Esquemas Supabase para compromisos, acuerdos, cuentas, plantel
- [ ] **F.5-F.8** — Servicios de sync para cada entidad (insert-only)
- [ ] **F.9** — Eliminar upsert en syncUnidadGestion
- [ ] **F.10** — Pantalla unificada "Pendientes de sincronizar"
- [ ] **F.11** — Tests end-to-end de sync
- [ ] **F.12** — Retry con backoff exponencial

---

## ✅ FASE G — DRAWER COMPLETO (COMPLETADA — 2026-03-03)

- [x] **G.1** — Fix crítico: 9 items del drawer no verificaban `isDrawerFixed` antes de `Navigator.pop()`, causando pantallas negras con drawer fijo
- [x] **G.2** — Fix deprecados: `withOpacity` → `withValues(alpha:)` en `custom_drawer.dart` (3) y `tesoreria_home_page.dart` (3)
- [x] **G.3** — Limpieza código muerto: `_appVersion` + import `app_version.dart` eliminados de `tesoreria_home_page.dart`
- [x] **G.4** — Nuevo item "Dashboard" en `TesoreriaDrawerHelper` (icono `Icons.dashboard`, color indigo, ruta `/dashboard`)
- [x] **G.5** — Tarjeta "Dashboard" agregada en `tesoreria_home_page.dart` (acceso rápido desde la home)
- [x] **G.6** — Todos los 15 items del drawer verifican `isDrawerFixed` (drawer fijo funciona correctamente)
- [x] **G.7** — `flutter analyze` 0 issues, 55 tests pasando

---

## ♻️ FASE H — CÓDIGO LIMPIO ✅ COMPLETADA

- [x] **H.1** — Extension `SafeMap` para casteos seguros de DB (`lib/domain/safe_map.dart`)
- [x] **H.2** — Refactorizar servicios para usar SafeMap (acuerdos_service, compromisos_service, export_service)
- [x] **H.3** — Extender clase `Format` (porcentaje, parseFecha)
- [x] **H.4** — Unificar `Format.money()` — funciones legacy marcadas `@Deprecated`
- [x] **H.5** — Paginación real SQL en `movimientos_list_page` con `PaginationControls`
- [x] **H.6** — Transacción atómica `confirmarCuota()` (INSERT mov + UPDATE cuota + counter)
- [x] **H.7** — Limpieza deuda `medio_pago_id` (quitar bifurcaciones, simplificar _onOpen)

---

## 🔧 FASE I — MEJORAS UX Y NAVEGACIÓN ✅ COMPLETADA

- [x] **I.1** — Movimientos: mostrar siempre el mes en curso al abrir (no restaurar mes de sesiones previas)
- [x] **I.2** — Movimientos: tarjetas centradas con `maxWidth: 700` (no ocupar todo el ancho)
- [x] **I.3** — Movimientos tabla: `showCheckboxColumn: false`, click en fila esperada → detalle/confirmar
- [x] **I.4** — Crear movimiento: categoría con `Autocomplete` (tipear + buscar + dropdown con código)
- [x] **I.5** — Compromisos: `Align(topCenter)` + `ConstrainedBox` + `showCheckboxColumn: false`
- [x] **I.6** — TesoreriaScaffold: botón volver (`leading`) visible cuando drawer fijo y `Navigator.canPop`
- [x] **I.7** — Plantel: `Align(topCenter)` + `ConstrainedBox(maxWidth: 1000)` + padding propio

## ✨ FASE J — EMPTY STATES + SKELETON LOADING ✅ COMPLETADA

Widgets reutilizables `EmptyState` y `SkeletonLoader` (con shimmer puro, sin dependencias externas).

- [x] **J.1** — Widget `EmptyState` reutilizable (`lib/features/shared/widgets/empty_state.dart`)
- [x] **J.2** — Widget `SkeletonLoader` reutilizable con variantes `.list()`, `.cards()`, `.table()`, `.custom()` (`lib/features/shared/widgets/skeleton_loader.dart`)
- [x] **J.3** — Aplicado en `movimientos_list_page` (cards skeleton + empty state con subtítulo)
- [x] **J.4** — Aplicado en `compromisos_page` (table skeleton + empty state)
- [x] **J.5** — Aplicado en `plantel_page` (cards skeleton + empty state con botón acción)
- [x] **J.6** — Aplicado en `dashboard_page` (cards skeleton + error state con reintentar)
- [x] **J.7** — Aplicado en 13 pantallas adicionales:
  - `acuerdos_page`, `categorias_movimiento_page`, `detalle_movimientos_entidad_page`
  - `detalle_acuerdo_page`, `comparativa_presupuesto_page`, `reporte_plantel_mensual_page`
  - `configurar_saldo_inicial_page`, `detalle_compromiso_page`, `detalle_jugador_page`
  - `gestionar_jugadores_page`, `presupuesto_page`, `proyeccion_flujo_page`
  - `reporte_categorias_page`, `reporte_resumen_anual_page`, `reporte_resumen_mensual_page`
  - `saldos_iniciales_list_page`, `tesoreria_home_page`

---

## �🔍 BRECHAS VS COMPETENCIA (To Fix)

| Brecha | Fase que la resuelve | Prioridad |
|---|---|---|
| No hay Presupuesto Anual | ~~Fase E~~ ✅ Resuelto | ~~Media~~ |
| No hay Flujo de Caja Proyectado | ~~Fase E~~ ✅ Resuelto | ~~Media~~ |
| No hay Reportes PDF exportables | ~~Fase D~~ ✅ Resuelto | ~~Media-Alta~~ |
| No hay Dashboard visual con gráficos | ~~Fase D~~ ✅ Resuelto | ~~Media~~ |
| No hay Notificaciones de vencimiento | ~~Fase D~~ ✅ Resuelto (badge) | ~~Media~~ |
| Edición de movimientos no implementada | ~~Fase C (21.8)~~ ✅ Resuelto | ~~Alta~~ |
| Sincronización solo cubre 1/10 entidades | Fase F | Baja-Media |

## ✅ VENTAJAS COMPETITIVAS (Mantener)

- Offline-first real (ningún competidor lo tiene)
- Acuerdos con generación automática de compromisos
- Comisiones bancarias semiautomáticas
- Categorías customizables con iconos
- Adjuntos fotográficos en cancha
- Acuerdos grupales para plantel completo
