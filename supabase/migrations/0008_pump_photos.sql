-- ============================================================================
-- 0008_pump_photos.sql — S3 Ảnh chứng từ (bắt buộc) cho Phiếu bơm + OCR-ready.
-- Ảnh lưu Supabase Storage bucket RIÊNG TƯ 'chung-tu'; metadata ở bảng
-- `pump_photos` (deny-by-default). Không submit được phiếu bơm thiếu ảnh đồng
-- hồ bơm; ảnh công-tơ-mét bắt buộc khi Xe CÓ công-tơ-mét, bỏ được khi không.
-- Trường OCR (ocr_value/ocr_confidence/manually_corrected) để trống ở V1.
-- Ghi qua RPC SECURITY DEFINER + require_permission; đọc URL ký từ FE (Storage
-- SELECT policy chỉ cho nhân sự đang Hoạt động). KHÔNG sửa migration cũ.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Bảng metadata ảnh chứng từ (một dòng / ảnh, gắn với bút toán ledger).
-- ----------------------------------------------------------------------------
create table if not exists pump_photos (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger (id) on delete cascade,
  kind text not null check (kind in ('pump_meter','odometer')),  -- đồng hồ bơm / công-tơ-mét
  storage_path text not null,                    -- đường dẫn object trong bucket 'chung-tu'
  ocr_value text,                                -- OCR-ready (rỗng ở V1)
  ocr_confidence numeric(5,2),                   -- OCR-ready (rỗng ở V1)
  manually_corrected boolean not null default false,  -- OCR-ready (rỗng/false ở V1)
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);
comment on table pump_photos is 'Ảnh chứng từ phiếu bơm (Storage riêng tư). Trường OCR sẵn cho phase sau.';

create index if not exists pump_photos_ledger_idx on pump_photos (ledger_id);

alter table pump_photos enable row level security;
revoke all on pump_photos from anon, authenticated;

-- ----------------------------------------------------------------------------
-- Helper cho policy Storage (đọc profiles/role_permissions trong ngữ cảnh policy;
-- authenticated không được đọc trực tiếp các bảng đó nên phải SECURITY DEFINER).
-- Bản thân bucket + policy trên storage.objects KHÔNG tạo ở migration: vai trò
-- chạy `supabase db push` (postgres) không sở hữu storage.objects nên
-- `create policy` sẽ lỗi "must be owner of table objects" và làm hỏng cả push.
-- => Tạo bucket + policy MỘT LẦN qua Dashboard, xem supabase/storage_chungtu_setup.md.
-- ----------------------------------------------------------------------------
create or replace function chungtu_can_read() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'Hoạt động');
$$;

create or replace function chungtu_can_upload() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from profiles pr
    where pr.id = auth.uid() and pr.status = 'Hoạt động'
      and public.has_permission(pr.role, 'pump:create')
  );
$$;
grant execute on function chungtu_can_read() to authenticated;
grant execute on function chungtu_can_upload() to authenticated;

-- ----------------------------------------------------------------------------
-- RPC ghi metadata ảnh — chỉ người tạo, chỉ khi phiếu còn Nháp. Đường dẫn phải
-- nằm trong "thư mục" của phiếu (chống đăng ký path tùy tiện).
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
  if v_path <> p_ledger_id::text and v_path not like p_ledger_id::text || '/%' then
    raise exception 'Đường dẫn ảnh không thuộc phiếu này.';
  end if;
  insert into pump_photos (ledger_id, kind, storage_path, created_by)
  values (p_ledger_id, p_kind, v_path, v_actor.id)
  returning * into v_row;
  perform write_audit(v_actor, 'ADD_PUMP_PHOTO', 'pump_photos', v_row.id::text, null, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', v_row.id);
end;
$$;

-- Xóa metadata ảnh (chỉ người tạo, chỉ khi Nháp). Trả path để FE xóa object.
create or replace function rpc_pump_photo_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur pump_photos; v_led ledger;
begin
  v_actor := require_permission('pump:create');
  select * into v_cur from pump_photos where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy ảnh.'; end if;
  select * into v_led from ledger where id = v_cur.ledger_id;
  if v_led.created_by <> v_actor.id then raise exception 'Chỉ người tạo được xóa ảnh.'; end if;
  if v_led.status <> 'Nhap' then raise exception 'Chỉ xóa ảnh khi phiếu còn Nháp.'; end if;
  delete from pump_photos where id = p_id;
  perform write_audit(v_actor, 'DELETE_PUMP_PHOTO', 'pump_photos', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id, 'path', v_cur.storage_path);
end;
$$;

-- Danh sách ảnh của một phiếu (cho người nhập lẫn người đối chiếu — đều là ThuKho).
create or replace function rpc_pump_photo_list(p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('pump:create');
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'path', storage_path,
    'ocrValue', ocr_value, 'ocrConfidence', ocr_confidence, 'manuallyCorrected', manually_corrected
  ) order by kind), '[]'::jsonb) into v_rows
  from pump_photos where ledger_id = p_ledger_id;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_pump_photo_add(uuid, text, text) to authenticated;
grant execute on function rpc_pump_photo_delete(uuid) to authenticated;
grant execute on function rpc_pump_photo_list(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- Override Submit ngày: chặn phiếu thiếu ảnh bắt buộc trước khi cấp Số phiếu.
-- Ảnh đồng hồ bơm bắt buộc mọi phiếu; ảnh công-tơ-mét bắt buộc khi Xe có
-- công-tơ-mét. Validate CẢ LÔ trước, chỉ submit khi không phiếu nào thiếu.
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
  perform write_audit(v_actor, 'SUBMIT_PUMP_DAY', 'ledger', null, null, jsonb_build_object('count', v_n));
  return jsonb_build_object('ok', true, 'count', v_n);
end;
$$;
