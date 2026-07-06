-- ============================================================================
-- 0012_stock_period.sql — S6 Kỳ điều chỉnh tồn (Tịnh téc + Kiểm kê) + Phân bổ tịnh.
-- Một thực thể chung: Tịnh téc (téc cạn) và Kiểm kê (giữa chừng) chỉ khác `kind`.
-- Kế toán tạo kỳ (Téc, ngày bắt đầu), rồi CHỐT với Tồn thực tế đo tay →
--   book_before = Tồn sổ tại thời điểm chốt (theo công thức tồn kho, kể cả tịnh kỳ trước)
--   diff = book_before − Tồn thực tế
--   Tịnh âm = max(diff,0) (hao hụt) · Tịnh dương = max(−diff,0) (dôi)
-- rồi PHÂN BỔ tịnh cho từng Xe đã bơm (xuất) từ téc trong kỳ theo tỉ lệ lít:
--   PB(xe) = Lít_xe × Tịnh_kỳ / Tổng_lít_kỳ  (giữ nguyên công thức cũ)
-- Làm tròn 2 chữ số + dồn phần dư vào xe lít lớn nhất → tổng PB khớp tuyệt đối tịnh kỳ.
-- KHÔNG qua đối chiếu ThuKho (Kế toán chốt, quyền adjust:manage).
-- Tịnh phản ánh vào tồn kho: OVERRIDE rpc_inventory_stock cộng −Tịnh âm +Tịnh dương.
-- Deny-by-default + RPC SECURITY DEFINER. KHÔNG sửa migration cũ.
-- ============================================================================

-- Kỳ điều chỉnh tồn (một dòng / kỳ).
create table if not exists stock_period (
  id uuid primary key default gen_random_uuid(),
  code text unique,                                   -- TINH-YYYY-######; cấp lúc Chốt
  tank_id uuid not null references tanks (id),
  kind text not null check (kind in ('tinh_tec','kiem_ke')),
  start_date date not null,
  close_date date,
  actual_liters numeric(14,2) check (actual_liters >= 0),  -- tồn thực tế đo tay (lúc chốt)
  book_liters numeric(14,2),                          -- tồn sổ tại thời điểm chốt
  tinh_am numeric(14,2) not null default 0,           -- hao hụt (book > thực tế)
  tinh_duong numeric(14,2) not null default 0,        -- dôi (thực tế > book)
  total_liters numeric(14,2) not null default 0,      -- tổng lít xe bơm từ téc trong kỳ
  status text not null default 'Mo' check (status in ('Mo','DaChot')),
  note text,
  created_by uuid references profiles (id),
  closed_by uuid references profiles (id),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table stock_period is 'Kỳ điều chỉnh tồn (Tịnh téc/Kiểm kê); chốt sinh tịnh âm/dương + phân bổ cho xe.';
create index if not exists stock_period_tank_idx on stock_period (tank_id, status);

-- Phân bổ tịnh cho từng xe trong một kỳ (một dòng / xe).
create table if not exists stock_period_alloc (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references stock_period (id) on delete cascade,
  vehicle_id uuid not null references vehicles (id),
  liters_in_period numeric(14,2) not null default 0,
  tinh_am numeric(14,2) not null default 0,   -- phần hao hụt phân cho xe (cộng tiêu hao)
  tinh_duong numeric(14,2) not null default 0,-- phần dôi phân cho xe (trừ tiêu hao)
  created_at timestamptz not null default now(),
  unique (period_id, vehicle_id)
);
create index if not exists stock_period_alloc_period_idx on stock_period_alloc (period_id);
create index if not exists stock_period_alloc_vehicle_idx on stock_period_alloc (vehicle_id);

alter table stock_period enable row level security;
alter table stock_period_alloc enable row level security;
revoke all on stock_period, stock_period_alloc from anon, authenticated;
create or replace trigger trg_stock_period_updated before update on stock_period for each row execute function set_updated_at();

-- ----------------------------------------------------------------------------
-- Helper nội bộ (KHÔNG grant): Tồn sổ của téc tại mốc `as_of`, kể cả tịnh của
-- các kỳ đã chốt trước đó. = Tồn đầu + Nhập − Xuất − Σtịnh âm + Σtịnh dương.
-- ----------------------------------------------------------------------------
create or replace function tank_book_before(p_tank_id uuid, p_as_of date) returns numeric
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select liters from tank_opening where tank_id = p_tank_id), 0)
    + coalesce((select sum(l.liters) from ledger l
        where l.tank_id = p_tank_id and l.entry_type = 'nhap'
          and l.entry_date <= p_as_of and (l.status = 'DaDuyet' or l.legacy)), 0)
    - coalesce((select sum(l.liters) from ledger l
        join transaction_types tt on tt.id = l.txn_type_id
        where l.tank_id = p_tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
          and l.entry_date <= p_as_of and (l.status = 'DaDuyet' or l.legacy)), 0)
    + coalesce((select sum(coalesce(sp.tinh_duong,0) - coalesce(sp.tinh_am,0))
        from stock_period sp
        where sp.tank_id = p_tank_id and sp.status = 'DaChot' and sp.close_date <= p_as_of), 0);
$$;

-- ----------------------------------------------------------------------------
-- Tạo kỳ (Mo). Không cho hai kỳ đang mở trên cùng một téc.
-- ----------------------------------------------------------------------------
create or replace function rpc_stock_period_create(
  p_tank_id uuid, p_kind text, p_start_date date, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_row stock_period;
begin
  v_actor := require_permission('adjust:manage');
  if p_tank_id is null or not exists (select 1 from tanks where id = p_tank_id and active) then
    raise exception 'Téc không hợp lệ hoặc đã ngừng.'; end if;
  if p_kind not in ('tinh_tec','kiem_ke') then raise exception 'Loại kỳ không hợp lệ.'; end if;
  if p_start_date is null then raise exception 'Chọn ngày bắt đầu.'; end if;
  if exists (select 1 from stock_period where tank_id = p_tank_id and status = 'Mo') then
    raise exception 'Téc đã có một kỳ đang mở. Chốt kỳ đó trước.'; end if;
  insert into stock_period (tank_id, kind, start_date, note, created_by)
  values (p_tank_id, p_kind, p_start_date, nullif(trim(coalesce(p_note,'')),''), v_actor.id)
  returning * into v_row;
  perform write_audit(v_actor, 'CREATE_STOCK_PERIOD', 'stock_period', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;

-- Sửa kỳ đang Mo.
create or replace function rpc_stock_period_update(
  p_id uuid, p_tank_id uuid, p_kind text, p_start_date date, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur stock_period; v_before jsonb; v_row stock_period;
begin
  v_actor := require_permission('adjust:manage');
  select * into v_cur from stock_period where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy kỳ.'; end if;
  if v_cur.status <> 'Mo' then raise exception 'Chỉ sửa được kỳ đang mở.'; end if;
  if p_tank_id is null or not exists (select 1 from tanks where id = p_tank_id and active) then
    raise exception 'Téc không hợp lệ hoặc đã ngừng.'; end if;
  if p_kind not in ('tinh_tec','kiem_ke') then raise exception 'Loại kỳ không hợp lệ.'; end if;
  if p_start_date is null then raise exception 'Chọn ngày bắt đầu.'; end if;
  if p_tank_id <> v_cur.tank_id and exists (select 1 from stock_period where tank_id = p_tank_id and status = 'Mo') then
    raise exception 'Téc đã có một kỳ đang mở.'; end if;
  v_before := to_jsonb(v_cur);
  update stock_period set tank_id = p_tank_id, kind = p_kind, start_date = p_start_date,
    note = nullif(trim(coalesce(p_note,'')),'') where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_STOCK_PERIOD', 'stock_period', p_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Xóa kỳ đang Mo.
create or replace function rpc_stock_period_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur stock_period;
begin
  v_actor := require_permission('adjust:manage');
  select * into v_cur from stock_period where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy kỳ.'; end if;
  if v_cur.status <> 'Mo' then raise exception 'Chỉ xóa được kỳ đang mở.'; end if;
  delete from stock_period where id = p_id;
  perform write_audit(v_actor, 'DELETE_STOCK_PERIOD', 'stock_period', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- CHỐT kỳ: nhập Tồn thực tế → tính tịnh âm/dương + phân bổ cho xe. Cấp Số kỳ.
-- ----------------------------------------------------------------------------
create or replace function rpc_stock_period_close(
  p_id uuid, p_actual_liters numeric, p_close_date date default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_actor profiles; v_cur stock_period; v_close date := coalesce(p_close_date, current_date);
  v_book numeric; v_diff numeric; v_am numeric; v_duong numeric; v_total numeric;
  v_rec record; v_sum_am numeric := 0; v_sum_duong numeric := 0; v_max_veh uuid; v_a numeric; v_d numeric;
begin
  v_actor := require_permission('adjust:manage');
  select * into v_cur from stock_period where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy kỳ.'; end if;
  if v_cur.status <> 'Mo' then raise exception 'Kỳ đã chốt.'; end if;
  if p_actual_liters is null or p_actual_liters < 0 then raise exception 'Tồn thực tế không hợp lệ.'; end if;
  if v_close < v_cur.start_date then raise exception 'Ngày chốt phải ≥ ngày bắt đầu.'; end if;

  v_book := tank_book_before(v_cur.tank_id, v_close);
  v_diff := round(v_book - p_actual_liters, 2);
  v_am := greatest(v_diff, 0);
  v_duong := greatest(-v_diff, 0);

  -- Tổng lít xe bơm (xuất) từ téc trong kỳ.
  select coalesce(sum(l.liters), 0) into v_total from ledger l
    join transaction_types tt on tt.id = l.txn_type_id
    where l.tank_id = v_cur.tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
      and l.vehicle_id is not null and (l.status = 'DaDuyet' or l.legacy)
      and l.entry_date between v_cur.start_date and v_close;

  update stock_period set actual_liters = p_actual_liters, book_liters = v_book,
    tinh_am = v_am, tinh_duong = v_duong, total_liters = v_total, close_date = v_close,
    status = 'DaChot', code = coalesce(v_cur.code, next_code_year('TINH')),
    closed_by = v_actor.id, closed_at = now()
  where id = p_id;

  -- Phân bổ theo tỉ lệ lít (chỉ khi có tịnh và có xe bơm).
  if v_total > 0 and (v_am > 0 or v_duong > 0) then
    for v_rec in
      select l.vehicle_id, sum(l.liters) as lit from ledger l
        join transaction_types tt on tt.id = l.txn_type_id
        where l.tank_id = v_cur.tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
          and l.vehicle_id is not null and (l.status = 'DaDuyet' or l.legacy)
          and l.entry_date between v_cur.start_date and v_close
        group by l.vehicle_id
        order by sum(l.liters) desc
    loop
      if v_max_veh is null then v_max_veh := v_rec.vehicle_id; end if;  -- xe lít lớn nhất
      v_a := round(v_am * v_rec.lit / v_total, 2);
      v_d := round(v_duong * v_rec.lit / v_total, 2);
      insert into stock_period_alloc (period_id, vehicle_id, liters_in_period, tinh_am, tinh_duong)
      values (p_id, v_rec.vehicle_id, v_rec.lit, v_a, v_d);
      v_sum_am := v_sum_am + v_a; v_sum_duong := v_sum_duong + v_d;
    end loop;
    -- Dồn phần dư làm tròn vào xe lít lớn nhất → tổng khớp tuyệt đối.
    if v_max_veh is not null then
      update stock_period_alloc
        set tinh_am = tinh_am + (v_am - v_sum_am), tinh_duong = tinh_duong + (v_duong - v_sum_duong)
        where period_id = p_id and vehicle_id = v_max_veh;
    end if;
  end if;

  perform write_audit(v_actor, 'CLOSE_STOCK_PERIOD', 'stock_period', p_id::text, to_jsonb(v_cur),
    jsonb_build_object('book', v_book, 'actual', p_actual_liters, 'tinhAm', v_am, 'tinhDuong', v_duong, 'totalLit', v_total));
  return jsonb_build_object('ok', true, 'id', p_id, 'tinhAm', v_am, 'tinhDuong', v_duong, 'book', v_book);
end;
$$;

-- Danh sách kỳ.
create or replace function rpc_stock_period_list()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('adjust:manage');
  select coalesce(jsonb_agg(r order by r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', sp.id, 'code', sp.code, 'tankId', sp.tank_id, 'tankName', tk.name, 'kind', sp.kind,
      'startDate', to_char(sp.start_date,'YYYY-MM-DD'), 'closeDate', to_char(sp.close_date,'YYYY-MM-DD'),
      'actual', sp.actual_liters, 'book', sp.book_liters, 'tinhAm', sp.tinh_am, 'tinhDuong', sp.tinh_duong,
      'totalLiters', sp.total_liters, 'status', sp.status, 'note', sp.note
    ) as r, sp.created_at as r_created
    from stock_period sp left join tanks tk on tk.id = sp.tank_id
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Chi tiết phân bổ của một kỳ.
create or replace function rpc_stock_period_detail(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('adjust:manage');
  select coalesce(jsonb_agg(jsonb_build_object(
    'vehicleId', a.vehicle_id, 'plate', v.plate, 'litersInPeriod', a.liters_in_period,
    'tinhAm', a.tinh_am, 'tinhDuong', a.tinh_duong
  ) order by a.liters_in_period desc), '[]'::jsonb) into v_rows
  from stock_period_alloc a left join vehicles v on v.id = a.vehicle_id
  where a.period_id = p_id;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- ----------------------------------------------------------------------------
-- OVERRIDE rpc_inventory_stock (S5): cộng −Tịnh âm +Tịnh dương của các kỳ ĐÃ CHỐT.
--   Tồn cuối = Tồn đầu + Nhập − Xuất − Σtịnh âm + Σtịnh dương.
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
      'tinhAm', coalesce(aj.am, 0),
      'tinhDuong', coalesce(aj.duong, 0),
      'adjust', coalesce(aj.duong, 0) - coalesce(aj.am, 0),
      'closing', coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0)
                 - coalesce(aj.am,0) + coalesce(aj.duong,0),
      'pctFull', case when t.capacity_liters > 0
        then round((coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0)
                    - coalesce(aj.am,0) + coalesce(aj.duong,0)) / t.capacity_liters * 100, 1)
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
    left join lateral (
      select sum(sp.tinh_am) am, sum(sp.tinh_duong) duong from stock_period sp
       where sp.tank_id = t.id and sp.status = 'DaChot'
    ) aj on true
    where t.active
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_stock_period_create(uuid, text, date, text) to authenticated;
grant execute on function rpc_stock_period_update(uuid, uuid, text, date, text) to authenticated;
grant execute on function rpc_stock_period_delete(uuid) to authenticated;
grant execute on function rpc_stock_period_close(uuid, numeric, date) to authenticated;
grant execute on function rpc_stock_period_list() to authenticated;
grant execute on function rpc_stock_period_detail(uuid) to authenticated;
