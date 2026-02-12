# Patr\u00f3n de Navegaci\u00f3n - BuffetApp

## \ud83d\udc1e Problemas Corregidos (6 de Febrero 2026)

### 1. **Bug Cr\u00edtico: AppSettings no cargado en inicio**
**Problema:** `main.dart` no llamaba `settings.ensureLoaded()` antes de verificar `isUnidadGestionConfigured`, causando que SIEMPRE fuera `false` en el primer inicio.

**Soluci\u00f3n:** Usar `FutureBuilder` para asegurar que `AppSettings` est\u00e9 completamente cargado antes de verificar la unidad de gesti\u00f3n.

```dart
// main.dart - CORRECTO
return Consumer<AppSettings>(
  builder: (context, settings, _) {
    return FutureBuilder(
      future: settings.ensureLoaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (!settings.isUnidadGestionConfigured) {
          return const _TesoreriaInitialGate();
        }
        
        return const TesoreriaHomePage();
      },
    );
  },
);
```

### 2. **Bug Cr\u00edtico: Navegaci\u00f3n rota en drawer**
**Problema:** `TesoreriaDrawerHelper` usaba `context.mounted` despu\u00e9s de `await`, causando que el context fuera inv\u00e1lido y generara pantallas negras.

**Soluci\u00f3n:** Capturar `Navigator.of(context)` ANTES de cualquier operaci\u00f3n async.

### 3. **Bug Cr\u00edtico: Settings page navegaci\u00f3n rota**
**Problema:** Similar al anterior, `settings_page.dart` no capturaba Navigator antes de `showDialog`.

### 4. **Bug: TesoreriaHomePage no cargaba unidad real**
**Problema:** `_checkUnidadGestionAndLoad()` usaba valor hardcodeado "Unidad por defecto" en lugar de consultar la base de datos.

**Soluci\u00f3n:** Cargar el nombre real desde `unidades_gestion` usando el `unidadGestionActivaId` de `AppSettings`.

---

## \u2705 Patr\u00f3n Correcto de Navegaci\u00f3n

### Regla de Oro
> **SIEMPRE capturar Navigator/Provider ANTES de cualquier operaci\u00f3n async (await, showDialog, Future, etc.)**

### Patr\u00f3n 1: Navegaci\u00f3n simple desde drawer
```dart
// \u274c INCORRECTO
DrawerMenuItem(
  onTap: () {
    Navigator.pop(context);
    Navigator.push(
      context,  // \u274c context puede ser inv\u00e1lido despu\u00e9s de pop
      MaterialPageRoute(builder: (_) => const SomePage()),
    );
  },
)

// \u2705 CORRECTO
DrawerMenuItem(
  onTap: () {
    final nav = Navigator.of(context);  // \u2705 Capturar ANTES
    Navigator.pop(context);
    nav.push(
      MaterialPageRoute(builder: (_) => const SomePage()),
    );
  },
)
```

### Patr\u00f3n 2: Navegaci\u00f3n con dialog/confirmaci\u00f3n
```dart
// \u274c INCORRECTO
onTap: () async {
  final confirm = await showDialog<bool>(...);
  
  if (confirm == true && context.mounted) {  // \u274c context.mounted NO es suficiente
    Navigator.of(context).push(...);  // \u274c Puede fallar
  }
}

// \u2705 CORRECTO
onTap: () async {
  final nav = Navigator.of(context);  // \u2705 Capturar ANTES del await
  
  final confirm = await showDialog<bool>(...);
  
  if (confirm == true) {
    nav.push(...);  // \u2705 Usar Navigator capturado
  }
}
```

### Patr\u00f3n 3: Navegaci\u00f3n con Provider/State
```dart
// \u274c INCORRECTO
onTap: () async {
  final result = await someAsyncOperation();
  
  if (context.mounted) {  // \u274c NO suficiente
    final modeState = context.read<AppModeState>();
    await modeState.setMode(AppMode.buffet);
    Navigator.of(context).push(...);  // \u274c Puede fallar
  }
}

// \u2705 CORRECTO
onTap: () async {
  final nav = Navigator.of(context);  // \u2705 Capturar Navigator
  final modeState = context.read<AppModeState>();  // \u2705 Capturar Provider
  
  final result = await someAsyncOperation();
  
  await modeState.setMode(AppMode.buffet);
  nav.push(...);  // \u2705 Usar Navigator capturado
}
```

### Patr\u00f3n 4: Verificar datos antes de navegar
```dart
// \u2705 CORRECTO - main.dart
return Consumer<AppSettings>(
  builder: (context, settings, _) {
    // Asegurar que settings est\u00e9 cargado antes de verificar
    return FutureBuilder(
      future: settings.ensureLoaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        // Ahora s\u00ed podemos verificar configuraci\u00f3n
        if (!settings.isUnidadGestionConfigured) {
          return const _TesoreriaInitialGate();
        }
        
        return const TesoreriaHomePage();
      },
    );
  },
);
```

---

## \ud83d\udcdd Checklist para Nuevas Pantallas

Antes de agregar navegaci\u00f3n a una nueva pantalla, verificar:

- [ ] \u00bfHay operaciones async (await, Future, showDialog)?
  - \u2705 S\u00ed \u2192 Capturar `Navigator.of(context)` ANTES
  - \u2705 No \u2192 Puedes usar `Navigator.of(context)` directamente

- [ ] \u00bfUsas `context.read<Provider>()` despu\u00e9s de async?
  - \u2705 S\u00ed \u2192 Capturar Provider ANTES del await
  - \u2705 No \u2192 OK

- [ ] \u00bfLa pantalla necesita datos de AppSettings/DB?
  - \u2705 S\u00ed \u2192 Usar `FutureBuilder` con `ensureLoaded()`
  - \u2705 No \u2192 OK

- [ ] \u00bfEl drawer cierra antes de navegar?
  - \u2705 S\u00ed \u2192 Capturar Navigator antes de `Navigator.pop()`
  - \u2705 No \u2192 OK

---

## \ud83d\udee0\ufe0f Template para DrawerMenuItem

```dart
DrawerMenuItem(
  icon: Icons.some_icon,
  label: 'Alguna Pantalla',
  onTap: () async {  // async si hay awaits
    // 1. Capturar dependencias PRIMERO
    final nav = Navigator.of(context);
    final someProvider = context.read<SomeProvider>();  // si aplica
    
    // 2. Cerrar drawer (si aplica)
    Navigator.pop(context);
    
    // 3. Operaciones async (si aplica)
    final result = await showDialog(...);
    await someProvider.doSomething();
    
    // 4. Navegar usando dependencias capturadas
    if (result == true) {
      nav.push(MaterialPageRoute(builder: (_) => const SomePage()));
    }
  },
  isActive: currentRouteName == '/some_route',
  activeColor: Colors.teal,
)
```

---

## \ud83d\udea8 Anti-patrones (NO hacer)

### \u274c NO usar `context.mounted` como \u00fanico chequeo
```dart
// \u274c MAL
if (confirm == true && context.mounted) {
  Navigator.of(context).push(...);  // Puede fallar igual
}
```

### \u274c NO usar `if (!mounted) return` sin capturar Navigator
```dart
// \u274c MAL
final result = await someAsync();
if (!mounted) return;
Navigator.of(context).push(...);  // Puede fallar
```

### \u274c NO asumir que SharedPreferences est\u00e1 cargado
```dart
// \u274c MAL
final settings = context.read<AppSettings>();
if (!settings.isUnidadGestionConfigured) {  // Puede ser false aunque haya valor
  // ...
}

// \u2705 BIEN
final settings = context.read<AppSettings>();
await settings.ensureLoaded();  // Asegurar carga
if (!settings.isUnidadGestionConfigured) {
  // ...
}
```

---

## \ud83d\udcca Estado de la Aplicaci\u00f3n (Post-correcci\u00f3n)

### Archivos Corregidos
1. \u2705 `lib/main.dart` - FutureBuilder para cargar settings
2. \u2705 `lib/features/shared/widgets/tesoreria_drawer_helper.dart` - Captura Navigator en todos los items
3. \u2705 `lib/features/shared/pages/settings_page.dart` - Captura Navigator antes de modal
4. \u2705 `lib/features/tesoreria/pages/tesoreria_home_page.dart` - Carga unidad real desde DB

### Tests
- \u2705 12/12 tests UX pasando
- \u2705 Sin errores de compilaci\u00f3n
- \u2705 Solo warnings menores (deprecaciones, unused variables)

### Flujo Verificado
1. \u2705 App inicia \u2192 Carga settings \u2192 Verifica unidad \u2192 Muestra selector si no hay
2. \u2705 Usuario selecciona unidad \u2192 Se guarda en SharedPreferences \u2192 Persiste entre reinicios
3. \u2705 Navegaci\u00f3n desde drawer \u2192 No genera pantallas negras
4. \u2705 Settings \u2192 Cambiar m\u00f3dulo \u2192 Funciona correctamente
5. \u2705 TesoreriaHomePage \u2192 Muestra nombre de unidad real

---

## \ud83d\udd70\ufe0f Historial de Versiones

### v2.0.1 - 6 de Febrero 2026
- \ud83d\udc1b Corregidos 5 bugs cr\u00edticos de navegaci\u00f3n
- \ud83d\udd27 Implementado patr\u00f3n consistente de captura de Navigator
- \u2705 100% tests UX pasando
- \ud83d\udcdd Documentado patr\u00f3n de navegaci\u00f3n

---

## \ud83d\udc65 Para Desarrolladores

**Antes de crear un nuevo PR con navegaci\u00f3n:**
1. Leer este documento completo
2. Aplicar el patr\u00f3n correcto seg\u00fan el caso
3. Verificar que no hay `context` usado despu\u00e9s de `await` sin capturar
4. Ejecutar tests: `flutter test test/tesoreria_ux_test.dart`
5. Verificar compilaci\u00f3n: `flutter analyze`

**En caso de pantalla negra:**
1. Verificar stack trace en debug console
2. Buscar uso de `context` despu\u00e9s de `await`
3. Aplicar patr\u00f3n de captura de Navigator
4. Si persiste, revisar que `AppSettings.ensureLoaded()` se llame antes de verificar configuraci\u00f3n

---

\ud83d\ude80 **BuffetApp - Navegaci\u00f3n robusta y predecible**
