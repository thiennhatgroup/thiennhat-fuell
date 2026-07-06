-- ============================================================================
-- 0003_permissions.sql — Helper quyền + ghi audit. Mọi RPC nghiệp vụ gọi
-- require_permission(...) làm câu đầu tiên.
-- ============================================================================
create or replace function has_permission(p_role text, p_permission text) returns boolean
language sql stable as $$
  select p_role = 'Admin' or exists (
    select 1 from role_permissions where role = p_role and permission = p_permission
  );
$$;

create or replace function require_permission(p_permission text) returns profiles
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_profile profiles;
begin
  select * into v_profile from profiles where id = auth.uid();
  if v_profile is null then
    raise exception 'Tài khoản chưa được cấp quyền truy cập hệ thống. Liên hệ Admin để tạo hồ sơ.';
  end if;
  if v_profile.status <> 'Hoạt động' then
    raise exception 'Tài khoản chưa ở trạng thái Hoạt động.';
  end if;
  if not has_permission(v_profile.role, p_permission) then
    raise exception 'Vai trò % không có quyền thực hiện thao tác này.', v_profile.role;
  end if;
  return v_profile;
end;
$$;

create or replace function write_audit(
  p_actor profiles, p_action text, p_entity_type text, p_entity_id text,
  p_before jsonb, p_after jsonb, p_result text default 'OK', p_message text default ''
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into audit_log (log_id, actor_id, actor_email, actor_name, role, action, entity_type, entity_id, before_json, after_json, result, message)
  values (next_code('LOG'), p_actor.id, p_actor.email, p_actor.name, p_actor.role, p_action, p_entity_type, p_entity_id, p_before, p_after, coalesce(p_result,'OK'), coalesce(p_message,''));
exception when others then
  raise notice 'audit log write failed: %', sqlerrm;
end;
$$;

grant execute on function has_permission(text, text) to authenticated;
