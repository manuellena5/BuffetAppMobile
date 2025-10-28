# Configuración de Supabase (sincronización en la nube)

Esta app puede sincronizar cierres de caja y sus items a una base en la nube usando Supabase (Postgres + REST). La DB local (SQLite) sigue siendo la fuente principal; la nube es un espejo para reportes/backup.

## Qué se necesita

- Una cuenta en Supabase
- Un proyecto creado (gratis alcanza)
- URL del proyecto (https://XXXX.supabase.co)
- Clave Anónima (anon key) del proyecto
- Tablas creadas con el esquema del repositorio (ver `installer/supabase_schema.sql`).

## Cómo decirle a la app tus credenciales

La app busca primero en su archivo de configuración de usuario y, si no encuentra valores, usa variables de entorno:

1) Archivo de configuración (recomendado)
- Ruta: `%LOCALAPPDATA%\BuffetApp\config.json`
- Abrilo con el Bloc de notas y agregá/ajustá estos campos:

```json
{
  "supabase_url": "https://TU-PROYECTO.supabase.co",
  "supabase_anon_key": "TU-ANON-KEY"
}
```

Guardá el archivo y abrí la app (o cerrá/abrí la ventana de Herramientas si ya está abierta).

2) Variables de entorno (alternativa rápida)
- En PowerShell (solo para la sesión actual):

```powershell
$env:SUPABASE_URL = "https://TU-PROYECTO.supabase.co"
$env:SUPABASE_ANON_KEY = "TU-ANON-KEY"
```

- Permanentes (Windows): Panel de Control > Sistema > Configuración avanzada del sistema > Variables de entorno… > Variables de usuario: agregar `SUPABASE_URL` y `SUPABASE_ANON_KEY`.

Notas:
- Si están presentes en `config.json`, tienen prioridad sobre las variables de entorno.
- La ruta de `config.json` se crea automáticamente si no existe.

## Probar la sincronización

- Opción 1: Cerrar una caja. Al finalizar, la app pregunta si querés sincronizar ahora; aceptá y revisá el resumen.
- Opción 2: Menú Herramientas > "Sincronizar datos con la nube". Se abrirá un modal con barra de progreso y, al terminar, verás un resumen por caja:
  - Código de caja, tickets subidos, items, productos creados en nube y el UUID de trazabilidad.

Si no hay cajas pendientes, te lo va a informar.

## Validación de productos

Antes de subir los items, la app verifica que todos los productos usados existan en Supabase por su `codigo_producto`:
- Los faltantes se crean automáticamente con `nombre` y `precio_venta` tomados de la venta local.
- El matcheo actual es por código; en caso de nombres iguales pero códigos diferentes se consideran distintos productos.

## Errores frecuentes y solución

- "Supabase no está configurado": faltan `supabase_url`/`supabase_anon_key` en `config.json` y/o en el entorno.
- 401/403 al sincronizar: revisá la anon key y que sea del proyecto correcto.
- POST/GET 404: revisá que creaste las tablas con `installer/supabase_schema.sql`.
- Timeout: verificá tu conexión a internet.

## Dónde se almacenan los cambios

- SQLite local nunca se borra. Al sincronizar:
  - Se marca la caja como enviada (`nube_enviado=1`, `nube_uuid=<uuid>`, `enviado_nube_ts=<fecha>`)
  - Se suben la cabecera (`cajas`) y los items (`caja_items`) a Supabase.

## Cómo desactivar la nube

- Borrá o dejá en blanco `supabase_url` y `supabase_anon_key` en `config.json`.
- O eliminá las variables de entorno `SUPABASE_URL` y `SUPABASE_ANON_KEY`.

---
Sugerencia: mantené un backup local automático (Botón "Backup Local") y usá la sincronización como respaldo adicional en la nube.
