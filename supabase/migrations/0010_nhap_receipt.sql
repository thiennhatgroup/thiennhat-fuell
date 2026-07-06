-- ============================================================================
-- 0010_nhap_receipt.sql — S4 Phiếu nhập (NHAP): nhập dầu về téc.
-- Tái dùng nguyên máy trạng thái + đối chiếu chéo + ảnh của S2/S3, nhưng cho
-- bút toán entry_type='nhap'. Vòng đời: Nhap → (Submit ngày, cấp Số phiếu
-- NHAP-YYYY-######) → ChoDoiChieu → DaDuyet | (Lệch → về Nhap + reject_reason).
-- Chỉ DaDuyet/legacy tính vào tồn kho (S5). Ảnh phiếu nhập (kind 'receipt') bắt
-- buộc ≥1 trước Submit. Vai trò dùng chung với phiếu bơm: ThuKho tạo
-- (pump:create), ThuKho KHÁC đối chiếu (pump:review) — cùng người kho.
-- Deny-by-default + RPC SECURITY DEFINER + require_permission. KHÔNG sửa migration cũ.
-- ============================================================================

-- Số hóa đơn NCC: nhập tay, KHÁC Số phiếu tự cấp (NHAP-YYYY-######).
alter table ledger add column if not exists supplier_invoice_no text;

-- Cho phép ảnh loại 'receipt' (phiếu nhập) bên cạnh 'pump_meter'/'odometer'.
alter table pump_photos drop constraint if exists pump_photos_kind_check;
alter table pump_photos add constraint pump_photos_kind_check
  check (kind in ('pump_meter','odometer','receipt'));

-- ----------------------------------------------------------------------------
-- Validate + chuẩn hóa input phiếu nhập (dùng chung create/update).
-- ----------------------------------------------------------------------------
create or replace function nhap_validate(
  p_supplier_id uuid, p_tank_id uuid, p_oil_type_id uuid,
  p_liters numeric, p_unit_price numeric
) returns text
language plpgsql stable set search_path = public, pg_temp as $$
begin
  if p_supplier_id is null then return 'Chọn nhà cung cấp.'; end if;
  if not exists (select 1 from suppliers where id = p_supplier_id and active) then return 'Nhà cung cấp không hợp lệ hoặc đã ngừng.'; end if;
  if p_tank_id is null then return 'Chọn téc nhận.'; end if;
  if not exists (select 1 from tanks where id = p_tank_id and active) then return 'Téc không hợp lệ hoặc đã ngừng.'; end if;
  if p_oil_type_id is null then return 'Chọn loại dầu.'; end if;
  if not exists (select 1 from oil_types where id = p_oil_type_id and active) then return 'Loại dầu không hợp lệ.'; end if;
  if coalesce(p_liters,0) <= 0 then return 'Số lít phải lớn hơn 0.'; end if;
  if coalesce(p_unit_price,0) <= 0 then return 'Đơn giá phải lớn hơn 0.'; end if;
  return null;  -- hợp lệ
end;
$$;

-- ----------------------------------------------------------------------------
-- Tạo phiếu nhập (Nhap).
-- ----------------------------------------------------------------------------
create or replace function rpc_nhap_create(
  p_supplier_id uuid, p_tank_id uuid, p_oil_type_id uuid, p_liters numeric, p_unit_price numeric,
  p_supplier_invoice_no text default null, p_entry_date date default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_err text; v_row ledger;
begin
  v_actor := require_permission('pump:create');
  v_err := nhap_validate(p_supplier_id, p_tank_id, p_oil_type_id, p_liters, p_unit_price);
  if v_err is not null then raise exception '%', v_err; end if;

  insert into ledger (entry_type, entry_date, tank_id, oil_type_id, liters, supplier_id,
    unit_price, supplier_invoice_no, note, status, created_by)
  values ('nhap', coalesce(p_entry_date, current_date), p_tank_id, p_oil_type_id, p_liters,
    p_supplier_id, p_unit_price, nullif(trim(coalesce(p_supplier_invoice_no,'')),''),
    nullif(trim(coalesce(p_note,'')),''), 'Nhap', v_actor.id)
  returning * into v_row;

  perform write_audit(v_actor, 'CREATE_NHAP', 'ledger', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;

-- Sửa phiếu Nhap (chỉ người tạo, chỉ khi còn Nhap). Xóa lý do trả về nếu có.
create or replace function rpc_nhap_update(
  p_id uuid, p_supplier_id uuid, p_tank_id uuid, p_oil_type_id uuid, p_liters numeric, p_unit_price numeric,
  p_supplier_invoice_no text default null, p_note text default null
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
    note = nullif(trim(coalesce(p_note,'')),''), reject_reason = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_NHAP', 'ledger', p_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Xóa phiếu Nhap (chỉ người tạo, chỉ khi còn Nhap).
create or replace function rpc_nhap_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Không phải phiếu nhập.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được xóa phiếu.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ xóa được phiếu ở trạng thái Nháp.'; end if;
  delete from ledger where id = p_id;
  perform write_audit(v_actor, 'DELETE_NHAP', 'ledger', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Submit cả lô Nháp nhập của tôi → ChoDoiChieu, cấp Số phiếu NHAP (nếu chưa có).
-- Chặn phiếu thiếu ảnh phiếu nhập (≥1 'receipt'); validate CẢ LÔ trước khi cấp số.
create or replace function rpc_nhap_submit_day()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rec record; v_n integer := 0;
begin
  v_actor := require_permission('pump:create');
  for v_rec in
    select id, code from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'nhap'
  loop
    if not exists (select 1 from pump_photos where ledger_id = v_rec.id and kind = 'receipt') then
      raise exception 'Phiếu % thiếu ảnh phiếu nhập.', coalesce(v_rec.code, '(nháp)');
    end if;
  end loop;

  for v_rec in
    select id, code from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'nhap'
     order by entry_date, created_at
  loop
    update ledger set status = 'ChoDoiChieu', submitted_at = now(),
      code = coalesce(v_rec.code, next_code_year('NHAP')), reject_reason = null
    where id = v_rec.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Không có phiếu Nháp nào để submit.'; end if;
  perform write_audit(v_actor, 'SUBMIT_NHAP_DAY', 'ledger', null, null, jsonb_build_object('count', v_n));
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

-- Rút lại phiếu ChoDoiChieu về Nhap (chỉ khi chưa ai đối chiếu). Giữ Số phiếu.
create or replace function rpc_nhap_withdraw(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Không phải phiếu nhập.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được rút lại phiếu.'; end if;
  if v_cur.status <> 'ChoDoiChieu' then raise exception 'Chỉ rút lại được phiếu đang Chờ đối chiếu.'; end if;
  if v_cur.reviewed_by is not null then raise exception 'Phiếu đã được đối chiếu, không thể rút lại.'; end if;
  update ledger set status = 'Nhap', submitted_at = null where id = p_id;
  perform write_audit(v_actor, 'WITHDRAW_NHAP', 'ledger', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Danh sách phiếu nhập của tôi (Nháp + Chờ đối chiếu).
create or replace function rpc_nhap_list_mine()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rows jsonb;
begin
  v_actor := require_permission('pump:create');
  select coalesce(jsonb_agg(r order by r_created), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'status', l.status, 'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'supplierId', l.supplier_id, 'supplierName', s.name, 'tankId', l.tank_id, 'tankName', tk.name,
      'oilTypeId', l.oil_type_id, 'oilTypeName', ot.name, 'liters', l.liters, 'unitPrice', l.unit_price,
      'amount', round(coalesce(l.liters,0) * coalesce(l.unit_price,0), 2),
      'supplierInvoiceNo', l.supplier_invoice_no, 'note', l.note, 'rejectReason', l.reject_reason
    ) as r, l.created_at as r_created
    from ledger l
    left join suppliers s on s.id = l.supplier_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    where l.created_by = v_actor.id and l.entry_type = 'nhap' and l.status in ('Nhap','ChoDoiChieu')
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Hàng đợi đối chiếu: phiếu nhập ChoDoiChieu của người KHÁC (chặn tự-duyệt).
create or replace function rpc_nhap_review_queue()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rows jsonb;
begin
  v_actor := require_permission('pump:review');
  select coalesce(jsonb_agg(r order by r_created), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'supplierName', s.name, 'tankName', tk.name, 'oilTypeName', ot.name,
      'liters', l.liters, 'unitPrice', l.unit_price,
      'amount', round(coalesce(l.liters,0) * coalesce(l.unit_price,0), 2),
      'supplierInvoiceNo', l.supplier_invoice_no, 'note', l.note, 'createdBy', p.name,
      'submittedAt', to_char(l.submitted_at,'YYYY-MM-DD HH24:MI')
    ) as r, l.submitted_at as r_created
    from ledger l
    left join suppliers s on s.id = l.supplier_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    left join profiles p on p.id = l.created_by
    where l.status = 'ChoDoiChieu' and l.entry_type = 'nhap' and l.created_by <> v_actor.id
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Khớp → DaDuyet (vào tồn kho/báo cáo). Không được duyệt phiếu của chính mình.
create or replace function rpc_nhap_approve(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row ledger;
begin
  v_actor := require_permission('pump:review');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Không phải phiếu nhập.'; end if;
  if v_cur.status <> 'ChoDoiChieu' then raise exception 'Chỉ đối chiếu được phiếu đang Chờ đối chiếu.'; end if;
  if v_cur.created_by = v_actor.id then raise exception 'Không được tự đối chiếu phiếu do mình tạo.'; end if;
  update ledger set status = 'DaDuyet', reviewed_by = v_actor.id, reviewed_at = now(), reject_reason = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'APPROVE_NHAP', 'ledger', p_id::text, to_jsonb(v_cur), to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Lệch → về Nhap của người tạo kèm lý do. Không được xử phiếu của chính mình.
create or replace function rpc_nhap_reject(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row ledger; v_reason text := trim(coalesce(p_reason,''));
begin
  v_actor := require_permission('pump:review');
  if v_reason = '' then raise exception 'Nhập lý do trả về.'; end if;
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Không phải phiếu nhập.'; end if;
  if v_cur.status <> 'ChoDoiChieu' then raise exception 'Chỉ đối chiếu được phiếu đang Chờ đối chiếu.'; end if;
  if v_cur.created_by = v_actor.id then raise exception 'Không được tự đối chiếu phiếu do mình tạo.'; end if;
  update ledger set status = 'Nhap', reject_reason = v_reason,
    reviewed_by = v_actor.id, reviewed_at = now(), submitted_at = null
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'REJECT_NHAP', 'ledger', p_id::text, to_jsonb(v_cur), to_jsonb(v_row), 'OK', v_reason);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- Ảnh phiếu nhập (kind 'receipt'). Cùng bucket riêng tư 'chung-tu', cùng helper
-- Storage (chungtu_can_upload gate 'pump:create' — ThuKho có sẵn). Chỉ người
-- tạo, chỉ khi phiếu còn Nháp; đường dẫn phải thuộc "thư mục" của phiếu.
-- ----------------------------------------------------------------------------
create or replace function rpc_nhap_photo_add(p_ledger_id uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row pump_photos; v_path text := trim(coalesce(p_path,''));
begin
  v_actor := require_permission('pump:create');
  if v_path = '' then raise exception 'Thiếu đường dẫn ảnh.'; end if;
  select * into v_cur from ledger where id = p_ledger_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Chỉ đính ảnh cho phiếu nhập.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được đính ảnh.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ đính ảnh khi phiếu còn Nháp.'; end if;
  if v_path <> p_ledger_id::text and v_path not like p_ledger_id::text || '/%' then
    raise exception 'Đường dẫn ảnh không thuộc phiếu này.';
  end if;
  insert into pump_photos (ledger_id, kind, storage_path, created_by)
  values (p_ledger_id, 'receipt', v_path, v_actor.id)
  returning * into v_row;
  perform write_audit(v_actor, 'ADD_NHAP_PHOTO', 'pump_photos', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;

-- Xóa metadata ảnh phiếu nhập (chỉ người tạo, chỉ khi Nháp). Trả path để FE xóa object.
create or replace function rpc_nhap_photo_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur pump_photos; v_led ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from pump_photos where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy ảnh.'; end if;
  select * into v_led from ledger where id = v_cur.ledger_id;
  if v_led.entry_type <> 'nhap' then raise exception 'Không phải ảnh phiếu nhập.'; end if;
  if v_led.created_by <> v_actor.id then raise exception 'Chỉ người tạo được xóa ảnh.'; end if;
  if v_led.status <> 'Nhap' then raise exception 'Chỉ xóa ảnh khi phiếu còn Nháp.'; end if;
  delete from pump_photos where id = p_id;
  perform write_audit(v_actor, 'DELETE_NHAP_PHOTO', 'pump_photos', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id, 'path', v_cur.storage_path);
end;
$$;

-- Danh sách ảnh của một phiếu nhập (cho người nhập lẫn người đối chiếu).
create or replace function rpc_nhap_photo_list(p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('pump:create');
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'path', storage_path
  ) order by created_at), '[]'::jsonb) into v_rows
  from pump_photos where ledger_id = p_ledger_id and kind = 'receipt';
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_nhap_create(uuid, uuid, uuid, numeric, numeric, text, date, text) to authenticated;
grant execute on function rpc_nhap_update(uuid, uuid, uuid, uuid, numeric, numeric, text, text) to authenticated;
grant execute on function rpc_nhap_delete(uuid) to authenticated;
grant execute on function rpc_nhap_submit_day() to authenticated;
grant execute on function rpc_nhap_withdraw(uuid) to authenticated;
grant execute on function rpc_nhap_list_mine() to authenticated;
grant execute on function rpc_nhap_review_queue() to authenticated;
grant execute on function rpc_nhap_approve(uuid) to authenticated;
grant execute on function rpc_nhap_reject(uuid, text) to authenticated;
grant execute on function rpc_nhap_photo_add(uuid, text) to authenticated;
grant execute on function rpc_nhap_photo_delete(uuid) to authenticated;
grant execute on function rpc_nhap_photo_list(uuid) to authenticated;
