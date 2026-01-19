-- ==========================================
-- Script de actualización Supabase para Tesorería
-- BuffetApp v2.0 - Fase 12
-- ==========================================
-- Este script agrega las tablas necesarias para sincronizar
-- los movimientos financieros de Tesorería con Supabase

-- =========================
-- Tabla: unidades_gestion
-- =========================
-- Reemplaza conceptualmente a "disciplinas" con un modelo más flexible
-- que soporta disciplinas deportivas, comisiones y eventos especiales

create table if not exists public.unidades_gestion (
  id integer primary key,
  nombre text unique not null,
  tipo text not null check (tipo in ('DISCIPLINA','COMISION','EVENTO')),
  disciplina_ref text,
  activo integer not null default 1,
  created_ts bigint not null default (extract(epoch from now())*1000)::bigint,
  updated_ts bigint not null default (extract(epoch from now())*1000)::bigint
);

create index if not exists idx_unidades_gestion_tipo 
  on public.unidades_gestion (tipo, activo);

-- Seed de unidades de gestión (8 unidades base)
insert into public.unidades_gestion (id, nombre, tipo, disciplina_ref, activo)
values
  (1, 'Fútbol Mayor', 'DISCIPLINA', 'FUTBOL', 1),
  (2, 'Fútbol Infantil', 'DISCIPLINA', 'FUTBOL', 1),
  (3, 'Vóley', 'DISCIPLINA', 'VOLEY', 1),
  (4, 'Patín', 'DISCIPLINA', 'PATIN', 1),
  (5, 'Tenis', 'DISCIPLINA', 'TENIS', 1),
  (6, 'Fútbol Senior', 'DISCIPLINA', 'FUTBOL', 1),
  (7, 'Comisión Directiva', 'COMISION', null, 1),
  (8, 'Evento Especial', 'EVENTO', null, 1)
on conflict (id) do nothing;

-- =========================
-- Tabla: evento_movimiento
-- =========================
-- Movimientos financieros externos al buffet (ingresos/egresos de tesorería)
-- Soporta adjuntos de archivos (imágenes de comprobantes)

create table if not exists public.evento_movimiento (
  id bigserial primary key,
  
  -- Contexto
  evento_id uuid references public.eventos(evento_id),
  disciplina_id integer not null references public.disciplinas(id),
  
  -- Datos del movimiento
  tipo text not null check (tipo in ('INGRESO','EGRESO')),
  categoria text,
  monto double precision not null check (monto > 0),
  medio_pago_id integer not null references public.metodos_pago(id),
  observacion text,
  
  -- Adjuntos (archivos de comprobantes)
  archivo_local_path text,
  archivo_remote_url text,
  archivo_nombre text,
  archivo_tipo text,
  archivo_size bigint,
  
  -- Soft delete
  eliminado integer not null default 0,
  
  -- Dispositivo origen
  dispositivo_id uuid,
  
  -- Sincronización
  sync_estado text not null default 'PENDIENTE' 
    check (sync_estado in ('PENDIENTE','SINCRONIZADA','ERROR')),
  
  -- Timestamps
  created_ts bigint not null default (extract(epoch from now())*1000)::bigint,
  updated_ts bigint
);

-- Índices para optimizar consultas
create index if not exists idx_evento_mov_disc_created 
  on public.evento_movimiento (disciplina_id, created_ts);
  
create index if not exists idx_evento_mov_evento_id 
  on public.evento_movimiento (evento_id);
  
create index if not exists idx_evento_mov_mp_id 
  on public.evento_movimiento (medio_pago_id);
  
create index if not exists idx_evento_mov_tipo 
  on public.evento_movimiento (tipo);
  
create index if not exists idx_evento_mov_eliminado 
  on public.evento_movimiento (eliminado);

-- =========================
-- RLS (sin auth => off)
-- =========================
alter table public.unidades_gestion disable row level security;
alter table public.evento_movimiento disable row level security;

-- =========================
-- Comentarios para documentación
-- =========================
comment on table public.unidades_gestion is 
  'Unidades de gestión del club: disciplinas deportivas, comisiones y eventos especiales';
  
comment on column public.unidades_gestion.tipo is 
  'DISCIPLINA: deporte/actividad, COMISION: comisión directiva, EVENTO: evento especial';
  
comment on column public.unidades_gestion.disciplina_ref is 
  'Referencia al tipo de deporte (FUTBOL, VOLEY, PATIN, etc). Null para comisiones y eventos';

comment on table public.evento_movimiento is 
  'Movimientos financieros externos al buffet: ingresos y egresos de tesorería';
  
comment on column public.evento_movimiento.archivo_remote_url is 
  'URL de Supabase Storage para el comprobante adjunto (imagen)';
  
comment on column public.evento_movimiento.eliminado is 
  'Soft delete: 0=activo, 1=eliminado';

-- =========================
-- Notas de implementación
-- =========================
-- 
-- FLUJO DE SINCRONIZACIÓN:
-- 1. El dispositivo móvil crea movimientos con sync_estado='PENDIENTE'
-- 2. Al sincronizar, la app sube:
--    a) El registro del movimiento a esta tabla
--    b) El archivo adjunto (si existe) a Supabase Storage
--    c) Actualiza archivo_remote_url con la URL pública del archivo
-- 3. Si todo OK, marca sync_estado='SINCRONIZADA' en local y remoto
-- 4. Si falla, marca sync_estado='ERROR'
--
-- DIFERENCIAS CON BUFFET (caja_diaria):
-- - evento_movimiento NO depende de una caja abierta
-- - evento_movimiento puede tener evento_id NULL (movimientos semanales/mensuales)
-- - evento_movimiento soporta adjuntos de archivos
-- - evento_movimiento usa soft delete (eliminado=1)
--
-- COMPATIBILIDAD:
-- - disciplina_id referencia a la tabla disciplinas existente
-- - Futura migración: agregar unidad_gestion_id cuando se deprecie disciplinas
