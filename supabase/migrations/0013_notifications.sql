-- ============================================================================
-- 0013_notifications.sql — S7 Cảnh báo tồn + Web Push (VAPID).
-- Sinh cảnh báo khi Téc: (a) tồn dưới điểm đặt hàng, (b) tồn âm, (c) vượt sức chứa.
-- Cơ chế:
--   • alerts_scan() (nội bộ, KHÔNG grant) tính lại tồn từng téc theo ĐÚNG công thức
--     rpc_inventory_stock (Tồn cuối = Tồn đầu + Nhập − Xuất − Tịnh âm + Tịnh dương)
--     rồi chèn `notification` cho mỗi điều kiện đang vi phạm. Dedup theo
--     (kind, tank, ngày) → tối đa 1 cảnh báo / loại / téc / ngày (không spam mỗi lần quét).
--   • rpc_alerts_scan() (gated inventory:read) — FE gọi sau khi tải Tồn kho / khi mở app.
--   • Cảnh báo hiển thị cho Kế toán/Admin (gated alert:read) + đánh dấu đã đọc / người.
--   • Web Push: bảng push_subscription (một dòng / thiết bị / người). Sau khi có cảnh báo
--     mới, push_dispatch() gọi Edge Function (secret ở app_config) — CÓ GUARD: thiếu
--     cấu hình hoặc chưa bật pg_net thì BỎ QUA AN TOÀN, không lỗi.
-- Deny-by-default + RPC SECURITY DEFINER. KHÔNG sửa migration cũ.
-- ============================================================================

-- Cảnh báo (một dòng / lần vượt ngưỡng; toàn hệ thống, không theo người nhận).
create table if not exists notification (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('ton_thap','ton_am','vuot_suc_chua')),
  level text not null default 'warning' check (level in ('info','warning','danger')),
  tank_id uuid references tanks (id) on delete set null,
  title text not null,
  body text not null,
  closing numeric(14,2),                              -- ảnh chụp tồn cuối lúc sinh cảnh báo
  dedup_key text unique not null,                     -- kind:tank:YYYY-MM-DD → tránh spam
  pushed_at timestamptz,                              -- Edge Function set khi đã đẩy push
  created_at timestamptz not null default now()
);
comment on table notification is 'Cảnh báo tồn (tồn thấp/âm/vượt sức chứa); Kế toán/Admin xem.';
create index if not exists notification_created_idx on notification (created_at desc);

-- Đã đọc theo từng người (một dòng / cảnh báo / người).
create table if not exists notification_read (
  notification_id uuid not null references notification (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);

-- Đăng ký Web Push (một dòng / endpoint thiết bị).
create table if not exists push_subscription (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  endpoint text unique not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_subscription_user_idx on push_subscription (user_id);

alter table notification enable row level security;
alter table notification_read enable row level security;
alter table push_subscription enable row level security;
revoke all on notification, notification_read, push_subscription from anon, authenticated;
create or replace trigger trg_push_subscription_updated before update on push_subscription for each row execute function set_updated_at();

-- ----------------------------------------------------------------------------
-- Quyền: Kế toán xem cảnh báo + đăng ký push (Admin ngầm định như '*').
-- ----------------------------------------------------------------------------
insert into role_permissions (role, permission) values
  ('KeToan','alert:read')
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- push_dispatch() — nội bộ, KHÔNG grant. Gọi Edge Function gửi push.
-- Đọc app_config: 'edge_push_url' (URL function) + 'edge_push_secret' (secret dùng
-- chung). Thiếu bất kỳ → bỏ qua. Chưa bật extension pg_net (net.http_post) → bỏ qua.
-- Best-effort: mọi lỗi mạng nuốt lại (raise notice) để không chặn nghiệp vụ.
-- ----------------------------------------------------------------------------
create or replace function push_dispatch() returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_url text; v_secret text; v_has_net boolean;
begin
  select value #>> '{}' into v_url from app_config where key = 'edge_push_url';
  select value #>> '{}' into v_secret from app_config where key = 'edge_push_secret';
  if coalesce(v_url,'') = '' or coalesce(v_secret,'') = '' then
    return;  -- chưa cấu hình push → bỏ qua an toàn
  end if;
  select exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'net' and p.proname = 'http_post'
  ) into v_has_net;
  if not v_has_net then
    raise notice 'push_dispatch: pg_net chưa bật, bỏ qua.';
    return;
  end if;
  begin
    execute
      'select net.http_post(url := $1, headers := $2::jsonb, body := $3::jsonb)'
      using v_url,
            jsonb_build_object('Content-Type','application/json','x-webhook-secret', v_secret),
            '{}'::jsonb;
  exception when others then
    raise notice 'push_dispatch lỗi: %', sqlerrm;
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- alerts_scan() — nội bộ, KHÔNG grant. Quét tồn hiện tại, chèn cảnh báo mới.
-- Trả số cảnh báo mới tạo. Gọi push_dispatch() nếu có cảnh báo mới.
-- ----------------------------------------------------------------------------
create or replace function alerts_scan() returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rec record; v_created int := 0; v_today text := to_char(current_date,'YYYY-MM-DD');
  v_kind text; v_level text; v_title text; v_body text; v_ins uuid;
begin
  for v_rec in
    select t.id as tank_id, t.name as tank_name, t.capacity_liters as capacity,
           t.reorder_point as reorder,
           coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0)
             - coalesce(aj.am,0) + coalesce(aj.duong,0) as closing
    from tanks t
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
  loop
    -- Ưu tiên nghiêm trọng: tồn âm > vượt sức chứa > dưới điểm đặt hàng.
    if v_rec.closing < 0 then
      v_kind := 'ton_am'; v_level := 'danger';
      v_title := 'Tồn âm: ' || v_rec.tank_name;
      v_body := 'Tồn cuối ' || trim(to_char(v_rec.closing,'FM999999990.00')) || ' lít (< 0). Kiểm tra sổ cái.';
    elsif v_rec.capacity > 0 and v_rec.closing > v_rec.capacity then
      v_kind := 'vuot_suc_chua'; v_level := 'warning';
      v_title := 'Vượt sức chứa: ' || v_rec.tank_name;
      v_body := 'Tồn cuối ' || trim(to_char(v_rec.closing,'FM999999990.00')) || ' lít > sức chứa '
                || trim(to_char(v_rec.capacity,'FM999999990.00')) || ' lít.';
    elsif v_rec.reorder > 0 and v_rec.closing <= v_rec.reorder then
      v_kind := 'ton_thap'; v_level := 'warning';
      v_title := 'Tồn thấp: ' || v_rec.tank_name;
      v_body := 'Tồn cuối ' || trim(to_char(v_rec.closing,'FM999999990.00')) || ' lít ≤ điểm đặt hàng '
                || trim(to_char(v_rec.reorder,'FM999999990.00')) || ' lít. Cân nhắc nhập thêm.';
    else
      continue;  -- téc bình thường
    end if;

    insert into notification (kind, level, tank_id, title, body, closing, dedup_key)
    values (v_kind, v_level, v_rec.tank_id, v_title, v_body, round(v_rec.closing,2),
            v_kind || ':' || v_rec.tank_id::text || ':' || v_today)
    on conflict (dedup_key) do nothing
    returning id into v_ins;
    if v_ins is not null then v_created := v_created + 1; end if;
  end loop;

  if v_created > 0 then perform push_dispatch(); end if;
  return v_created;
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_alerts_scan() — FE gọi để kích hoạt quét (gated inventory:read; ThuKho/KeToan/Admin).
-- ----------------------------------------------------------------------------
create or replace function rpc_alerts_scan() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int;
begin
  perform require_permission('inventory:read');
  v_n := alerts_scan();
  return jsonb_build_object('ok', true, 'created', v_n);
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_alerts_list() — danh sách cảnh báo gần đây + cờ đã đọc của người gọi (Kế toán/Admin).
-- ----------------------------------------------------------------------------
create or replace function rpc_alerts_list(p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rows jsonb; v_unread int;
begin
  v_actor := require_permission('alert:read');
  select coalesce(jsonb_agg(r order by r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', n.id, 'kind', n.kind, 'level', n.level, 'title', n.title, 'body', n.body,
      'closing', n.closing, 'tankId', n.tank_id,
      'createdAt', to_char(n.created_at,'YYYY-MM-DD HH24:MI'),
      'read', (nr.notification_id is not null)
    ) as r, n.created_at as r_created
    from notification n
    left join notification_read nr on nr.notification_id = n.id and nr.user_id = v_actor.id
    order by n.created_at desc
    limit greatest(1, least(coalesce(p_limit,50), 200))
  ) s;
  select count(*) into v_unread from notification n
    where not exists (select 1 from notification_read nr
      where nr.notification_id = n.id and nr.user_id = v_actor.id);
  return jsonb_build_object('ok', true, 'rows', v_rows, 'unread', v_unread);
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_alerts_mark_read(p_id) — đánh dấu đã đọc một cảnh báo, hoặc tất cả nếu p_id null.
-- ----------------------------------------------------------------------------
create or replace function rpc_alerts_mark_read(p_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles;
begin
  v_actor := require_permission('alert:read');
  if p_id is null then
    insert into notification_read (notification_id, user_id)
    select n.id, v_actor.id from notification n
    on conflict do nothing;
  else
    if not exists (select 1 from notification where id = p_id) then
      raise exception 'Không tìm thấy cảnh báo.'; end if;
    insert into notification_read (notification_id, user_id)
    values (p_id, v_actor.id) on conflict do nothing;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_push_subscribe / rpc_push_unsubscribe — đăng ký/hủy Web Push cho thiết bị.
-- Chỉ vai trò có alert:read (Kế toán/Admin) mới nhận push.
-- ----------------------------------------------------------------------------
create or replace function rpc_push_subscribe(
  p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles;
begin
  v_actor := require_permission('alert:read');
  if coalesce(trim(p_endpoint),'') = '' or coalesce(trim(p_p256dh),'') = ''
     or coalesce(trim(p_auth),'') = '' then
    raise exception 'Thông tin đăng ký push không hợp lệ.'; end if;
  insert into push_subscription (user_id, endpoint, p256dh, auth, user_agent)
  values (v_actor.id, trim(p_endpoint), trim(p_p256dh), trim(p_auth), p_user_agent)
  on conflict (endpoint) do update set
    user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
    user_agent = excluded.user_agent;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function rpc_push_unsubscribe(p_endpoint text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles;
begin
  v_actor := require_permission('alert:read');
  delete from push_subscription where endpoint = trim(p_endpoint) and user_id = v_actor.id;
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function rpc_alerts_scan() to authenticated;
grant execute on function rpc_alerts_list(int) to authenticated;
grant execute on function rpc_alerts_mark_read(uuid) to authenticated;
grant execute on function rpc_push_subscribe(text, text, text, text) to authenticated;
grant execute on function rpc_push_unsubscribe(text) to authenticated;
