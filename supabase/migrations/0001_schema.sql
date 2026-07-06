-- ============================================================================
-- 0001_schema.sql — Tồn kho Xăng dầu (Thiên Nhật) — S0 nền tảng
-- Bám khuôn thiennhat-supabase: deny-by-default + RPC SECURITY DEFINER.
-- Slice S0 chỉ tạo phần nền: cấu hình, người dùng/vai trò, quyền, code_counters,
-- audit_log + helper. Các bảng nghiệp vụ (ledger, phiếu bơm, téc, xe, tịnh...)
-- sẽ đến ở các migration sau (S1+), KHÔNG sửa migration này về sau.
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid(), crypt()
create extension if not exists unaccent;    -- so khớp không dấu tiếng Việt

-- ----------------------------------------------------------------------------
-- Cấu hình + người dùng + quyền
-- ----------------------------------------------------------------------------
create table if not exists app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique not null,
  name text not null,
  role text not null check (role in ('ThuKho','KeToan','Admin')),
  status text not null default 'Hoạt động' check (status in ('Hoạt động','Ngừng')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table profiles is 'Một dòng / một Supabase Auth user, khóa theo auth.users.id.';

create table if not exists role_permissions (
  role text not null,
  permission text not null,
  primary key (role, permission)
);
comment on table role_permissions is 'Ma trận quyền. Admin bỏ qua bảng này (coi như "*").';

create table if not exists code_counters (
  prefix text not null,
  day date not null,
  seq int not null default 0,
  primary key (prefix, day)
);

create table if not exists audit_log (
  id uuid primary key default gen_random_uuid(),
  log_id text unique not null,
  time timestamptz not null default now(),
  actor_id uuid references profiles (id),
  actor_email text,
  actor_name text,
  role text,
  action text not null,
  entity_type text not null,
  entity_id text,
  before_json jsonb,
  after_json jsonb,
  result text not null default 'OK',
  message text
);

-- ----------------------------------------------------------------------------
-- Helper: cấp mã tăng dần theo ngày (BOM-YYYYMMDD-###, NHAP-..., LOG-...)
-- ----------------------------------------------------------------------------
create or replace function next_code(p_prefix text) returns text
language plpgsql as $$
declare
  v_seq int;
  v_day date := current_date;
begin
  insert into code_counters (prefix, day, seq) values (p_prefix, v_day, 1)
  on conflict (prefix, day) do update set seq = code_counters.seq + 1
  returning seq into v_seq;
  return p_prefix || '-' || to_char(v_day, 'YYYYMMDD') || '-' || lpad(v_seq::text, 3, '0');
end;
$$;

-- Cấp mã tăng dần theo NĂM (cho Số phiếu: BOM-2026-000123)
create or replace function next_code_year(p_prefix text) returns text
language plpgsql as $$
declare
  v_seq int;
  v_year date := date_trunc('year', current_date)::date;
begin
  insert into code_counters (prefix, day, seq) values (p_prefix, v_year, 1)
  on conflict (prefix, day) do update set seq = code_counters.seq + 1
  returning seq into v_seq;
  return p_prefix || '-' || to_char(current_date, 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

-- Chuẩn hóa text không dấu (so khớp tên xe/NCC...)
create or replace function normalize_text(p_text text) returns text
language sql immutable as $$
  select trim(regexp_replace(lower(unaccent(replace(coalesce(p_text, ''), 'đ', 'd'))), '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger trg_profiles_updated before update on profiles for each row execute function set_updated_at();
create or replace trigger trg_app_config_updated before update on app_config for each row execute function set_updated_at();
