-- ============================================================================
-- 0007_pump_ledger.sql — S2 Sổ cái (ledger) + vòng đời Phiếu bơm.
-- Một bảng `ledger` = mọi bút toán (S2: entry_type='bom'; S4 thêm 'nhap').
-- Máy trạng thái: Nhap → (Submit ngày) → ChoDoiChieu → DaDuyet | (Lệch → về Nhap).
-- "Lệch/TraVe" thu gọn thành status='Nhap' + reject_reason (đúng "về Nhap của
-- người tạo kèm lý do"). Chỉ bút toán DaDuyet (hoặc legacy) tính vào tồn kho (S5).
-- Deny-by-default + RPC SECURITY DEFINER + require_permission. KHÔNG sửa migration cũ.
-- ============================================================================

create table if not exists ledger (
  id uuid primary key default gen_random_uuid(),
  code text unique,                         -- Số phiếu BOM-YYYY-######; cấp lúc Submit
  entry_type text not null default 'bom' check (entry_type in ('bom','nhap','adjust')),
  entry_date date not null default current_date,   -- Ngày nghiệp vụ (ngày bơm)
  vehicle_id uuid references vehicles (id),
  txn_type_id uuid references transaction_types (id),
  tank_id uuid references tanks (id),        -- null khi Bơm ngoài (không gắn téc kho)
  oil_type_id uuid references oil_types (id),
  liters numeric(14,2) not null default 0 check (liters >= 0),
  km_old numeric(14,1),
  km_new numeric(14,1),
  km_run numeric(14,1) generated always as (
    case when km_new is not null and km_old is not null then km_new - km_old else null end
  ) stored,
  supplier_id uuid references suppliers (id),  -- tùy chọn (Bơm ngoài)
  unit_price numeric(14,2),                    -- tùy chọn
  note text,
  status text not null default 'Nhap' check (status in ('Nhap','ChoDoiChieu','DaDuyet')),
  reject_reason text,                          -- lý do bị trả về (khi Lệch → về Nhap)
  legacy boolean not null default false,       -- bút toán migrate: coi như đã chốt
  created_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_by uuid references profiles (id),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table ledger is 'Sổ cái append-only. Nháp sửa được tới khi Submit; DaDuyet/legacy là bất biến và tính vào tồn kho.';

create index if not exists ledger_status_idx      on ledger (status);
create index if not exists ledger_creator_idx      on ledger (created_by, status);
create index if not exists ledger_vehicle_km_idx    on ledger (vehicle_id, entry_date, created_at);
create index if not exists ledger_tank_date_idx     on ledger (tank_id, entry_date);

create or replace trigger trg_ledger_updated before update on ledger for each row execute function set_updated_at();

alter table ledger enable row level security;
revoke all on ledger from anon, authenticated;

-- ----------------------------------------------------------------------------
-- Helper nội bộ: lấy loại giao dịch (kind) — quyết định có gắn téc hay không.
-- ----------------------------------------------------------------------------
create or replace function txn_kind(p_txn_type_id uuid) returns text
language sql stable set search_path = public, pg_temp as $$
  select kind from transaction_types where id = p_txn_type_id;
$$;

-- KM mới gần nhất của một Xe (để tự điền KM cũ). Chỉ tính phiếu chưa xóa.
create or replace function rpc_vehicle_last_km(p_vehicle_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_km numeric;
begin
  perform require_permission('pump:create');
  select km_new into v_km from ledger
   where vehicle_id = p_vehicle_id and km_new is not null and entry_type = 'bom'
   order by entry_date desc, created_at desc limit 1;
  return jsonb_build_object('ok', true, 'kmOld', v_km);
end;
$$;

-- ----------------------------------------------------------------------------
-- Validate + chuẩn hóa input phiếu bơm (dùng chung create/update).
-- ----------------------------------------------------------------------------
create or replace function pump_validate(
  p_vehicle_id uuid, p_txn_type_id uuid, p_tank_id uuid, p_oil_type_id uuid,
  p_liters numeric, p_km_old numeric, p_km_new numeric
) returns text
language plpgsql stable set search_path = public, pg_temp as $$
declare v_kind text; v_has_odo boolean;
begin
  if p_vehicle_id is null then return 'Chọn xe.'; end if;
  if not exists (select 1 from vehicles where id = p_vehicle_id and active) then return 'Xe không hợp lệ hoặc đã ngừng.'; end if;
  if p_oil_type_id is null then return 'Chọn loại dầu.'; end if;
  if not exists (select 1 from oil_types where id = p_oil_type_id and active) then return 'Loại dầu không hợp lệ.'; end if;
  v_kind := txn_kind(p_txn_type_id);
  if v_kind is null then return 'Chọn loại giao dịch.'; end if;
  if v_kind = 'nhap' then return 'Loại giao dịch nhập kho dùng ở màn Phiếu nhập.'; end if;
  if v_kind = 'bom_ngoai' then
    if p_tank_id is not null then return 'Bơm ngoài không gắn téc kho.'; end if;
  else
    if p_tank_id is null then return 'Chọn téc.'; end if;
    if not exists (select 1 from tanks where id = p_tank_id and active) then return 'Téc không hợp lệ hoặc đã ngừng.'; end if;
  end if;
  if coalesce(p_liters,0) <= 0 then return 'Số lít phải lớn hơn 0.'; end if;
  select has_odometer into v_has_odo from vehicles where id = p_vehicle_id;
  -- KM có thể trống cho thiết bị không công-tơ-mét; nếu có cả hai thì không được lùi.
  if p_km_new is not null and p_km_old is not null and p_km_new < p_km_old then
    return 'KM mới nhỏ hơn KM cũ.';
  end if;
  return null;  -- hợp lệ
end;
$$;

-- ----------------------------------------------------------------------------
-- Tạo phiếu bơm (Nhap). KM cũ tự lấy từ lần bơm gần nhất nếu bỏ trống.
-- ----------------------------------------------------------------------------
create or replace function rpc_pump_create(
  p_vehicle_id uuid, p_txn_type_id uuid, p_oil_type_id uuid, p_liters numeric,
  p_tank_id uuid default null, p_km_new numeric default null, p_km_old numeric default null,
  p_supplier_id uuid default null, p_unit_price numeric default null,
  p_entry_date date default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_err text; v_km_old numeric := p_km_old; v_row ledger;
begin
  v_actor := require_permission('pump:create');
  if p_km_old is null and exists (select 1 from vehicles where id = p_vehicle_id and has_odometer) then
    select km_new into v_km_old from ledger
     where vehicle_id = p_vehicle_id and km_new is not null and entry_type = 'bom'
     order by entry_date desc, created_at desc limit 1;
  end if;
  v_err := pump_validate(p_vehicle_id, p_txn_type_id, p_tank_id, p_oil_type_id, p_liters, v_km_old, p_km_new);
  if v_err is not null then raise exception '%', v_err; end if;

  insert into ledger (entry_type, entry_date, vehicle_id, txn_type_id, tank_id, oil_type_id,
    liters, km_old, km_new, supplier_id, unit_price, note, status, created_by)
  values ('bom', coalesce(p_entry_date, current_date), p_vehicle_id, p_txn_type_id,
    case when txn_kind(p_txn_type_id) = 'bom_ngoai' then null else p_tank_id end,
    p_oil_type_id, p_liters, v_km_old, p_km_new, p_supplier_id, p_unit_price,
    nullif(trim(coalesce(p_note,'')),''), 'Nhap', v_actor.id)
  returning * into v_row;

  perform write_audit(v_actor, 'CREATE_PUMP', 'ledger', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;

-- Sửa phiếu Nhap (chỉ người tạo, chỉ khi còn Nhap). Xóa lý do trả về nếu có.
create or replace function rpc_pump_update(
  p_id uuid, p_vehicle_id uuid, p_txn_type_id uuid, p_oil_type_id uuid, p_liters numeric,
  p_tank_id uuid default null, p_km_new numeric default null, p_km_old numeric default null,
  p_supplier_id uuid default null, p_unit_price numeric default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_before jsonb; v_err text; v_row ledger; v_cur ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được sửa phiếu.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ sửa được phiếu ở trạng thái Nháp.'; end if;
  v_err := pump_validate(p_vehicle_id, p_txn_type_id, p_tank_id, p_oil_type_id, p_liters, p_km_old, p_km_new);
  if v_err is not null then raise exception '%', v_err; end if;
  v_before := to_jsonb(v_cur);
  update ledger set vehicle_id = p_vehicle_id, txn_type_id = p_txn_type_id,
    tank_id = case when txn_kind(p_txn_type_id) = 'bom_ngoai' then null else p_tank_id end,
    oil_type_id = p_oil_type_id, liters = p_liters, km_old = p_km_old, km_new = p_km_new,
    supplier_id = p_supplier_id, unit_price = p_unit_price,
    note = nullif(trim(coalesce(p_note,'')),''), reject_reason = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_PUMP', 'ledger', p_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Xóa phiếu Nhap (chỉ người tạo, chỉ khi còn Nhap).
create or replace function rpc_pump_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được xóa phiếu.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ xóa được phiếu ở trạng thái Nháp.'; end if;
  delete from ledger where id = p_id;
  perform write_audit(v_actor, 'DELETE_PUMP', 'ledger', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Submit cả lô Nháp của tôi → ChoDoiChieu, cấp Số phiếu (nếu chưa có).
create or replace function rpc_pump_submit_day()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rec record; v_n integer := 0;
begin
  v_actor := require_permission('pump:create');
  for v_rec in
    select id, code from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'bom'
     order by entry_date, created_at
  loop
    update ledger set status = 'ChoDoiChieu', submitted_at = now(),
      code = coalesce(v_rec.code, next_code_year('BOM')), reject_reason = null
    where id = v_rec.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Không có phiếu Nháp nào để submit.'; end if;
  perform write_audit(v_actor, 'SUBMIT_PUMP_DAY', 'ledger', null, null,
    jsonb_build_object('count', v_n));
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

-- Rút lại phiếu ChoDoiChieu về Nhap (chỉ khi chưa ai đối chiếu). Giữ Số phiếu.
create or replace function rpc_pump_withdraw(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được rút lại phiếu.'; end if;
  if v_cur.status <> 'ChoDoiChieu' then raise exception 'Chỉ rút lại được phiếu đang Chờ đối chiếu.'; end if;
  if v_cur.reviewed_by is not null then raise exception 'Phiếu đã được đối chiếu, không thể rút lại.'; end if;
  update ledger set status = 'Nhap', submitted_at = null where id = p_id;
  perform write_audit(v_actor, 'WITHDRAW_PUMP', 'ledger', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Danh sách phiếu của tôi (Nháp + Chờ đối chiếu) để rà soát/submit/rút lại.
create or replace function rpc_pump_list_mine()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rows jsonb;
begin
  v_actor := require_permission('pump:create');
  select coalesce(jsonb_agg(r order by r_created), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'status', l.status, 'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'vehicleId', l.vehicle_id, 'plate', v.plate, 'txnTypeId', l.txn_type_id, 'txnName', tt.name, 'txnKind', tt.kind,
      'tankId', l.tank_id, 'tankName', tk.name, 'oilTypeId', l.oil_type_id, 'oilTypeName', ot.name,
      'liters', l.liters, 'kmOld', l.km_old, 'kmNew', l.km_new, 'kmRun', l.km_run,
      'supplierId', l.supplier_id, 'unitPrice', l.unit_price, 'note', l.note, 'rejectReason', l.reject_reason
    ) as r, l.created_at as r_created
    from ledger l
    left join vehicles v on v.id = l.vehicle_id
    left join transaction_types tt on tt.id = l.txn_type_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    where l.created_by = v_actor.id and l.entry_type = 'bom' and l.status in ('Nhap','ChoDoiChieu')
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Hàng đợi đối chiếu: phiếu ChoDoiChieu của người KHÁC (chặn tự-duyệt ngay ở đây).
create or replace function rpc_pump_review_queue()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rows jsonb;
begin
  v_actor := require_permission('pump:review');
  select coalesce(jsonb_agg(r order by r_created), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'plate', v.plate, 'txnName', tt.name, 'txnKind', tt.kind, 'tankName', tk.name, 'oilTypeName', ot.name,
      'liters', l.liters, 'kmOld', l.km_old, 'kmNew', l.km_new, 'kmRun', l.km_run,
      'note', l.note, 'createdBy', p.name, 'submittedAt', to_char(l.submitted_at,'YYYY-MM-DD HH24:MI')
    ) as r, l.submitted_at as r_created
    from ledger l
    left join vehicles v on v.id = l.vehicle_id
    left join transaction_types tt on tt.id = l.txn_type_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    left join profiles p on p.id = l.created_by
    where l.status = 'ChoDoiChieu' and l.entry_type = 'bom' and l.created_by <> v_actor.id
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Khớp → DaDuyet (vào tồn kho/báo cáo). Không được duyệt phiếu của chính mình.
create or replace function rpc_pump_approve(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row ledger;
begin
  v_actor := require_permission('pump:review');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.status <> 'ChoDoiChieu' then raise exception 'Chỉ đối chiếu được phiếu đang Chờ đối chiếu.'; end if;
  if v_cur.created_by = v_actor.id then raise exception 'Không được tự đối chiếu phiếu do mình tạo.'; end if;
  update ledger set status = 'DaDuyet', reviewed_by = v_actor.id, reviewed_at = now(), reject_reason = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'APPROVE_PUMP', 'ledger', p_id::text, to_jsonb(v_cur), to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Lệch → về Nhap của người tạo kèm lý do. Không được xử phiếu của chính mình.
create or replace function rpc_pump_reject(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row ledger; v_reason text := trim(coalesce(p_reason,''));
begin
  v_actor := require_permission('pump:review');
  if v_reason = '' then raise exception 'Nhập lý do trả về.'; end if;
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.status <> 'ChoDoiChieu' then raise exception 'Chỉ đối chiếu được phiếu đang Chờ đối chiếu.'; end if;
  if v_cur.created_by = v_actor.id then raise exception 'Không được tự đối chiếu phiếu do mình tạo.'; end if;
  update ledger set status = 'Nhap', reject_reason = v_reason,
    reviewed_by = v_actor.id, reviewed_at = now(), submitted_at = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'REJECT_PUMP', 'ledger', p_id::text, to_jsonb(v_cur), to_jsonb(v_row), 'OK', v_reason);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

grant execute on function rpc_vehicle_last_km(uuid) to authenticated;
grant execute on function rpc_pump_create(uuid, uuid, uuid, numeric, uuid, numeric, numeric, uuid, numeric, date, text) to authenticated;
grant execute on function rpc_pump_update(uuid, uuid, uuid, uuid, numeric, uuid, numeric, numeric, uuid, numeric, text) to authenticated;
grant execute on function rpc_pump_delete(uuid) to authenticated;
grant execute on function rpc_pump_submit_day() to authenticated;
grant execute on function rpc_pump_withdraw(uuid) to authenticated;
grant execute on function rpc_pump_list_mine() to authenticated;
grant execute on function rpc_pump_review_queue() to authenticated;
grant execute on function rpc_pump_approve(uuid) to authenticated;
grant execute on function rpc_pump_reject(uuid, text) to authenticated;
