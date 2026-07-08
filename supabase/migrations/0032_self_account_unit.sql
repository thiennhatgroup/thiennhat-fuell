-- ============================================================================
-- 0032_self_account_unit.sql — Batch 9 · Mục 1: tài khoản cá nhân + cột đơn vị.
--   - Thêm cột profiles.unit (Đơn vị) do Admin nhập khi tạo/sửa tài khoản.
--   - rpc_bootstrap trả thêm 'unit' để FE hiển thị + đóng dấu watermark ảnh (mục 2).
--   - rpc_admin_create_user / rpc_admin_update_user nhận p_unit.
--   - rpc_admin_list_users trả thêm unit.
-- Đổi mã PIN do mỗi user tự thực hiện qua Supabase Auth ở FE (không cần RPC).
-- KHÔNG sửa migration cũ — file mới ghi đè RPC đang chạy.
-- ============================================================================

alter table profiles add column if not exists unit text;

-- ----------------------------------------------------------------------------
-- rpc_bootstrap: bổ sung 'unit' vào đối tượng user trả về.
-- ----------------------------------------------------------------------------
create or replace function rpc_bootstrap() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_profile profiles;
  v_perms jsonb;
begin
  select * into v_profile from profiles where id = auth.uid();
  if v_profile is null then
    raise exception 'Tài khoản chưa được cấp quyền truy cập hệ thống. Liên hệ Admin để tạo hồ sơ.';
  end if;
  if v_profile.status <> 'Hoạt động' then
    raise exception 'Tài khoản chưa ở trạng thái Hoạt động.';
  end if;

  if v_profile.role = 'Admin' then
    v_perms := to_jsonb(array['*']::text[]);
  else
    select coalesce(jsonb_agg(permission), '[]'::jsonb) into v_perms
    from role_permissions where role = v_profile.role;
  end if;

  return jsonb_build_object(
    'ok', true,
    'user', jsonb_build_object(
      'email', v_profile.email, 'name', v_profile.name,
      'role', v_profile.role, 'unit', v_profile.unit),
    'permissions', v_perms
  );
end;
$$;
grant execute on function rpc_bootstrap() to authenticated;

-- ----------------------------------------------------------------------------
-- rpc_admin_create_user: thêm p_unit (đặt cuối để không phá thứ tự cũ).
-- ----------------------------------------------------------------------------
drop function if exists rpc_admin_create_user(text, text, text, text);
create or replace function rpc_admin_create_user(
  p_email text, p_name text, p_role text, p_pin text, p_unit text default null)
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

  insert into profiles (id, email, name, role, status, unit)
  values (v_uid, v_email, coalesce(nullif(trim(p_name),''), v_email), p_role, 'Hoạt động',
          nullif(trim(coalesce(p_unit,'')),''));

  perform write_audit(v_actor, 'CREATE_USER', 'profiles', v_uid::text, null,
    jsonb_build_object('email', v_email, 'role', p_role, 'unit', p_unit), 'OK', '');
  return jsonb_build_object('ok', true, 'id', v_uid, 'email', v_email);
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_admin_update_user: thêm p_unit (chỉ cập nhật khi truyền chuỗi khác rỗng).
-- ----------------------------------------------------------------------------
drop function if exists rpc_admin_update_user(uuid, text, text, text);
create or replace function rpc_admin_update_user(
  p_id uuid, p_role text default null, p_status text default null,
  p_name text default null, p_unit text default null)
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
    name = coalesce(nullif(trim(coalesce(p_name,'')),''), name),
    unit = coalesce(nullif(trim(coalesce(p_unit,'')),''), unit)
  where id = p_id returning * into v_row;
  perform write_audit(v_actor, 'UPDATE_USER', 'profiles', p_id::text, v_before, to_jsonb(v_row), 'OK', '');
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_admin_list_users: trả thêm unit để màn Tài khoản (Admin) hiển thị/sửa.
-- ----------------------------------------------------------------------------
create or replace function rpc_admin_list_users() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('user:manage');
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'email', email, 'name', name, 'role', role, 'status', status,
    'unit', unit, 'createdAt', to_char(created_at, 'YYYY-MM-DD')
  ) order by created_at), '[]'::jsonb) into v_rows from profiles;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_admin_create_user(text, text, text, text, text) to authenticated;
grant execute on function rpc_admin_update_user(uuid, text, text, text, text) to authenticated;
grant execute on function rpc_admin_list_users() to authenticated;
