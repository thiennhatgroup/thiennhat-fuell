-- ============================================================================
-- 0028_vehicle_entity.sql — Tách xe theo đơn vị (entity): Thiên Nhật / Lâm Hải.
-- Báo cáo tháng cần tách 2 đơn vị như file Excel gốc. Thêm cột entity vào xe,
-- cập nhật RPC upsert (thêm p_entity) và rpc_catalog_list (trả về entity).
-- KHÔNG sửa migration cũ.
-- ============================================================================

-- 1) Cột entity (mặc định Thiên Nhật cho xe hiện có).
alter table vehicles
  add column if not exists entity text not null default 'Thiên Nhật'
  check (entity in ('Thiên Nhật','Lâm Hải'));

-- 2) Upsert xe: thêm tham số p_entity. Bỏ chữ ký cũ (5 tham số) để tránh nhập nhằng.
drop function if exists rpc_vehicle_upsert(uuid, text, numeric, boolean, boolean);

create or replace function rpc_vehicle_upsert(
  p_id uuid, p_plate text, p_pump_norm numeric default 0,
  p_has_odometer boolean default true, p_active boolean default true,
  p_entity text default 'Thiên Nhật')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_actor profiles; v_plate text := trim(coalesce(p_plate,''));
  v_entity text := coalesce(nullif(trim(coalesce(p_entity,'')),''), 'Thiên Nhật');
  v_before jsonb; v_row vehicles;
begin
  v_actor := require_permission('catalog:manage');
  if v_plate = '' then raise exception 'Biển số xe không được trống.'; end if;
  if coalesce(p_pump_norm,0) < 0 then raise exception 'Định mức bơm không được âm.'; end if;
  if v_entity not in ('Thiên Nhật','Lâm Hải') then raise exception 'Đơn vị không hợp lệ.'; end if;
  if p_id is null then
    insert into vehicles (plate, pump_norm, has_odometer, active, entity)
      values (v_plate, coalesce(p_pump_norm,0), coalesce(p_has_odometer,true), coalesce(p_active,true), v_entity)
      returning * into v_row;
  else
    select to_jsonb(x) into v_before from vehicles x where id = p_id;
    if v_before is null then raise exception 'Không tìm thấy xe.'; end if;
    update vehicles set plate = v_plate, pump_norm = coalesce(p_pump_norm,0),
      has_odometer = coalesce(p_has_odometer,true), active = coalesce(p_active,true), entity = v_entity
      where id = p_id returning * into v_row;
  end if;
  perform write_audit(v_actor, case when p_id is null then 'CREATE_VEHICLE' else 'UPDATE_VEHICLE' end,
    'vehicles', v_row.id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
exception when unique_violation then raise exception 'Xe biển số "%" đã tồn tại.', v_plate;
end;
$$;

grant execute on function rpc_vehicle_upsert(uuid, text, numeric, boolean, boolean, text) to authenticated;

-- 3) Danh mục (Kế toán/Admin): trả thêm 'entity' cho mỗi xe.
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
        'hasOdometer', has_odometer, 'entity', entity, 'active', active) order by plate), '[]'::jsonb) from vehicles)
  ) into v;
  return v;
end;
$$;
