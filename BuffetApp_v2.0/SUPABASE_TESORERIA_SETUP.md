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
**Fase 20:** Gestión de Cuentas de Fondos

---

## 📦 FASE 20: Gestión de Cuentas de Fondos

### 🎯 Nuevas Tablas Requeridas

Para soportar la gestión de cuentas (bancos, billeteras digitales, cajas, inversiones), necesitás agregar:

1. **`cuentas_fondos`** - Definición de cuentas (bancos, billeteras, cajas físicas, inversiones)
2. **Modificar `evento_movimiento`** - Agregar columnas `cuenta_id`, `es_transferencia`, `transferencia_id`

### 🚀 Script de Instalación Fase 20

En el SQL Editor de Supabase, ejecutá:

```sql
-- ============================================
-- FASE 20: CUENTAS DE FONDOS
-- ============================================

-- 1. Crear tabla cuentas_fondos
CREATE TABLE IF NOT EXISTS public.cuentas_fondos (
    id SERIAL PRIMARY KEY,
    unidad_gestion_id INTEGER NOT NULL REFERENCES public.unidades_gestion(id) ON DELETE RESTRICT,
    nombre TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('BANCO', 'BILLETERA', 'CAJA', 'INVERSION')),
    saldo_inicial NUMERIC(10, 2) NOT NULL DEFAULT 0,
    tiene_comision BOOLEAN NOT NULL DEFAULT FALSE,
    comision_porcentaje NUMERIC(5, 2),
    banco_nombre TEXT,
    cbu_alias TEXT,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    observaciones TEXT,
    archivo_local_path TEXT,
    archivo_remote_url TEXT,
    archivo_nombre TEXT,
    archivo_tipo TEXT,
    archivo_size INTEGER,
    dispositivo_id TEXT,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE,
    sync_estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (sync_estado IN ('PENDIENTE', 'SINCRONIZADA', 'ERROR')),
    created_ts BIGINT NOT NULL,
    updated_ts BIGINT NOT NULL
);

-- Índices para cuentas_fondos
CREATE INDEX IF NOT EXISTS idx_cuentas_fondos_unidad ON public.cuentas_fondos(unidad_gestion_id);
CREATE INDEX IF NOT EXISTS idx_cuentas_fondos_tipo ON public.cuentas_fondos(tipo);
CREATE INDEX IF NOT EXISTS idx_cuentas_fondos_activo ON public.cuentas_fondos(activo) WHERE eliminado = FALSE;

-- 2. Modificar evento_movimiento (agregar columnas)
ALTER TABLE public.evento_movimiento
  ADD COLUMN IF NOT EXISTS cuenta_id INTEGER REFERENCES public.cuentas_fondos(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS es_transferencia INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS transferencia_id TEXT;

-- Índices para las nuevas columnas
CREATE INDEX IF NOT EXISTS idx_evento_movimiento_cuenta ON public.evento_movimiento(cuenta_id);
CREATE INDEX IF NOT EXISTS idx_evento_movimiento_transferencia ON public.evento_movimiento(transferencia_id) WHERE es_transferencia = 1;

-- 3. Actualizar CHECK de categorías de evento_movimiento (agregar nuevas categorías)
-- Primero, eliminar el constraint viejo si existe
ALTER TABLE public.evento_movimiento DROP CONSTRAINT IF EXISTS evento_movimiento_categoria_check;

-- Agregar nuevo constraint con las categorías actualizadas
ALTER TABLE public.evento_movimiento
  ADD CONSTRAINT evento_movimiento_categoria_check CHECK (
    categoria IN (
      -- Ingresos existentes
      'CUOTA_SOCIO', 'BONO_CONTRIBUCION', 'ALQUILER_CANCHA', 
      'SPONSORS', 'SORTEOS', 'EVENTOS_ESPECIALES', 'OTROS_ING',
      -- Egresos existentes
      'SUELDOS_CUERPO_TECNICO', 'PAGO_PROVEEDORES', 'INSUMOS_DEPORT', 
      'MANTENIMIENTO', 'GASTOS_VARIOS', 'SERVICIOS', 'ARBITRAJES_JUECES',
      -- NUEVAS (FASE 20)
      'TRANSFERENCIA',   -- Transferencia entre cuentas
      'COM_BANC',        -- Comisión bancaria
      'INT_PF'           -- Interés de plazo fijo
    )
  );

-- Verificación
SELECT 
    'cuentas_fondos' AS tabla,
    COUNT(*) AS registros
FROM public.cuentas_fondos
UNION ALL
SELECT 
    'evento_movimiento (con cuenta_id)',
    COUNT(*) 
FROM public.evento_movimiento 
WHERE cuenta_id IS NOT NULL;
```

### ✅ Verificar Instalación Fase 20

Ejecutá para confirmar:

```sql
-- 1. Verificar que la tabla existe
SELECT 
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'cuentas_fondos'
ORDER BY ordinal_position;

-- 2. Verificar índices
SELECT 
    indexname,
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public' 
  AND tablename = 'cuentas_fondos'
ORDER BY indexname;

-- 3. Verificar columnas nuevas en evento_movimiento
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'evento_movimiento'
  AND column_name IN ('cuenta_id', 'es_transferencia', 'transferencia_id');

-- 4. Verificar categorías nuevas (debería incluir TRANSFERENCIA, COM_BANC, INT_PF)
SELECT 
    conname,
    pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.evento_movimiento'::regclass
  AND conname LIKE '%categoria%';
```

### 🔄 Flujo de Sincronización de Cuentas

**Desde la app móvil:**
1. Usuario crea/edita una cuenta en la app
2. Registro queda en SQLite local con `sync_estado = 'PENDIENTE'`
3. Usuario sincroniza manualmente
4. App sube registro a Supabase (tabla `cuentas_fondos`)
5. Si exitoso: `sync_estado = 'SINCRONIZADA'`

**Transferencias:**
- Cada transferencia genera **2 movimientos** en `evento_movimiento`:
  - 1 EGRESO en cuenta origen
  - 1 INGRESO en cuenta destino
- Ambos comparten el mismo `transferencia_id` (UUID v4)
- Ambos tienen `es_transferencia = 1`

### 📊 Consultas Útiles (Cuentas)

```sql
-- Ver todas las cuentas activas con saldos
SELECT 
    cf.id,
    cf.nombre,
    cf.tipo,
    cf.saldo_inicial,
    COUNT(em.id) AS total_movimientos,
    COALESCE(SUM(CASE WHEN em.tipo = 'INGRESO' THEN em.monto ELSE 0 END), 0) AS total_ingresos,
    COALESCE(SUM(CASE WHEN em.tipo = 'EGRESO' THEN em.monto ELSE 0 END), 0) AS total_egresos,
    cf.saldo_inicial + 
      COALESCE(SUM(CASE WHEN em.tipo = 'INGRESO' THEN em.monto ELSE 0 END), 0) -
      COALESCE(SUM(CASE WHEN em.tipo = 'EGRESO' THEN em.monto ELSE 0 END), 0) AS saldo_actual
FROM public.cuentas_fondos cf
LEFT JOIN public.evento_movimiento em ON em.cuenta_id = cf.id AND em.eliminado = FALSE
WHERE cf.eliminado = FALSE AND cf.activo = TRUE
GROUP BY cf.id, cf.nombre, cf.tipo, cf.saldo_inicial
ORDER BY cf.nombre;

-- Ver transferencias (movimientos vinculados)
SELECT 
    em.transferencia_id,
    em.tipo,
    cf.nombre AS cuenta,
    em.monto,
    em.created_ts
FROM public.evento_movimiento em
JOIN public.cuentas_fondos cf ON cf.id = em.cuenta_id
WHERE em.es_transferencia = 1 
  AND em.eliminado = FALSE
ORDER BY em.transferencia_id, em.tipo DESC;

-- Comisiones bancarias por cuenta
SELECT 
    cf.nombre AS cuenta,
    COUNT(*) AS total_comisiones,
    SUM(em.monto) AS total_monto_comisiones
FROM public.evento_movimiento em
JOIN public.cuentas_fondos cf ON cf.id = em.cuenta_id
WHERE em.categoria = 'COM_BANC' 
  AND em.eliminado = FALSE
GROUP BY cf.id, cf.nombre
ORDER BY total_monto_comisiones DESC;
```

### 🧪 Probar Sincronización de Cuentas

1. En la app móvil, andá a **Tesorería → Cuentas de Fondos**
2. Creá una cuenta de prueba (ej: Banco Nación)
3. Registrá algunos movimientos vinculados a esa cuenta
4. Creá una transferencia entre dos cuentas
5. Sincronizá desde **"Pendientes de Sincronizar"**
6. Verificá en Supabase:

```sql
-- Ver última cuenta sincronizada
SELECT * FROM public.cuentas_fondos 
ORDER BY created_ts DESC 
LIMIT 1;

-- Ver movimientos de esa cuenta
SELECT * FROM public.evento_movimiento 
WHERE cuenta_id = (SELECT id FROM public.cuentas_fondos ORDER BY created_ts DESC LIMIT 1)
ORDER BY created_ts DESC;
```

---

**Última actualización:** Enero 15, 2026  
**Fase:** 12 - Sincronización Tesorería con Supabase  
**Fase 20:** Gestión de Cuentas de Fondos ✅ COMPLETA
