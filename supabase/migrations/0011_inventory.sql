-- ============================================================================
-- 0011_inventory.sql — S5 Tồn kho thời gian thực (theo từng Téc).
-- Công thức (giữ nguyên file cũ):
--   Tồn cuối = Tồn đầu gốc + Nhập − Xuất − Tịnh âm + Tịnh dương
-- Chỉ tính bút toán ĐÃ chốt: status='DaDuyet' HOẶC legacy=true.
--   Nhập = Σ lít entry_type='nhap' vào téc.
--   Xuất = Σ lít entry_type='bom' kind='xuat' từ téc (xuất nội bộ).
--   Bơm ngoài (kind='bom_ngoai') KHÔNG gắn téc (tank_id null) → không trừ tồn.
--   Tịnh (entry_type='adjust') = 0 ở S5 (chưa có phiếu tịnh); S6 sẽ OVERRIDE
--     rpc_inventory_stock để cộng/trừ tịnh có dấu.
-- Tồn đầu gốc: bảng `tank_opening` seed một lần (KeToan chốt, quyền adjust:manage);
-- giá trị đo tay lấy từ file cũ ở S9. Deny-by-default + RPC SECURITY DEFINER.
-- KHÔNG sửa migration cũ.
-- ============================================================================

-- Tồn đầu gốc mỗi téc tại một mốc khởi tạo (một dòng / téc).
create table if not exists tank_opening (
  tank_id uuid primary key references tanks (id) on delete cascade,
  as_of_date date not null default current_date,
  liters numeric(14,2) not null default 0 check (liters >= 0),
  note text,
  updated_by uuid references profiles (id),
  updated_at timestamptz not null default now()
);
comment on table tank_opening is 'Tồn đầu gốc từng téc tại mốc khởi tạo; nền của công thức tồn kho.';

alter table tank_opening enable row level security;
revoke all on tank_opening from anon, authenticated;
create or replace trigger trg_tank_opening_updated before update on tank_opening for each row execute function set_updated_at();

-- ----------------------------------------------------------------------------
-- Đặt/cập nhật Tồn đầu gốc của một téc (KeToan chốt).
-- ----------------------------------------------------------------------------
create or replace function rpc_tank_opening_set(
  p_tank_id uuid, p_liters numeric, p_as_of_date date default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_before jsonb; v_row tank_opening;
begin
  v_actor := require_permission('adjust:manage');
  if p_tank_id is null or not exists (select 1 from tanks where id = p_tank_id) then
    raise exception 'Téc không hợp lệ.';
  end if;
  if coalesce(p_liters,0) < 0 then raise exception 'Tồn đầu không được âm.'; end if;
  select to_jsonb(o) into v_before from tank_opening o where tank_id = p_tank_id;
  insert into tank_opening (tank_id, liters, as_of_date, note, updated_by)
  values (p_tank_id, p_liters, coalesce(p_as_of_date, current_date),
    nullif(trim(coalesce(p_note,'')),''), v_actor.id)
  on conflict (tank_id) do update set
    liters = excluded.liters, as_of_date = excluded.as_of_date,
    note = excluded.note, updated_by = excluded.updated_by
  returning * into v_row;
  perform write_audit(v_actor, 'SET_TANK_OPENING', 'tank_opening', p_tank_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'tankId', p_tank_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- Tồn kho thời gian thực theo từng téc (đọc cho mọi vai trò có inventory:read).
-- ----------------------------------------------------------------------------
create or replace function rpc_inventory_stock() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('inventory:read');
  select coalesce(jsonb_agg(r order by r_name), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'tankId', t.id, 'tankName', t.name, 'oilTypeName', ot.name,
      'capacity', t.capacity_liters, 'reorderPoint', t.reorder_point,
      'opening', coalesce(op.liters, 0),
      'nhap', coalesce(nh.s, 0),
      'xuat', coalesce(xu.s, 0),
      'adjust', 0,   -- S6 override: cộng/trừ tịnh có dấu
      'closing', coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0),
      'pctFull', case when t.capacity_liters > 0
        then round((coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0)) / t.capacity_liters * 100, 1)
        else null end,
      'openingAsOf', to_char(op.as_of_date, 'YYYY-MM-DD')
    ) as r, t.name as r_name
    from tanks t
    left join oil_types ot on ot.id = t.oil_type_id
    left join tank_opening op on op.tank_id = t.id
    left join lateral (
      select sum(l.liters) s from ledger l
       where l.tank_id = t.id and l.entry_type = 'nhap' and (l.status = 'DaDuyet' or l.legacy)
    ) nh on true
    left join lateral (
      select sum(l.liters) s from ledger l
       join transaction_types tt on tt.id = l.txn_type_id
       where l.tank_id = t.id and l.entry_type = 'bom' and tt.kind = 'xuat'
         and (l.status = 'DaDuyet' or l.legacy)
    ) xu on true
    where t.active
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_tank_opening_set(uuid, numeric, date, text) to authenticated;
grant execute on function rpc_inventory_stock() to authenticated;
