# Captura de Errores - Módulo de Tesorería

## Implementación completada ✅

### 1. Servicio de manejo de errores (`ErrorHandler`)
Archivo: `lib/features/shared/services/error_handler.dart`

Funcionalidades:
- Captura automática de errores con guardado en BD local
- Mensajes amigables para el usuario
- Soporte para SnackBar y diálogos modales
- Helper `execute()` para operaciones con manejo automático de errores

### 2. Integración en Tesorería

#### Páginas actualizadas:
- **crear_movimiento_page.dart**: Manejo de errores en creación/edición de movimientos
- **crear_compromiso_page.dart**: Manejo de errores en creación de compromisos
- **tesoreria_home_page.dart**: Opción de ver logs de errores (funciones avanzadas)

#### Visualización de errores:
- Se agregó opción "Logs de errores" en el drawer de Tesorería
- Solo visible cuando "Funciones avanzadas" está activada en configuración
- Usa la pantalla compartida `ErrorLogsPage`

### 3. Base de datos
La tabla `app_error_log` ya existe en `db.dart` con los siguientes campos:
- `id`: identificador único
- `scope`: contexto del error (ej: 'tesoreria.crear_movimiento')
- `message`: mensaje del error
- `stacktrace`: traza del stack
- `payload`: datos adicionales en JSON
- `created_ts`: fecha y hora

Funciones disponibles:
- `AppDatabase.logLocalError()`: guardar error
- `AppDatabase.ultimosErrores()`: leer errores
- `AppDatabase.clearErrorLogs()`: limpiar logs

## Uso del ErrorHandler

### Opción 1: Manejo manual
```dart
try {
  await operacionRiesgosa();
} catch (e, st) {
  await ErrorHandler.instance.handle(
    scope: 'tesoreria.crear_movimiento',
    error: e,
    stackTrace: st,
    context: context,
    userMessage: 'No se pudo crear el movimiento',
    showDialog: true, // o false para SnackBar
  );
}
```

### Opción 2: Ejecutar con manejo automático
```dart
final resultado = await ErrorHandler.instance.execute(
  scope: 'tesoreria.crear_movimiento',
  context: context,
  userMessage: 'No se pudo crear el movimiento',
  operation: () async {
    return await service.crearMovimiento(...);
  },
);
```

## Activar visualización de logs

1. Ir a Configuración (Buffet o Tesorería)
2. Activar "Funciones avanzadas"
3. Volver al menú principal
4. Aparecerá la opción "Logs de errores" 🐛

## Scopes recomendados

### Tesorería:
- `tesoreria.crear_movimiento`
- `tesoreria.editar_movimiento`
- `tesoreria.eliminar_movimiento`
- `tesoreria.cargar_movimientos`
- `tesoreria.crear_compromiso`
- `tesoreria.editar_compromiso`
- `tesoreria.generar_cuotas`

### Buffet:
- `buffet.abrir_caja`
- `buffet.cerrar_caja`
- `buffet.crear_venta`
- `buffet.anular_venta`
- `buffet.imprimir`

### General:
- `sync.envio`
- `sync.descarga`
- `db.migracion`

## Beneficios

1. **Para el usuario**: Mensajes claros y amigables sin detalles técnicos
2. **Para el desarrollador**: Trazabilidad completa de errores con contexto
3. **Para soporte**: Logs exportables para debugging remoto
4. **Para la app**: No se rompe ante errores inesperados

## Próximos pasos recomendados

1. Aplicar `ErrorHandler` en más pantallas de Tesorería:
   - `movimientos_list_page.dart`
   - `compromisos_page.dart`
   - `categorias_movimiento_page.dart`
   
2. Agregar logging en servicios críticos:
   - `CompromisosService`
   - `EventoMovimientoService`
   - `SupaSyncService`

3. Implementar purga automática de logs antiguos (ya existe `purgeOldErrorLogs()`)
