-- ============================================================================
-- qa_00_roles_permissions.sql — Ma trận quyền 4 vai trò (S0/S1/S7/B8-0023).
-- Bám ĐÚNG code: 0004 + 0006 + 0013 + 0023. Admin bỏ qua ma trận (has_permission
-- trả true cho mọi quyền). Chạy trong SQL Editor. begin…rollback, không để lại rác.
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

-- Người dùng giả để test deny-path end-to-end (FK profiles.id -> auth.users).
insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','qa_tk@test.local','x',now(),now(),now(),'{"provider":"email"}','{}'),
 ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333','authenticated','authenticated','qa_kt@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('11111111-1111-1111-1111-111111111111','qa_tk@test.local','QA ThuKho','ThuKho','Hoạt động'),
 ('33333333-3333-3333-3333-333333333333','qa_kt@test.local','QA KeToan','KeToan','Hoạt động');

-- ---- 1) Ma trận has_permission (nguồn: role_permissions + bypass Admin) ----
do $$
declare
  -- (role, permission, kỳ vọng)
  m text[][] := array[
    ['ThuKho','pump:create','t'], ['ThuKho','inventory:read','t'], ['ThuKho','catalog:read','t'],
    ['ThuKho','pump:review','f'], ['ThuKho','catalog:manage','f'], ['ThuKho','adjust:manage','f'],
    ['ThuKho','report:read','f'], ['ThuKho','alert:read','f'], ['ThuKho','ledger:flag','f'], ['ThuKho','ledger:admin','f'],
    ['KeToan','inventory:read','t'], ['KeToan','report:read','t'], ['KeToan','catalog:manage','t'],
    ['KeToan','adjust:manage','t'], ['KeToan','catalog:read','t'], ['KeToan','alert:read','t'],
    ['KeToan','ledger:flag','t'], ['KeToan','pump:create','f'], ['KeToan','ledger:admin','f'],
    ['TruongBoPhan','inventory:read','t'], ['TruongBoPhan','adjust:manage','t'], ['TruongBoPhan','report:read','t'],
    ['TruongBoPhan','catalog:manage','t'], ['TruongBoPhan','catalog:read','t'], ['TruongBoPhan','alert:read','t'],
    ['TruongBoPhan','ledger:flag','t'], ['TruongBoPhan','pump:create','f'], ['TruongBoPhan','ledger:admin','f'],
    ['Admin','pump:create','t'], ['Admin','ledger:admin','t'], ['Admin','adjust:manage','t'],
    ['Admin','report:read','t'], ['Admin','ledger:flag','t'], ['Admin','anything:xyz','t']
  ];
  i int; got boolean; want boolean;
begin
  for i in 1 .. array_length(m,1) loop
    got := has_permission(m[i][1], m[i][2]);
    want := (m[i][3] = 't');
    perform pg_temp.rec(
      format('Quyền %s ⟶ %s (kỳ vọng %s)', m[i][1], m[i][2], case when want then 'CÓ' else 'KHÔNG' end),
      got = want, 'thực tế: '||coalesce(got::text,'null'));
  end loop;
end $$;

-- ---- 2) Deny-path end-to-end qua RPC thật ----
-- ThuKho gọi báo cáo (report:read) phải bị chặn.
do $$
begin
  perform set_config('request.jwt.claim.sub', ('11111111-1111-1111-1111-111111111111')::text, true);
  begin
    perform rpc_report_monthly(1,2026);
    perform pg_temp.rec('Chặn ThuKho xem báo cáo', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn ThuKho xem báo cáo', true, 'đã chặn: '||sqlerrm);
  end;
end $$;

-- KeToan gọi tạo phiếu bơm (pump:create) phải bị chặn.
do $$
begin
  perform set_config('request.jwt.claim.sub', ('33333333-3333-3333-3333-333333333333')::text, true);
  begin
    perform rpc_pump_submit_day();     -- cần pump:create; KeToan không có
    perform pg_temp.rec('Chặn KeToan submit phiếu bơm', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn KeToan submit phiếu bơm', sqlerrm not like '%Không có phiếu%',
      'đã chặn: '||sqlerrm);
  end;
end $$;

-- KeToan xem tồn kho (inventory:read) phải CHO PHÉP.
do $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', ('33333333-3333-3333-3333-333333333333')::text, true);
  v := rpc_inventory_stock();
  perform pg_temp.rec('Cho phép KeToan xem tồn kho', (v->>'ok')='true', 'ok='||coalesce(v->>'ok','null'));
exception when others then
  perform pg_temp.rec('Cho phép KeToan xem tồn kho', false, 'EXC: '||sqlerrm);
end $$;

-- ============ BẢNG ĐIỂM ============
-- Bản in dự phòng ra tab Messages (chắc chắn hiện, kể cả khi lưới grid bị ẩn do rollback).
do $$
declare r record; v_pass int; v_tot int;
begin
  select count(*) filter(where pass), count(*) into v_pass, v_tot from pg_temp._t;
  raise notice '==================== KẾT QUẢ: % / % PASS ====================', v_pass, v_tot;
  for r in select n,name,pass,note from pg_temp._t order by n loop
    raise notice '[%] #% % — %', case when r.pass then 'PASS' else 'FAIL' end, r.n, r.name, coalesce(r.note,'');
  end loop;
end $$;

select z.n as "#", z.kq as "KQ", z.test as "Test", z.note as "Chi tiết" from (
  select 0 n,
    (case when (select bool_and(pass) from pg_temp._t) then 'ALL PASS' else '*** CÓ FAIL ***' end) kq,
    ('TỔNG '||(select count(*) filter(where pass) from pg_temp._t)||'/'||(select count(*) from pg_temp._t)||' PASS') test, '' note
  union all
  select n, case when pass then 'PASS' else 'FAIL' end, name, coalesce(note,'') from pg_temp._t
) z order by n;
rollback;
