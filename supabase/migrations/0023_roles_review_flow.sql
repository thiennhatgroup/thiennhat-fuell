-- ============================================================================
-- 0023_roles_review_flow.sql — Batch 8: vai trò Trưởng bộ phận + phân quyền lại,
-- phiếu bơm DUYỆT THẲNG khi Submit, số phiếu theo ngày, cơ chế "gắn cờ nhờ Admin
-- sửa" (mục 6) + hàng đợi phiếu bị gắn cờ cho Admin (mục 7). KHÔNG sửa migration cũ.
--
-- Phân quyền (mục 1..7 theo thứ tự menu nghiệp vụ):
--   ThuKho      → 1 Nhập bơm, 2 Phiếu nhập, 3 Tồn kho.
--   TruongBoPhan + KeToan (kế toán tổng hợp) → 3 Tồn kho, 4 Tịnh téc, 5 Báo cáo,
--                 6 Đối chiếu phiếu (xem ảnh + nhờ Admin sửa), + Danh mục & Xe.
--   Admin       → tất cả, gồm 7 Sửa phiếu (tự sửa + phiếu bị gắn cờ).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Thêm vai trò TruongBoPhan vào ràng buộc + các RPC quản trị tài khoản.
-- ----------------------------------------------------------------------------
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check
  check (role in ('ThuKho','KeToan','TruongBoPhan','Admin'));

-- Recreate rpc_admin_create_user (chỉ đổi danh sách vai trò hợp lệ; thân giữ nguyên).
create or replace function rpc_admin_create_user(p_email text, p_name text, p_role text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_actor profiles;
  v_uid uuid := gen_random_uuid();
  v_email text := lower(trim(coalesce(p_email,'')));
  v_pin text := trim(coalesce(p_pin,''));
  v_pw text;
begin
  v_actor := require_permission('user:manage');
  if v_email = '' or position('@' in v_email) = 0 then raise exception 'Email không hợp lệ.'; end if;
  if p_role not in ('ThuKho','KeToan','TruongBoPhan','Admin') then raise exception 'Vai trò không hợp lệ.'; end if;
  if length(v_pin) < 4 then raise exception 'Mã PIN cần ít nhất 4 ký tự.'; end if;
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Email % đã tồn tại.', v_email;
  end if;
  v_pw := 'tn-pin::' || v_pin;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
    crypt(v_pw, gen_salt('bf')), now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('name', coalesce(nullif(trim(p_name),''), v_email)),
    false, '', '', '', ''
  );

  insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_uid::text, v_uid,
          jsonb_build_object('sub', v_uid::text, 'email', v_email), 'email', now(), now(), now());

  insert into profiles (id, email, name, role, status)
  values (v_uid, v_email, coalesce(nullif(trim(p_name),''), v_email), p_role, 'Hoạt động');

  perform write_audit(v_actor, 'CREATE_USER', 'profiles', v_uid::text, null,
    jsonb_build_object('email', v_email, 'role', p_role), 'OK', '');
  return jsonb_build_object('ok', true, 'id', v_uid, 'email', v_email);
end;
$$;

create or replace function rpc_admin_update_user(p_id uuid, p_role text default null, p_status text default null, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_before jsonb; v_row profiles;
begin
  v_actor := require_permission('user:manage');
  select to_jsonb(p) into v_before from profiles p where id = p_id;
  if v_before is null then raise exception 'Không tìm thấy tài khoản.'; end if;
  if p_role is not null and p_role not in ('ThuKho','KeToan','TruongBoPhan','Admin') then raise exception 'Vai trò không hợp lệ.'; end if;
  if p_status is not null and p_status not in ('Hoạt động','Ngừng') then raise exception 'Trạng thái không hợp lệ.'; end if;
  update profiles set
    role = coalesce(nullif(trim(coalesce(p_role,'')),''), role),
    status = coalesce(nullif(trim(coalesce(p_status,'')),''), status),
    name = coalesce(nullif(trim(coalesce(p_name,'')),''), name)
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_USER', 'profiles', p_id::text, v_before, to_jsonb(v_row), 'OK', '');
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- 2) Ma trận quyền. Thủ kho BỎ quyền đối chiếu bơm (mục 6 chuyển cho TBP/KeToan).
--    'ledger:flag' = xem phiếu đã duyệt + xem ảnh + gửi yêu cầu Admin sửa (mục 6).
-- ----------------------------------------------------------------------------
delete from role_permissions where role = 'ThuKho' and permission = 'pump:review';

insert into role_permissions (role, permission) values
  ('KeToan','ledger:flag'),
  ('TruongBoPhan','inventory:read'),
  ('TruongBoPhan','adjust:manage'),
  ('TruongBoPhan','report:read'),
  ('TruongBoPhan','catalog:manage'),
  ('TruongBoPhan','catalog:read'),
  ('TruongBoPhan','alert:read'),
  ('TruongBoPhan','ledger:flag')
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 3) Số phiếu theo NGÀY nghiệp vụ: PREFIX-YYYYMMDD-## (đếm riêng theo prefix+ngày).
--    Tái dùng bảng code_counters (prefix, day, seq).
-- ----------------------------------------------------------------------------
create or replace function next_code_for_date(p_prefix text, p_date date) returns text
language plpgsql as $$
declare v_seq int; v_d date := coalesce(p_date, current_date);
begin
  insert into code_counters (prefix, day, seq) values (p_prefix, v_d, 1)
  on conflict (prefix, day) do update set seq = code_counters.seq + 1
  returning seq into v_seq;
  return p_prefix || '-' || to_char(v_d, 'YYYYMMDD') || '-' || lpad(v_seq::text, 2, '0');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4) Phiếu bơm: Submit ngày = DUYỆT THẲNG vào tồn (bỏ đối chiếu chéo của thủ kho).
--    Giữ nguyên yêu cầu ảnh (đồng hồ bơm + công-tơ-mét nếu xe có). Cấp số theo ngày.
-- ----------------------------------------------------------------------------
create or replace function rpc_pump_submit_day()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rec record; v_n integer := 0; v_veh_odo boolean;
begin
  v_actor := require_permission('pump:create');
  for v_rec in
    select l.id, l.code, l.vehicle_id from ledger l
     where l.created_by = v_actor.id and l.status = 'Nhap' and l.entry_type = 'bom'
  loop
    if not exists (select 1 from pump_photos where ledger_id = v_rec.id and kind = 'pump_meter') then
      raise exception 'Phiếu % thiếu ảnh đồng hồ bơm.', coalesce(v_rec.code, '(nháp)');
    end if;
    select coalesce(has_odometer, false) into v_veh_odo from vehicles where id = v_rec.vehicle_id;
    if v_veh_odo and not exists (select 1 from pump_photos where ledger_id = v_rec.id and kind = 'odometer') then
      raise exception 'Phiếu % thiếu ảnh công-tơ-mét.', coalesce(v_rec.code, '(nháp)');
    end if;
  end loop;

  for v_rec in
    select id, code, entry_date from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'bom'
     order by entry_date, created_at
  loop
    update ledger set status = 'DaDuyet', submitted_at = now(),
      reviewed_by = v_actor.id, reviewed_at = now(),
      code = coalesce(v_rec.code, next_code_for_date('BOM', v_rec.entry_date)), reject_reason = null
    where id = v_rec.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Không có phiếu Nháp nào để submit.'; end if;
  perform write_audit(v_actor, 'SUBMIT_PUMP_DAY', 'ledger', null, null,
    jsonb_build_object('count', v_n, 'directApprove', true));
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

-- Phiếu nhập: giữ DUYỆT THẲNG (Batch 3), chỉ đổi số phiếu sang theo ngày.
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
    select id, code, entry_date from ledger
     where created_by = v_actor.id and status = 'Nhap' and entry_type = 'nhap'
     order by entry_date, created_at
  loop
    update ledger set status = 'DaDuyet', submitted_at = now(),
      reviewed_by = v_actor.id, reviewed_at = now(),
      code = coalesce(v_rec.code, next_code_for_date('NHAP', v_rec.entry_date)), reject_reason = null
    where id = v_rec.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Không có phiếu Nháp nào để submit.'; end if;
  perform write_audit(v_actor, 'SUBMIT_NHAP_DAY', 'ledger', null, null,
    jsonb_build_object('count', v_n, 'directApprove', true));
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;

-- ----------------------------------------------------------------------------
-- 5) Cột gắn cờ trên ledger: trưởng bộ phận/kế toán "nhờ Admin sửa" một phiếu.
-- ----------------------------------------------------------------------------
alter table ledger add column if not exists flagged boolean not null default false;
alter table ledger add column if not exists flag_reason text;
alter table ledger add column if not exists flagged_by uuid references profiles (id);
alter table ledger add column if not exists flagged_at timestamptz;
alter table ledger add column if not exists flag_status text;  -- 'open' | 'resolved'
create index if not exists ledger_flag_idx on ledger (flagged) where flagged;

-- ----------------------------------------------------------------------------
-- 6) MỤC 6 — Đối chiếu phiếu (TruongBoPhan/KeToan): danh sách phiếu đã duyệt để
--    xem lại + xem ảnh + gắn cờ nhờ Admin sửa.
-- ----------------------------------------------------------------------------
create or replace function rpc_review_ledger_list(
  p_days integer default 60, p_entry_type text default null, p_q text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb; v_days integer := greatest(coalesce(p_days, 60), 1);
        v_q text := nullif(trim(coalesce(p_q,'')),'');
begin
  perform require_permission('ledger:flag');
  select coalesce(jsonb_agg(r order by r_date desc, r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'entryType', l.entry_type, 'status', l.status,
      'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'vehiclePlate', ve.plate, 'txnName', tt.name, 'txnKind', tt.kind,
      'tankName', tk.name, 'oilTypeName', ot.name, 'supplierName', su.name,
      'liters', l.liters, 'kmOld', l.km_old, 'kmNew', l.km_new, 'kmRun', l.km_run,
      'unitPrice', l.unit_price, 'amount', round(coalesce(l.liters,0)*coalesce(l.unit_price,0),2),
      'supplierInvoiceNo', l.supplier_invoice_no, 'note', l.note, 'legacy', l.legacy,
      'createdByName', pc.name,
      'flagged', l.flagged, 'flagStatus', l.flag_status, 'flagReason', l.flag_reason,
      'flaggedByName', pf.name
    ) as r, l.entry_date as r_date, l.created_at as r_created
    from ledger l
    left join vehicles ve on ve.id = l.vehicle_id
    left join transaction_types tt on tt.id = l.txn_type_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    left join suppliers su on su.id = l.supplier_id
    left join profiles pc on pc.id = l.created_by
    left join profiles pf on pf.id = l.flagged_by
    where l.entry_type in ('bom','nhap') and l.status = 'DaDuyet'
      and l.entry_date >= current_date - v_days
      and (p_entry_type is null or l.entry_type = p_entry_type)
      and (v_q is null or normalize_text(
            coalesce(l.code,'')||' '||coalesce(ve.plate,'')||' '||coalesce(su.name,'')||' '||coalesce(l.note,'')
          ) like '%'||normalize_text(v_q)||'%')
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Xem ảnh của một phiếu bất kỳ (mọi loại ảnh bơm/nhập) — cho người có quyền đối chiếu.
create or replace function rpc_review_photo_list(p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('ledger:flag');
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'path', storage_path
  ) order by kind), '[]'::jsonb) into v_rows
  from pump_photos where ledger_id = p_ledger_id;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Gắn cờ "nhờ Admin sửa" một phiếu đã duyệt (kèm lý do). Ghi audit.
create or replace function rpc_ledger_flag(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  v_actor := require_permission('ledger:flag');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if v_cur.status <> 'DaDuyet' then raise exception 'Chỉ gắn cờ phiếu đã duyệt.'; end if;
  if v_reason is null then raise exception 'Nhập lý do cần Admin sửa.'; end if;
  update ledger set flagged = true, flag_reason = v_reason, flag_status = 'open',
    flagged_by = v_actor.id, flagged_at = now()
  where id = p_id;
  perform write_audit(v_actor, 'FLAG_LEDGER', 'ledger', p_id::text, null,
    jsonb_build_object('reason', v_reason));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- 7) MỤC 7 — Admin: dashboard phiếu + lọc "chỉ phiếu bị gắn cờ" + trả (resolve) cờ.
--    Thay chữ ký rpc_admin_ledger_list cũ (thêm p_flagged_only + trường cờ).
-- ----------------------------------------------------------------------------
drop function if exists rpc_admin_ledger_list(integer, text, text);
create or replace function rpc_admin_ledger_list(
  p_days integer default 60, p_entry_type text default null, p_q text default null,
  p_flagged_only boolean default false
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb; v_days integer := greatest(coalesce(p_days, 60), 1);
        v_q text := nullif(trim(coalesce(p_q,'')),'');
begin
  perform require_permission('ledger:admin');
  select coalesce(jsonb_agg(r order by r_flag desc, r_date desc, r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'entryType', l.entry_type, 'status', l.status,
      'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'vehicleId', l.vehicle_id, 'vehiclePlate', ve.plate,
      'txnTypeId', l.txn_type_id, 'txnName', tt.name, 'txnKind', tt.kind,
      'tankId', l.tank_id, 'tankName', tk.name,
      'oilTypeId', l.oil_type_id, 'oilTypeName', ot.name,
      'supplierId', l.supplier_id, 'supplierName', su.name,
      'liters', l.liters, 'kmOld', l.km_old, 'kmNew', l.km_new,
      'unitPrice', l.unit_price, 'amount', round(coalesce(l.liters,0)*coalesce(l.unit_price,0),2),
      'supplierInvoiceNo', l.supplier_invoice_no, 'note', l.note,
      'legacy', l.legacy, 'createdByName', pc.name,
      'editedByName', pe.name, 'editedAt', to_char(l.edited_at,'YYYY-MM-DD HH24:MI'),
      'flagged', l.flagged, 'flagStatus', l.flag_status, 'flagReason', l.flag_reason,
      'flaggedByName', pf.name
    ) as r, (l.flagged and coalesce(l.flag_status,'open')='open') as r_flag,
       l.entry_date as r_date, l.created_at as r_created
    from ledger l
    left join vehicles ve on ve.id = l.vehicle_id
    left join transaction_types tt on tt.id = l.txn_type_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    left join suppliers su on su.id = l.supplier_id
    left join profiles pc on pc.id = l.created_by
    left join profiles pe on pe.id = l.edited_by
    left join profiles pf on pf.id = l.flagged_by
    where l.entry_type in ('bom','nhap')
      and l.entry_date >= current_date - v_days
      and (p_entry_type is null or l.entry_type = p_entry_type)
      and (not coalesce(p_flagged_only,false) or (l.flagged and coalesce(l.flag_status,'open')='open'))
      and (v_q is null or normalize_text(
            coalesce(l.code,'')||' '||coalesce(ve.plate,'')||' '||coalesce(su.name,'')||' '||coalesce(l.note,'')
          ) like '%'||normalize_text(v_q)||'%')
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Admin đánh dấu đã xử lý cờ (sau khi sửa hoặc bỏ qua).
create or replace function rpc_admin_flag_resolve(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger;
begin
  v_actor := require_permission('ledger:admin');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  update ledger set flagged = false, flag_status = 'resolved' where id = p_id;
  perform write_audit(v_actor, 'RESOLVE_FLAG', 'ledger', p_id::text,
    jsonb_build_object('reason', v_cur.flag_reason), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

grant execute on function next_code_for_date(text, date) to authenticated;
grant execute on function rpc_review_ledger_list(integer, text, text) to authenticated;
grant execute on function rpc_review_photo_list(uuid) to authenticated;
grant execute on function rpc_ledger_flag(uuid, text) to authenticated;
grant execute on function rpc_admin_ledger_list(integer, text, text, boolean) to authenticated;
grant execute on function rpc_admin_flag_resolve(uuid) to authenticated;
