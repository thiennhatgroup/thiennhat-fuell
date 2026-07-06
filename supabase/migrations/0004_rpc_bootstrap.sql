-- ============================================================================
-- 0004_rpc_bootstrap.sql — Seed quyền theo vai trò + RPC khởi tạo phiên.
-- rpc_bootstrap() trả hồ sơ + danh sách quyền để FE dựng điều hướng.
-- (Quyền là placeholder cho các slice sau; server vẫn chốt qua require_permission.)
-- ============================================================================
insert into role_permissions (role, permission) values
  ('ThuKho','pump:create'),
  ('ThuKho','pump:review'),
  ('ThuKho','inventory:read'),
  ('KeToan','inventory:read'),
  ('KeToan','report:read'),
  ('KeToan','catalog:manage'),
  ('KeToan','adjust:manage')
on conflict do nothing;

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
    'user', jsonb_build_object('email', v_profile.email, 'name', v_profile.name, 'role', v_profile.role),
    'permissions', v_perms
  );
end;
$$;

grant execute on function rpc_bootstrap() to authenticated;
