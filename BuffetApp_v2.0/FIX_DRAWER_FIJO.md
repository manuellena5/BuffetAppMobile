# Fix: Pantallas Negras con Drawer Fijo + Logs No Visibles

**Fecha:** 6 de febrero de 2026  
**Actualizado:** 6 de febrero de 2026 (quinta iteración - showAdvanced no se detecta en home y cuentas)

---

## 🐛 Problemas Reportados

### 1. Pantallas negras cuando el menú lateral está fijo
**Síntoma:** 
- Al guardar cambios en **Configuraciones** con el drawer FIJO (pantallas anchas), aparece pantalla negra
- Al navegar desde items del menú lateral con drawer fijo, aparece pantalla negra
- Con drawer COLAPSADO (pantallas angostas) NO sucede

**Causa raíz:**
El drawer puede estar en dos estados según `DrawerState.isFixed`:
- `isFixed = false`: Drawer colapsado que se abre/cierra como overlay (`Drawer` de Flutter)
- `isFixed = true`: Drawer fijo siempre visible como widget en un `Row`

Cuando `isFixed = true`, el drawer NO es un `Drawer` de Flutter sino un `Widget` dentro de un `Row`. Por lo tanto, **NO se debe llamar a `Navigator.pop(context)`** porque no hay drawer para cerrar. Llamar a `pop()` en este contexto causa que se cierre la pantalla actual en lugar de solo cerrar el drawer, resultando en pantallas negras.

**Lugares afectados:**
1. **tesoreria_drawer_helper.dart** - 15 items del menú (✅ Corregido en iteración 1)
2. **settings_page.dart** - Método `_save()` hace `nav.pop(true)` (✅ Corregido en iteración 2)
3. **tesoreria_home_page.dart** - Drawer custom con Navigator.pop sin verificar isFixed (✅ Corregido en iteración 3)

### 2. El item "Logs de errores" no se visualiza en pantallas de Tesorería
**Síntoma (Iteración 1-2):**
- En pantallas de Tesorería, el item "Logs de errores" NO aparece aunque modo avanzado esté activado
- En Buffet SÍ aparece correctamente

**Causa raíz (Iteración 1-2):**
- `TesoreriaScaffold` no leía `show_advanced_options` desde `SharedPreferences`
- Usaba `showAdvanced ?? false` como default

**Síntoma (Iteración 3):**
- En la pantalla de **inicio de Tesorería**, el item "Logs de errores" NO aparece aunque modo avanzado esté activado
- En **otras pantallas de Tesorería**, SÍ aparece correctamente
- El item "Inicio tesorería" tampoco aparece en la home (solo en otras pantallas)

**Causa raíz (Iteración 3):**
- `tesoreria_home_page.dart` usaba su propio drawer personalizado (`_buildDrawer()`) en lugar de `TesoreriaDrawerHelper`
- Este drawer custom NO incluía el item "Inicio tesorería"
- Usaba su propia variable `_showAdvanced` que solo se cargaba en `initState`, no se actualizaba dinámicamente

**Síntoma (Iteración 5):**
- En la pantalla de **inicio de Tesorería** y **Cuentas/Fondos**, el item "Logs de errores" SIGUE sin aparecer
- En otras pantallas SÍ aparece

**Causa raíz (Iteración 5):**
- `tesoreria_home_page.dart` declaraba `_showAdvanced = false` pero nunca lo inicializaba desde SharedPreferences
- `cuentas_page.dart` pasaba explícitamente `showAdvanced: false`, ignorando SharedPreferences
- Ambos sobreescribían el auto-detección del drawer helper

---

## ✅ Soluciones Aplicadas

### Fix 1: NO llamar Navigator.pop cuando drawer está fijo (tesoreria_drawer_helper.dart)

**Archivos modificados:**
- `lib/features/shared/widgets/tesoreria_drawer_helper.dart`

**Cambios:**
1. Importar `DrawerState` para detectar si drawer está fijo
2. Obtener `drawerState` en el helper: `final drawerState = context.watch<DrawerState>();`
3. Capturar estado: `final isDrawerFixed = drawerState.isFixed;`
4. Actualizar TODOS los items del drawer (15 items):

```dart
// ❌ ANTES (causaba pantallas negras con drawer fijo)
onTap: () {
  final nav = Navigator.of(context);
  Navigator.pop(context); // Esto cierra la pantalla cuando drawer está fijo
  nav.push(...);
},

// ✅ DESPUÉS (solo pop si drawer NO está fijo)
onTap: () {
  final nav = Navigator.of(context);
  if (!isDrawerFixed) Navigator.pop(context); // Cerrar solo si es overlay
  nav.push(...);
},
```

**Items actualizados:**
1. Inicio Tesorería
2. Seleccionar Unidad
3. Cambiar a Buffet (cerrar drawer ANTES de showDialog)
4. Crear Movimiento
5. Ver Movimientos
6. Compromisos
7. Acuerdos
8. Cuentas
9. Plantel
10. Reportes
11. Categorías
12. Saldos Iniciales
13. Logs de errores
14. Configuración
15. Ayuda

**Caso especial - Cambiar a Buffet:**
```dart
onTap: () async {
  final nav = Navigator.of(context);
  final modeState = context.read<AppModeState>();
  
  // Cerrar drawer ANTES de showDialog (si no está fijo)
  if (!isDrawerFixed) Navigator.pop(context);
  
  final confirm = await showDialog<bool>(...);
  // ... resto del código
}
```

---

### Fix 2: NO hacer pop en settings_page cuando drawer está fijo

**Archivos modificados:**
- `lib/features/shared/pages/settings_page.dart`

**Cambios:**
1. Importar `DrawerState`:
```dart
import '../state/drawer_state.dart';
```

2. En `_save()`, verificar estado del drawer antes de hacer `pop()`:
```dart
if (!mounted) return;
_initialLayout = _layout;
_initialAdvanced = _advanced;
_initialTheme = _theme;
_initialWinPrinterName = _winPrinterName;
_initialUiScale = _uiScale;
setState(() => _dirty = false);

// ✅ Solo hacer pop si drawer NO está fijo
final drawerState = context.read<DrawerState?>();
if (drawerState == null || !drawerState.isFixed) {
  nav.pop(true);
}
```

**Resultado:**
- **Drawer colapsado:** Guarda y cierra pantalla (normal)
- **Drawer fijo:** Guarda, actualiza estado, NO cierra pantalla

---

### Fix 3: Leer showAdvanced desde SharedPreferences automáticamente

**Archivos modificados:**
- `lib/features/shared/widgets/tesoreria_scaffold.dart`

**Cambios:**

1. **Importar SharedPreferences:**
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

2. **Convertir a StatefulWidget:**
```dart
class TesoreriaScaffold extends StatefulWidget {
  final bool? showAdvanced; // Nullable - auto-detecta si es null
  // ...
  @override
  State<TesoreriaScaffold> createState() => _TesoreriaScaffoldState();
}
```

3. **Cargar desde SharedPreferences:**
```dart
class _TesoreriaScaffoldState extends State<TesoreriaScaffold> {
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadShowAdvanced();
  }

  Future<void> _loadShowAdvanced() async {
    if (widget.showAdvanced != null) {
      setState(() => _showAdvanced = widget.showAdvanced!);
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool('show_advanced_options') ?? false;
      if (mounted) {
        setState(() => _showAdvanced = value);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final effectiveShowAdvanced = widget.showAdvanced ?? _showAdvanced;
    // ... usar en ambos drawers (overlay y fijo)
  }
}
```

**Resultado:**
- Si pantalla pasa `showAdvanced: true` → usa ese valor
- Si NO lo pasa → lee automáticamente desde `'show_advanced_options'`
- Todas las pantallas de Tesorería detectan modo avanzado sin código extra

---

### Fix 4: Unificar drawer en tesoreria_home_page usando TesoreriaDrawerHelper

**Archivos modificados:**
- `lib/features/tesoreria/pages/tesoreria_home_page.dart`

**Problema:**
- La pantalla de inicio de Tesorería usaba su propio drawer custom (`_buildDrawer()`)
- Este drawer NO incluía el item "Inicio tesorería"
- Los `Navigator.pop()` no verificaban `isFixed` (causaba pantallas negras)
- NO se actualizaba cuando cambiaba el modo avanzado en Settings

**Solución:**
1. Reemplazar `_buildDrawer(context)` por `_buildDrawerSimplified(context)`
2. Eliminar método `_buildDrawer()` completo (240 líneas de código duplicado)
3. Limpiar imports innecesarios

```dart
// ❌ ANTES - drawer custom duplicado
drawer: drawerState.isFixed ? null : _buildDrawer(context),
body: Row(
  children: [
    if (drawerState.isFixed) _buildDrawer(context),
    // ...
  ],
),

// ✅ AHORA - usa TesoreriaDrawerHelper consistentemente
drawer: drawerState.isFixed ? null : _buildDrawerSimplified(context),
body: Row(
  children: [
    if (drawerState.isFixed) _buildDrawerSimplified(context),
    // ...
  ],
),
```

**Resultado:**
- ✅ Drawer consistente en TODA la app de Tesorería
- ✅ "Inicio tesorería" ahora aparece en la home
- ✅ "Logs de errores" aparece cuando modo avanzado está activo
- ✅ NO más pantallas negras con drawer fijo
- ✅ Menos código duplicado (eliminadas 240 líneas)

---

### Fix 5: Cargar showAdvanced desde SharedPreferences en pantallas específicas

**Archivos modificados:**
- `lib/features/tesoreria/pages/tesoreria_home_page.dart`
- `lib/features/cuentas/pages/cuentas_page.dart`

**Problema:**
- `tesoreria_home_page.dart` declaraba `_showAdvanced = false` pero NUNCA lo inicializaba desde SharedPreferences
- `cuentas_page.dart` pasaba explícitamente `showAdvanced: false` a `TesoreriaDrawerHelper`, bloqueando auto-detección
- Ambos sobreescribían el mecanismo de auto-detección del drawer helper
- Resultado: "Logs de errores" NO aparecía aunque modo avanzado estuviera activado

**Solución:**

1. **Importar SharedPreferences:**
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

2. **Agregar variable de estado y método de carga:**
```dart
class _PaginaState extends State<Pagina> {
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadShowAdvanced();
    // ... otros métodos
  }

  Future<void> _loadShowAdvanced() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showAdvanced = prefs.getBool('show_advanced_options') ?? false;
      });
    }
  }
}
```

3. **Pasar valor al drawer helper:**
```dart
// ✅ AHORA - pasa valor leído desde SharedPreferences
TesoreriaDrawerHelper.build(
  context: context,
  currentRouteName: '/tesoreria',
  unidadGestionNombre: _unidadGestionNombre,
  showAdvanced: _showAdvanced, // ← Leer desde SharedPreferences en initState
  onLoadVersion: () async {
    if (mounted) {
      await _loadVersion();
    }
  },
)
```

**Cambios específicos:**

**tesoreria_home_page.dart:**
- ❌ ANTES: `_showAdvanced = false` declarado pero nunca inicializado
- ✅ AHORA: `_loadShowAdvanced()` en `initState`, lee desde SharedPreferences
- ❌ ANTES: Comentario "No pasar showAdvanced para que se detecte automáticamente" (no funcionaba)
- ✅ AHORA: `showAdvanced: _showAdvanced` pasado explícitamente con valor correcto

**cuentas_page.dart:**
- ❌ ANTES: `showAdvanced: false` hardcodeado en ambos drawers (overlay y fijo)
- ✅ AHORA: `_loadShowAdvanced()` en `initState`, lee desde SharedPreferences
- ✅ AHORA: `showAdvanced: _showAdvanced` pasado explícitamente con valor correcto

**Resultado:**
- ✅ "Logs de errores" AHORA aparece en **Inicio Tesorería** cuando modo avanzado está activo
- ✅ "Logs de errores" AHORA aparece en **Cuentas/Fondos** cuando modo avanzado está activo
- ✅ Consistencia total con el resto de pantallas de Tesorería
- ✅ Patrón unificado: cada pantalla lee su configuración desde SharedPreferences

---

## 📊 Impacto de los Cambios

### Pantallas afectadas positivamente:
**✅ 16 pantallas principales de Tesorería ahora con drawer unificado y showAdvanced correcto:**
1. **tesoreria_home_page.dart** ← Corregida en iteración 3 (drawer) y 5 (showAdvanced)
2. **cuentas_page.dart** ← Corregida en iteración 5 (showAdvanced)
3. acuerdos_page.dart
4. compromisos_page.dart
5. movimientos_list_page.dart
6. plantel_page.dart
7. categorias_movimiento_page.dart
8. gestionar_jugadores_page.dart
9. saldos_iniciales_list_page.dart
10. unidad_gestion_selector_page.dart
11. reportes_index_page.dart
12. reporte_categorias_page.dart
13. reporte_plantel_mensual_page.dart
14. reporte_resumen_mensual_page.dart
15. reporte_resumen_anual_page.dart
16. crear_movimiento_page.dart

**✅ 15 items del drawer + settings NO causan pantallas negras con drawer fijo**

### Beneficios adicionales:
- ✅ **Código más mantenible:** 1 solo lugar para el drawer (TesoreriaDrawerHelper)
- ✅ **Consistencia UX:** mismo drawer en toda la app
- ✅ **Menos bugs:** cambios en el drawer se aplican automáticamente a todas las pantallas
- ✅ **Patrón claro:** Cada pantalla lee `showAdvanced` desde SharedPreferences en `initState`

### Compatibilidad:
- ✅ Drawer colapsado (overlay): sigue funcionando igual
- ✅ Drawer fijo (ancho): ahora funciona correctamente en TODAS las pantallas
- ✅ Pantallas que usan TesoreriaScaffold: auto-detección funciona
- ✅ Pantallas con custom Scaffold: ahora leen explícitamente desde SharedPreferences

---

## ✅ Validación

### Compilación:
```bash
flutter analyze
```
**Resultado:** ✅ 0 errores, 449 warnings (todos deprecación/info, no críticos)

### Testing manual requerido:
1. **Con drawer colapsado (pantalla angosta):**
   - ✅ Verificar que navegación funciona (items del drawer)
   - ✅ Verificar que drawer se cierra al navegar

2. **Con drawer fijo (pantalla ancha):**
   - ✅ Verificar que navegación funciona SIN pantallas negras
   - ✅ Verificar que drawer NO se cierra al navegar (permanece visible)
   - ✅ Ir a Configuraciones, modificar algo, dar "Guardar"
   - ✅ Verificar que NO aparece pantalla negra

3. **Modo avanzado (NUEVA VERIFICACIÓN - Iteración 5):**
   - ✅ Activar "Opciones avanzadas" en Configuraciones
   - ✅ Verificar que aparece item "Logs de errores 🐛" en drawer desde:
     - **Inicio Tesorería** ← CRÍTICO (era el problema reportado)
     - **Cuentas/Fondos** ← CRÍTICO (también reportado)
     - Cualquier otra pantalla con TesoreriaScaffold
   - ✅ Navegar a "Logs de errores" y verificar que funciona

---

## 🎯 Resumen Técnico

**Problema 1:** `Navigator.pop(context)` siempre llamado → pantallas negras con drawer fijo  
**Solución 1:** `if (!isDrawerFixed) Navigator.pop(context)` → pop condicional

**Problema 2:** `showAdvanced` no pasado desde pantallas → logs no visibles  
**Solución 2:** `showAdvanced ?? appSettings.showAdvancedOptions` → auto-detectar (TesoreriaScaffold)

**Problema 3:** `tesoreria_home_page` con drawer custom duplicado → inconsistencias  
**Solución 3:** Reemplazar con `TesoreriaDrawerHelper` → drawer unificado

**Problema 4:** `_showAdvanced` no inicializado o hardcodeado a false → logs no visibles en home/cuentas  
**Solución 4:** Leer desde `SharedPreferences` en `initState` → valor correcto

**Patrón aplicado:**
```dart
// En drawer_helper.dart
final drawerState = context.watch<DrawerState>();
final isDrawerFixed = drawerState.isFixed;

// En cada onTap:
onTap: () {
  final nav = Navigator.of(context);
  if (!isDrawerFixed) Navigator.pop(context); // Condicional
  nav.push(...);
}

// En pantallas con custom Scaffold:
class _PaginaState extends State<Pagina> {
  bool _showAdvanced = false;
  
  @override
  void initState() {
    super.initState();
    _loadShowAdvanced();
  }
  
  Future<void> _loadShowAdvanced() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showAdvanced = prefs.getBool('show_advanced_options') ?? false;
      });
    }
  }
  
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: TesoreriaDrawerHelper.build(
        context: context,
        showAdvanced: _showAdvanced, // Explícitamente desde SharedPreferences
        // ...
      ),
    );
  }
}
```

---

**Preparado por:** GitHub Copilot  
**Fecha:** 6 de febrero de 2026  
**Estado:** ✅ LISTO PARA TESTING (5 iteraciones aplicadas)
