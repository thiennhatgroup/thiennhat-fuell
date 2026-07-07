-- Batch 2 (S-uplift): cho phép sửa Ngày nghiệp vụ (entry_date) trên phiếu Nháp.
-- rpc_pump_create / rpc_nhap_create đã nhận p_entry_date; bổ sung cho hai RPC update.
-- Thêm tham số ⇒ đổi chữ ký ⇒ phải DROP chữ ký cũ trước khi tạo lại (tránh nhập nhằng overload).

-- ---------- Phiếu bơm ----------
drop function if exists rpc_pump_update(uuid, uuid, uuid, uuid, numeric, uuid, numeric, numeric, uuid, numeric, text);

create or replace function rpc_pump_update(
  p_id uuid, p_vehicle_id uuid, p_txn_type_id uuid, p_oil_type_id uuid, p_liters numeric,
  p_tank_id uuid default null, p_km_new numeric default null, p_km_old numeric default null,
  p_supplier_id uuid default null, p_unit_price numeric default null, p_note text default null,
  p_entry_date date default null
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
    entry_date = coalesce(p_entry_date, entry_date),
    note = nullif(trim(coalesce(p_note,'')),''), reject_reason = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_PUMP', 'ledger', p_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

grant execute on function rpc_pump_update(uuid, uuid, uuid, uuid, numeric, uuid, numeric, numeric, uuid, numeric, text, date) to authenticated;

-- ---------- Phiếu nhập ----------
drop function if exists rpc_nhap_update(uuid, uuid, uuid, uuid, numeric, numeric, text, text);

create or replace function rpc_nhap_update(
  p_id uuid, p_supplier_id uuid, p_tank_id uuid, p_oil_type_id uuid, p_liters numeric, p_unit_price numeric,
  p_supplier_invoice_no text default null, p_note text default null, p_entry_date date default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_before jsonb; v_err text; v_row ledger; v_cur ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Không phải phiếu nhập.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được sửa phiếu.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ sửa được phiếu ở trạng thái Nháp.'; end if;
  v_err := nhap_validate(p_supplier_id, p_tank_id, p_oil_type_id, p_liters, p_unit_price);
  if v_err is not null then raise exception '%', v_err; end if;
  v_before := to_jsonb(v_cur);
  update ledger set supplier_id = p_supplier_id, tank_id = p_tank_id, oil_type_id = p_oil_type_id,
    liters = p_liters, unit_price = p_unit_price,
    supplier_invoice_no = nullif(trim(coalesce(p_supplier_invoice_no,'')),''),
    entry_date = coalesce(p_entry_date, entry_date),
    note = nullif(trim(coalesce(p_note,'')),''), reject_reason = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_NHAP', 'ledger', p_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

grant execute on function rpc_nhap_update(uuid, uuid, uuid, uuid, numeric, numeric, text, text, date) to authenticated;
