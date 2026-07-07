-- ============================================================================
-- 0018 — Batch 3: Phiếu nhập
--   (a) Bắt buộc 2 loại ảnh: Biên bản giao nhận + Phiếu nhập kho.
--   (b) Submit ngày = DUYỆT THẲNG vào tồn (bỏ đối chiếu chéo cho phiếu nhập;
--       phiếu bơm vẫn giữ đối chiếu chéo như cũ).
--   (c) Đường dẫn ảnh chuyển sang folder theo tháng: <YYYY-MM>/<ledger_id>/...
--       (áp cho cả ảnh bơm & ảnh nhập). Validate: ledger_id phải là 1 segment.
-- KHÔNG sửa migration cũ.
-- ============================================================================

-- (a) Thêm 2 loại ảnh phiếu nhập vào ràng buộc kind (giữ các loại cũ).
alter table pump_photos drop constraint if exists pump_photos_kind_check;
alter table pump_photos add constraint pump_photos_kind_check
  check (kind in ('pump_meter','odometer','receipt','bien_ban_giao_nhan','phieu_nhap_kho'));

-- ----------------------------------------------------------------------------
-- (c) Ảnh bơm: nới validate đường dẫn để chấp nhận folder theo tháng.
--     Chấp nhận cả path cũ (<ledger_id>/...) lẫn mới (<YYYY-MM>/<ledger_id>/...).
-- ----------------------------------------------------------------------------
create or replace function rpc_pump_photo_add(p_ledger_id uuid, p_kind text, p_path text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row pump_photos; v_path text := trim(coalesce(p_path,''));
begin
  v_actor := require_permission('pump:create');
  if p_kind not in ('pump_meter','odometer') then raise exception 'Loại ảnh không hợp lệ.'; end if;
  if v_path = '' then raise exception 'Thiếu đường dẫn ảnh.'; end if;
  select * into v_cur from ledger where id = p_ledger_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'bom' then raise exception 'Chỉ đính ảnh cho phiếu bơm.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được đính ảnh.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ đính ảnh khi phiếu còn Nháp.'; end if;
  if position('/' || p_ledger_id::text || '/' in '/' || v_path || '/') = 0 then
    raise exception 'Đường dẫn ảnh không thuộc phiếu này.';
  end if;
  insert into pump_photos (ledger_id, kind, storage_path, created_by)
  values (p_ledger_id, p_kind, v_path, v_actor.id)
  returning * into v_row;
  perform write_audit(v_actor, 'ADD_PUMP_PHOTO', 'pump_photos', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;
grant execute on function rpc_pump_photo_add(uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- (a)+(c) Ảnh nhập: nhận p_kind (2 loại bắt buộc) + validate path theo segment.
--   Đổi chữ ký (thêm p_kind) ⇒ drop bản cũ trước.
-- ----------------------------------------------------------------------------
drop function if exists rpc_nhap_photo_add(uuid, text);
create or replace function rpc_nhap_photo_add(p_ledger_id uuid, p_kind text, p_path text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row pump_photos; v_path text := trim(coalesce(p_path,''));
begin
  v_actor := require_permission('pump:create');
  if p_kind not in ('bien_ban_giao_nhan','phieu_nhap_kho') then raise exception 'Loại ảnh không hợp lệ.'; end if;
  if v_path = '' then raise exception 'Thiếu đường dẫn ảnh.'; end if;
  select * into v_cur from ledger where id = p_ledger_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.entry_type <> 'nhap' then raise exception 'Chỉ đính ảnh cho phiếu nhập.'; end if;
  if v_cur.created_by <> v_actor.id then raise exception 'Chỉ người tạo được đính ảnh.'; end if;
  if v_cur.status <> 'Nhap' then raise exception 'Chỉ đính ảnh khi phiếu còn Nháp.'; end if;
  if position('/' || p_ledger_id::text || '/' in '/' || v_path || '/') = 0 then
    raise exception 'Đường dẫn ảnh không thuộc phiếu này.';
  end if;
  insert into pump_photos (ledger_id, kind, storage_path, created_by)
  values (p_ledger_id, p_kind, v_path, v_actor.id)
  returning * into v_row;
  perform write_audit(v_actor, 'ADD_NHAP_PHOTO', 'pump_photos', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;
grant execute on function rpc_nhap_photo_add(uuid, text, text) to authenticated;

-- Danh sách ảnh phiếu nhập: trả cả 2 loại mới (giữ 'receipt' cũ cho tương thích).
create or replace function rpc_nhap_photo_list(p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('pump:create');
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'path', storage_path
  ) order by kind, created_at), '[]'::jsonb) into v_rows
  from pump_photos
  where ledger_id = p_ledger_id and kind in ('bien_ban_giao_nhan','phieu_nhap_kho','receipt');
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- ----------------------------------------------------------------------------
-- (b) Submit ngày phiếu nhập = DUYỆT THẲNG (DaDuyet). Chặn nếu thiếu 1 trong 2
--     ảnh bắt buộc. Validate cả lô trước khi cấp Số phiếu + vào tồn.
-- ----------------------------------------------------------------------------
create or replace function rpc_nhap_submit_day()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rec record; v_n integer := 0;
begin
  v_actor := require_permission('pump:create');
  for v_rec in
    select id, code from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'nhap'
  loop
    if not exists (select 1 from pump_photos where ledger_id = v_rec.id and kind = 'bien_ban_giao_nhan') then
      raise exception 'Phiếu % thiếu ảnh Biên bản giao nhận.', coalesce(v_rec.code, '(nháp)');
    end if;
    if not exists (select 1 from pump_photos where ledger_id = v_rec.id and kind = 'phieu_nhap_kho') then
      raise exception 'Phiếu % thiếu ảnh Phiếu nhập kho.', coalesce(v_rec.code, '(nháp)');
    end if;
  end loop;

  for v_rec in
    select id, code from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'nhap'
     order by entry_date, created_at
  loop
    update ledger set status = 'DaDuyet', submitted_at = now(),
      reviewed_by = v_actor.id, reviewed_at = now(),
      code = coalesce(v_rec.code, next_code_year('NHAP')), reject_reason = null
    where id = v_rec.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Không có phiếu Nháp nào để submit.'; end if;
  perform write_audit(v_actor, 'SUBMIT_NHAP_DAY', 'ledger', null, null,
    jsonb_build_object('count', v_n, 'directApprove', true));
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;
