-- ============================================================================
-- 0006_catalog.sql — S1 Danh mục nền: Téc, Loại dầu, Nhà cung cấp,
-- Loại giao dịch, Xe. Deny-by-default + RPC SECURITY DEFINER + require_permission.
-- Quản (thêm/sửa/ngừng) gated 'catalog:manage' (KeToan/Admin). Đọc danh mục
-- active cho dropdown nhập liệu gated 'catalog:read' (mọi vai trò hoạt động).
-- KHÔNG sửa migration cũ; các slice sau tham chiếu các bảng này.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Bảng danh mục
-- ----------------------------------------------------------------------------
create table if not exists oil_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists oil_types_name_uk on oil_types (normalize_text(name));

create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists suppliers_name_uk on suppliers (normalize_text(name));

-- Loại giao dịch: semi cố định. 'kind' lái logic tồn kho ở S5:
--   xuat = xuất nội bộ (trừ tồn téc) · bom_ngoai = bơm ngoài (không trừ tồn)
--   nhap = nhập vào kho/téc (cộng tồn)
create table if not exists transaction_types (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  kind text not null check (kind in ('xuat','bom_ngoai','nhap')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists tanks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  oil_type_id uuid references oil_types (id),
  capacity_liters numeric(14,2) not null default 0 check (capacity_liters >= 0),
  reorder_point numeric(14,2) not null default 0 check (reorder_point >= 0),
  lead_time_days integer not null default 0 check (lead_time_days >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists tanks_name_uk on tanks (normalize_text(name));

create table if not exists vehicles (
  id uuid primary key default gen_random_uuid(),
  plate text not null,
  pump_norm numeric(14,2) not null default 0 check (pump_norm >= 0),
  has_odometer boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists vehicles_plate_uk on vehicles (normalize_text(plate));

create or replace trigger trg_oil_types_updated        before update on oil_types        for each row execute function set_updated_at();
create or replace trigger trg_suppliers_updated         before update on suppliers         for each row execute function set_updated_at();
create or replace trigger trg_transaction_types_updated before update on transaction_types for each row execute function set_updated_at();
create or replace trigger trg_tanks_updated             before update on tanks             for each row execute function set_updated_at();
create or replace trigger trg_vehicles_updated          before update on vehicles          for each row execute function set_updated_at();

-- ----------------------------------------------------------------------------
-- Deny-by-default: bật RLS, không policy, revoke → chỉ vào được qua RPC.
-- ----------------------------------------------------------------------------
alter table oil_types         enable row level security;
alter table suppliers         enable row level security;
alter table transaction_types enable row level security;
alter table tanks             enable row level security;
alter table vehicles          enable row level security;
revoke all on oil_types, suppliers, transaction_types, tanks, vehicles from anon, authenticated;

-- ----------------------------------------------------------------------------
-- Quyền
-- ----------------------------------------------------------------------------
insert into role_permissions (role, permission) values
  ('ThuKho','catalog:read'),
  ('KeToan','catalog:read')
on conflict do nothing;

-- Seed 3 loại giao dịch chuẩn (đổi tên/ẩn được, code cố định).
insert into transaction_types (code, name, kind) values
  ('xuat_noi_bo', 'Xuất nội bộ từ téc', 'xuat'),
  ('bom_ngoai',   'Bơm ngoài',          'bom_ngoai'),
  ('nhap_kho',    'Nhập vào kho/téc',   'nhap')
on conflict (code) do nothing;

-- ----------------------------------------------------------------------------
-- RPC đọc
-- ----------------------------------------------------------------------------
-- Danh mục đầy đủ (kể cả đã ngừng) cho màn quản lý.
create or replace function rpc_catalog_list() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  perform require_permission('catalog:manage');
  select jsonb_build_object(
    'ok', true,
    'oilTypes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'active', active) order by name), '[]'::jsonb) from oil_types),
    'suppliers', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'phone', phone, 'note', note, 'active', active) order by name), '[]'::jsonb) from suppliers),
    'txnTypes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'code', code, 'name', name, 'kind', kind, 'active', active) order by created_at), '[]'::jsonb) from transaction_types),
    'tanks', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'oilTypeId', t.oil_type_id, 'oilTypeName', ot.name,
        'capacity', t.capacity_liters, 'reorderPoint', t.reorder_point,
        'leadTimeDays', t.lead_time_days, 'active', t.active) order by t.name), '[]'::jsonb)
      from tanks t left join oil_types ot on ot.id = t.oil_type_id),
    'vehicles', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'plate', plate, 'pumpNorm', pump_norm,
        'hasOdometer', has_odometer, 'active', active) order by plate), '[]'::jsonb) from vehicles)
  ) into v;
  return v;
end;
$$;

-- Chỉ mục active cho dropdown nhập liệu (mọi vai trò hoạt động).
create or replace function rpc_catalog_active() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  perform require_permission('catalog:read');
  select jsonb_build_object(
    'ok', true,
    'oilTypes', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb) from oil_types where active),
    'suppliers', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb) from suppliers where active),
    'txnTypes', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', name, 'kind', kind) order by created_at), '[]'::jsonb) from transaction_types where active),
    'tanks', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'oilTypeId', oil_type_id) order by name), '[]'::jsonb) from tanks where active),
    'vehicles', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'plate', plate, 'pumpNorm', pump_norm, 'hasOdometer', has_odometer) order by plate), '[]'::jsonb) from vehicles where active)
  ) into v;
  return v;
end;
$$;

-- ----------------------------------------------------------------------------
-- RPC ghi (thêm/sửa). p_id null = thêm mới, khác null = sửa.
-- ----------------------------------------------------------------------------
create or replace function rpc_oil_type_upsert(p_id uuid, p_name text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_name text := trim(coalesce(p_name,'')); v_before jsonb; v_row oil_types;
begin
  v_actor := require_permission('catalog:manage');
  if v_name = '' then raise exception 'Tên loại dầu không được trống.'; end if;
  if p_id is null then
    insert into oil_types (name, active) values (v_name, coalesce(p_active,true)) returning * into v_row;
  else
    select to_jsonb(o) into v_before from oil_types o where id = p_id;
    if v_before is null then raise exception 'Không tìm thấy loại dầu.'; end if;
    update oil_types set name = v_name, active = coalesce(p_active,true) where id = p_id returning * into v_row;
  end if;
  perform write_audit(v_actor, case when p_id is null then 'CREATE_OIL_TYPE' else 'UPDATE_OIL_TYPE' end,
    'oil_types', v_row.id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
exception when unique_violation then raise exception 'Loại dầu "%" đã tồn tại.', v_name;
end;
$$;

create or replace function rpc_supplier_upsert(p_id uuid, p_name text, p_phone text default null, p_note text default null, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_name text := trim(coalesce(p_name,'')); v_before jsonb; v_row suppliers;
begin
  v_actor := require_permission('catalog:manage');
  if v_name = '' then raise exception 'Tên nhà cung cấp không được trống.'; end if;
  if p_id is null then
    insert into suppliers (name, phone, note, active)
      values (v_name, nullif(trim(coalesce(p_phone,'')),''), nullif(trim(coalesce(p_note,'')),''), coalesce(p_active,true))
      returning * into v_row;
  else
    select to_jsonb(s) into v_before from suppliers s where id = p_id;
    if v_before is null then raise exception 'Không tìm thấy nhà cung cấp.'; end if;
    update suppliers set name = v_name,
      phone = nullif(trim(coalesce(p_phone,'')),''), note = nullif(trim(coalesce(p_note,'')),''),
      active = coalesce(p_active,true) where id = p_id returning * into v_row;
  end if;
  perform write_audit(v_actor, case when p_id is null then 'CREATE_SUPPLIER' else 'UPDATE_SUPPLIER' end,
    'suppliers', v_row.id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
exception when unique_violation then raise exception 'Nhà cung cấp "%" đã tồn tại.', v_name;
end;
$$;

-- Loại giao dịch: chỉ đổi tên/ngừng; code + kind cố định (seed).
create or replace function rpc_txn_type_upsert(p_id uuid, p_name text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_name text := trim(coalesce(p_name,'')); v_before jsonb; v_row transaction_types;
begin
  v_actor := require_permission('catalog:manage');
  if p_id is null then raise exception 'Loại giao dịch là danh mục cố định, không thêm mới.'; end if;
  if v_name = '' then raise exception 'Tên loại giao dịch không được trống.'; end if;
  select to_jsonb(x) into v_before from transaction_types x where id = p_id;
  if v_before is null then raise exception 'Không tìm thấy loại giao dịch.'; end if;
  update transaction_types set name = v_name, active = coalesce(p_active,true) where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_TXN_TYPE', 'transaction_types', v_row.id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;

create or replace function rpc_tank_upsert(
  p_id uuid, p_name text, p_oil_type_id uuid default null,
  p_capacity numeric default 0, p_reorder numeric default 0,
  p_lead_time_days integer default 0, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_name text := trim(coalesce(p_name,'')); v_before jsonb; v_row tanks;
begin
  v_actor := require_permission('catalog:manage');
  if v_name = '' then raise exception 'Tên téc không được trống.'; end if;
  if coalesce(p_capacity,0) < 0 or coalesce(p_reorder,0) < 0 or coalesce(p_lead_time_days,0) < 0 then
    raise exception 'Sức chứa / reorder / lead-time không được âm.';
  end if;
  if p_oil_type_id is not null and not exists (select 1 from oil_types where id = p_oil_type_id) then
    raise exception 'Loại dầu không hợp lệ.';
  end if;
  if p_id is null then
    insert into tanks (name, oil_type_id, capacity_liters, reorder_point, lead_time_days, active)
      values (v_name, p_oil_type_id, coalesce(p_capacity,0), coalesce(p_reorder,0), coalesce(p_lead_time_days,0), coalesce(p_active,true))
      returning * into v_row;
  else
    select to_jsonb(t) into v_before from tanks t where id = p_id;
    if v_before is null then raise exception 'Không tìm thấy téc.'; end if;
    update tanks set name = v_name, oil_type_id = p_oil_type_id,
      capacity_liters = coalesce(p_capacity,0), reorder_point = coalesce(p_reorder,0),
      lead_time_days = coalesce(p_lead_time_days,0), active = coalesce(p_active,true)
      where id = p_id returning * into v_row;
  end if;
  perform write_audit(v_actor, case when p_id is null then 'CREATE_TANK' else 'UPDATE_TANK' end,
    'tanks', v_row.id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
exception when unique_violation then raise exception 'Téc "%" đã tồn tại.', v_name;
end;
$$;

create or replace function rpc_vehicle_upsert(
  p_id uuid, p_plate text, p_pump_norm numeric default 0,
  p_has_odometer boolean default true, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_plate text := trim(coalesce(p_plate,'')); v_before jsonb; v_row vehicles;
begin
  v_actor := require_permission('catalog:manage');
  if v_plate = '' then raise exception 'Biển số xe không được trống.'; end if;
  if coalesce(p_pump_norm,0) < 0 then raise exception 'Định mức bơm không được âm.'; end if;
  if p_id is null then
    insert into vehicles (plate, pump_norm, has_odometer, active)
      values (v_plate, coalesce(p_pump_norm,0), coalesce(p_has_odometer,true), coalesce(p_active,true))
      returning * into v_row;
  else
    select to_jsonb(x) into v_before from vehicles x where id = p_id;
    if v_before is null then raise exception 'Không tìm thấy xe.'; end if;
    update vehicles set plate = v_plate, pump_norm = coalesce(p_pump_norm,0),
      has_odometer = coalesce(p_has_odometer,true), active = coalesce(p_active,true)
      where id = p_id returning * into v_row;
  end if;
  perform write_audit(v_actor, case when p_id is null then 'CREATE_VEHICLE' else 'UPDATE_VEHICLE' end,
    'vehicles', v_row.id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
exception when unique_violation then raise exception 'Xe biển số "%" đã tồn tại.', v_plate;
end;
$$;

-- Bật/ngừng nhanh (soft-delete) cho mọi danh mục — giữ nguyên lịch sử.
create or replace function rpc_catalog_toggle(p_kind text, p_id uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_tbl text; v_n integer;
begin
  v_actor := require_permission('catalog:manage');
  v_tbl := case p_kind
    when 'oilType'  then 'oil_types'
    when 'supplier' then 'suppliers'
    when 'txnType'  then 'transaction_types'
    when 'tank'     then 'tanks'
    when 'vehicle'  then 'vehicles'
    else null end;
  if v_tbl is null then raise exception 'Loại danh mục không hợp lệ: %', p_kind; end if;
  execute format('update %I set active = $1 where id = $2', v_tbl) using coalesce(p_active,true), p_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Không tìm thấy mục cần cập nhật.'; end if;
  perform write_audit(v_actor, 'TOGGLE_CATALOG', v_tbl, p_id::text, null,
    jsonb_build_object('active', coalesce(p_active,true)));
  return jsonb_build_object('ok', true, 'id', p_id, 'active', coalesce(p_active,true));
end;
$$;

grant execute on function rpc_catalog_list() to authenticated;
grant execute on function rpc_catalog_active() to authenticated;
grant execute on function rpc_oil_type_upsert(uuid, text, boolean) to authenticated;
grant execute on function rpc_supplier_upsert(uuid, text, text, text, boolean) to authenticated;
grant execute on function rpc_txn_type_upsert(uuid, text, boolean) to authenticated;
grant execute on function rpc_tank_upsert(uuid, text, uuid, numeric, numeric, integer, boolean) to authenticated;
grant execute on function rpc_vehicle_upsert(uuid, text, numeric, boolean, boolean) to authenticated;
grant execute on function rpc_catalog_toggle(text, uuid, boolean) to authenticated;
