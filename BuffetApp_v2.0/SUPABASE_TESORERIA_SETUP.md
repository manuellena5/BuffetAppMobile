# Instrucciones de Configuración - Supabase Tesorería

## 📋 Resumen

Este documento explica cómo actualizar tu base de datos Supabase para soportar la sincronización de datos de Tesorería desde BuffetApp.

## 🎯 Qué Necesitas Agregar

Tu esquema actual de Supabase está casi completo. Solo faltan **2 tablas** para Tesorería:

1. **`unidades_gestion`** - Unidades organizativas (disciplinas, comisiones, eventos)
2. **`evento_movimiento`** - Movimientos financieros de tesorería (ingresos/egresos)

## 🚀 Pasos de Instalación

### 1. Acceder al SQL Editor de Supabase

1. Ingresá a tu proyecto en [Supabase Dashboard](https://app.supabase.com)
2. En el menú lateral, hacé click en **"SQL Editor"**
3. Hacé click en **"New Query"**

### 2. Ejecutar el Script

1. Abrí el archivo `tools/supabase_tesoreria_schema.sql`
2. Copiá **TODO** el contenido
3. Pegalo en el SQL Editor de Supabase
4. Hacé click en **"Run"** (▶️)

### 3. Verificar la Instalación

Ejecutá esta consulta para verificar que las tablas se crearon correctamente:

```sql
-- Verificar tabla unidades_gestion
SELECT * FROM public.unidades_gestion ORDER BY id;

-- Verificar tabla evento_movimiento (debería estar vacía)
SELECT COUNT(*) FROM public.evento_movimiento;

-- Verificar índices
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND tablename IN ('unidades_gestion', 'evento_movimiento')
ORDER BY tablename, indexname;
```

**Resultado esperado:**
- 8 unidades de gestión insertadas (Fútbol Mayor, Infantil, Vóley, Patín, etc.)
- 0 movimientos (tabla vacía)
- 5 índices creados

### 4. Configurar Supabase Storage (para adjuntos) 🔴 OBLIGATORIO

⚠️ **Este paso es OBLIGATORIO** para que la sincronización funcione correctamente.

Para que los archivos adjuntos (comprobantes) funcionen:

#### 4.1. Crear el Bucket

1. En el menú lateral de Supabase Dashboard, andá a **"Storage"**
2. Hacé click en **"Create a new bucket"**
3. Configurá:
   - **Name:** `movimientos-adjuntos` (exactamente así, sin mayúsculas)
   - **Public bucket:** ✅ **SÍ** (marcado)
   - **File size limit:** `26214400` (25 MB en bytes)
   - **Allowed MIME types:** Dejar en blanco o poner `image/jpeg,image/png,image/jpg`
4. Hacé click en **"Create bucket"**

#### 4.2. Configurar Políticas de Acceso (Sin Autenticación)

Como la app NO usa autenticación, necesitás permitir acceso público.

En el SQL Editor, ejecutá:

```sql
-- Permitir subida pública de archivos
CREATE POLICY "Permitir subida de adjuntos"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'movimientos-adjuntos');

-- Permitir lectura pública de archivos
CREATE POLICY "Permitir lectura de adjuntos"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'movimientos-adjuntos');

-- Permitir borrado (opcional, por si necesitás limpiar)
CREATE POLICY "Permitir borrado de adjuntos"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'movimientos-adjuntos');
```

#### 4.3. Verificar Storage

Ejecutá en SQL Editor:

```sql
SELECT * FROM storage.buckets WHERE name = 'movimientos-adjuntos';
```

**Resultado esperado:** 1 fila con:
- `name`: `movimientos-adjuntos`
- `public`: `true`

### 5. Verificar Políticas de Storage (Opcional)

```sql
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd
FROM pg_policies 
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
ORDER BY policyname;
```

**Resultado esperado:** 3 políticas para el bucket `movimientos-adjuntos`

## 📊 Estructura de las Tablas

### `unidades_gestion`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| id | integer | ID único (1-8 para seed) |
| nombre | text | Nombre de la unidad (ej: "Fútbol Mayor") |
| tipo | text | DISCIPLINA / COMISION / EVENTO |
| disciplina_ref | text | Referencia al deporte (FUTBOL, VOLEY, etc) |
| activo | integer | 1=activo, 0=inactivo |
| created_ts | bigint | Timestamp de creación (epoch ms) |
| updated_ts | bigint | Timestamp de modificación (epoch ms) |

### `evento_movimiento`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| id | bigserial | ID autoincremental |
| evento_id | uuid | Referencia al evento (nullable) |
| disciplina_id | integer | Referencia a disciplina (obligatorio) |
| tipo | text | INGRESO / EGRESO |
| categoria | text | Categoría del movimiento |
| monto | double | Monto del movimiento (>0) |
| medio_pago_id | integer | Referencia a método de pago |
| observacion | text | Observaciones opcionales |
| archivo_local_path | text | Path local del adjunto |
| archivo_remote_url | text | URL en Supabase Storage |
| archivo_nombre | text | Nombre del archivo adjunto |
| archivo_tipo | text | MIME type del archivo |
| archivo_size | bigint | Tamaño en bytes |
| eliminado | integer | 0=activo, 1=eliminado (soft delete) |
| dispositivo_id | uuid | ID del dispositivo origen |
| sync_estado | text | PENDIENTE / SINCRONIZADA / ERROR |
| created_ts | bigint | Timestamp de creación (epoch ms) |
| updated_ts | bigint | Timestamp de modificación (epoch ms) |

## 🔍 Consultas Útiles

### Ver movimientos por unidad de gestión

```sql
SELECT 
  em.id,
  em.tipo,
  em.monto,
  em.categoria,
  ug.nombre as unidad,
  mp.descripcion as medio_pago,
  to_timestamp(em.created_ts/1000) as fecha
FROM public.evento_movimiento em
JOIN public.unidades_gestion ug ON em.disciplina_id = ug.id
JOIN public.metodos_pago mp ON em.medio_pago_id = mp.id
WHERE em.eliminado = 0
ORDER BY em.created_ts DESC
LIMIT 50;
```

### Resumen por unidad y tipo

```sql
SELECT 
  ug.nombre as unidad,
  em.tipo,
  COUNT(*) as cantidad,
  SUM(em.monto) as total
FROM public.evento_movimiento em
JOIN public.unidades_gestion ug ON em.disciplina_id = ug.id
WHERE em.eliminado = 0
GROUP BY ug.nombre, em.tipo
ORDER BY ug.nombre, em.tipo;
```

### Ver movimientos con adjuntos

```sql
SELECT 
  em.id,
  em.tipo,
  em.monto,
  em.archivo_nombre,
  em.archivo_remote_url,
  em.archivo_size
FROM public.evento_movimiento em
WHERE em.archivo_remote_url IS NOT NULL
  AND em.eliminado = 0
ORDER BY em.created_ts DESC;
```

## ⚠️ Consideraciones Importantes

### Compatibilidad con Buffet

- Las tablas de Buffet (caja_diaria, ventas, tickets) **NO se tocan**
- Tesorería y Buffet comparten catálogos (metodos_pago, disciplinas)
- Tesorería usa `evento_movimiento`, Buffet usa `caja_movimiento`

### Política de Sincronización

- **Insert-only:** La app NO hace UPDATE ni DELETE en Supabase
- **Sin duplicados:** La app valida antes de sincronizar (por código único)
- **Manual:** El usuario decide cuándo sincronizar (botón en la app)
- **Reintentos:** Si falla, se marca como ERROR y se puede reintentar

### Timestamps

- Usamos **epoch en milisegundos** (igual que SQLite local)
- Formato: `(extract(epoch from now())*1000)::bigint`
- Para mostrar en formato legible: `to_timestamp(created_ts/1000)`

### Soft Delete

- `eliminado = 0`: Registro activo
- `eliminado = 1`: Registro eliminado (no se muestra en la app)
- Los registros eliminados **nunca se borran físicamente**

## 📞 Próximos Pasos

Una vez ejecutado el script:

1. ✅ Verificá que las tablas se crearon
2. ✅ Verificá que los seeds se insertaron (8 unidades de gestión)
3. ✅ Creá el bucket de Storage `movimientos-adjuntos` (OBLIGATORIO)
4. ✅ Configurá las políticas de acceso público al bucket
5. ✅ Verificá que el bucket esté público y acepte archivos
6. 🚀 Probá la sincronización manual desde la app móvil

## 🧪 Probar la Sincronización

Después de configurar todo:

1. En la app móvil, andá a **Tesorería**
2. Creá un movimiento de prueba (con o sin adjunto)
3. Hacé click en el botón **"Sincronizar"** (☁️) en la lista de movimientos
4. Verificá que se suba correctamente
5. En Supabase, verificá:

```sql
-- Ver último movimiento sincronizado
SELECT * FROM public.evento_movimiento 
ORDER BY created_ts DESC 
LIMIT 1;

-- Si tiene adjunto, verificá el archivo en Storage
SELECT * FROM storage.objects 
WHERE bucket_id = 'movimientos-adjuntos' 
ORDER BY created_at DESC 
LIMIT 5;
```

## 🐛 Solución de Problemas

### Error: "relation already exists"

Es normal, significa que ya ejecutaste el script. Las tablas no se duplican.

### Error: "foreign key constraint"

Verificá que las tablas de referencia existan:
- `disciplinas`
- `metodos_pago`
- `eventos`

### Seed no se insertó

Ejecutá manualmente:

```sql
INSERT INTO public.unidades_gestion (id, nombre, tipo, disciplina_ref, activo)
VALUES (1, 'Fútbol Mayor', 'DISCIPLINA', 'FUTBOL', 1)
ON CONFLICT (id) DO NOTHING;
-- Repetir para las demás unidades...
```

---

**Última actualización:** Enero 14, 2026  
**Fase:** 12 - Sincronización Tesorería con Supabase
