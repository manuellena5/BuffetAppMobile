# Fix: Error al guardar movimiento con archivo adjunto

## Problema Identificado

Al intentar guardar un movimiento con imagen adjunta, ocurría un error de INSERT en la tabla `evento_movimiento`. 

**Causa raíz:** Las nuevas columnas para archivos adjuntos (`archivo_local_path`, `archivo_remote_url`, `archivo_nombre`, `archivo_tipo`, `archivo_size`) no existían en las bases de datos ya creadas con versión 7.

## Solución Implementada

### 1. Incrementar versión de DB (v7 → v8)
**Archivo:** `lib/data/dao/db.dart`
```dart
version: 8,  // Antes era 7
```

Esto fuerza la ejecución de `onUpgrade` en instalaciones existentes, agregando las columnas de archivo.

### 2. Test de Integración
**Archivo:** `test/movimiento_con_adjunto_test.dart`

Creados 2 tests para verificar:
- ✅ Insert de movimiento CON archivo adjunto
- ✅ Insert de movimiento SIN archivo adjunto (columnas en null)

### 3. Limpieza de código
Removidos:
- Import no usado de `format.dart`
- Variable `_attachmentData` no utilizada

## Resultado

✅ **24/24 tests pasando**  
✅ **0 errores de compilación**

## Instrucciones para Testing Manual

1. **Limpiar datos de app existente** (si ya tenías versión 7):
   - Android: Desinstalar y reinstalar la app
   - Desktop: Eliminar archivo `barcancha.db` en:
     - Windows: `%LOCALAPPDATA%\Buffet_App\barcancha.db`
     - Linux/Mac: `~/Documents/barcancha.db`

2. **Probar adjuntar archivo:**
   - Ir a Tesorería → Cargar Movimiento
   - Click en "Adjuntar comprobante"
   - Seleccionar imagen de galería o tomar foto
   - Completar formulario y guardar
   - Verificar que se guarda sin errores
   - En lista de movimientos, verificar badge "Tiene adjunto"

## Columnas de Base de Datos

```sql
CREATE TABLE evento_movimiento (
  ...
  archivo_local_path TEXT,
  archivo_remote_url TEXT,
  archivo_nombre TEXT,
  archivo_tipo TEXT,
  archivo_size INTEGER,
  ...
);
```

Todas las columnas son **nullable** para permitir movimientos sin adjunto.
