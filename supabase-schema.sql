-- ============================================================
--  Mobile POS — Supabase Sync Schema
--  الصق هذا الملف كاملاً في: Supabase → SQL Editor → New query → Run
--  Paste this whole file into Supabase SQL Editor and click Run
-- ============================================================

-- One universal table holds every record from every store.
-- Records are isolated per store via store_id + a shared secret.
create table if not exists public.pos_records (
  store_id   text        not null,          -- معرّف المتجر (Store ID)
  entity     text        not null,          -- products / sales / customers ...
  id         text        not null,          -- UUID الخاص بالسجل
  data       jsonb       not null,          -- محتوى السجل الكامل
  updated_at timestamptz not null default now(),
  deleted    boolean     not null default false,
  primary key (store_id, entity, id)
);

-- Fast pulls: "give me everything for this store changed after X"
create index if not exists pos_records_sync_idx
  on public.pos_records (store_id, updated_at);

-- ============================================================
--  Store registry — كل متجر له رمز سري (secret) للتحقق
-- ============================================================
create table if not exists public.pos_stores (
  store_id   text primary key,
  secret     text        not null,          -- الرمز السري للمتجر
  name       text,
  created_at timestamptz not null default now()
);

-- ============================================================
--  Row Level Security
--  الأمان: لا أحد يصل لبيانات متجر إلا بمعرفة store_id + secret.
--  التحقق يتم عبر دالة تقارن الرمز المرسل في الهيدر.
-- ============================================================
alter table public.pos_records enable row level security;
alter table public.pos_stores  enable row level security;

-- The client sends the secret in a request header:  x-store-secret
-- This helper reads it.
create or replace function public.req_store_secret()
returns text language sql stable as $$
  select current_setting('request.headers', true)::json ->> 'x-store-secret'
$$;

-- Policy: a row in pos_records is accessible only if the provided
-- secret matches the secret registered for that store_id.
drop policy if exists pos_records_rw on public.pos_records;
create policy pos_records_rw on public.pos_records
  for all
  using (
    exists (
      select 1 from public.pos_stores s
      where s.store_id = pos_records.store_id
        and s.secret   = public.req_store_secret()
    )
  )
  with check (
    exists (
      select 1 from public.pos_stores s
      where s.store_id = pos_records.store_id
        and s.secret   = public.req_store_secret()
    )
  );

-- Stores table: allow reading/creating a store row only when the
-- caller already knows the secret (used for first-time registration
-- and for verifying credentials).
drop policy if exists pos_stores_select on public.pos_stores;
create policy pos_stores_select on public.pos_stores
  for select
  using ( secret = public.req_store_secret() );

drop policy if exists pos_stores_insert on public.pos_stores;
create policy pos_stores_insert on public.pos_stores
  for insert
  with check ( secret = public.req_store_secret() );

-- ============================================================
--  Realtime — بث التغييرات لحظياً لكل الأجهزة
-- ============================================================
alter publication supabase_realtime add table public.pos_records;

-- ============================================================
--  Done ✓  الجداول جاهزة. ارجع للتطبيق وأدخل بيانات المزامنة.
-- ============================================================
