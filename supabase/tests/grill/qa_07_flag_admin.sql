-- ============================================================================
-- qa_07_flag_admin.sql — Gắn cờ (mục 6) → Admin sửa (mục 7) → gỡ cờ + audit.
-- TBP/KeToan có ledger:flag; ThuKho KHÔNG. Chỉ Admin (bypass ledger:admin) sửa/gỡ.
-- Bám Batch 6 (0021) + Batch 8 (0023).
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','qa_tk@test.local','x',now(),now(),now(),'{"provider":"email"}','{}'),
 ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333','authenticated','authenticated','qa_kt@test.local','x',now(),now(),now(),'{"provider":"email"}','{}'),
 ('00000000-0000-0000-0000-000000000000','44444444-4444-4444-4444-444444444444','authenticated','authenticated','qa_tbp@test.local','x',now(),now(),now(),'{"provider":"email"}','{}'),
 ('00000000-0000-0000-0000-000000000000','55555555-5555-5555-5555-555555555555','authenticated','authenticated','qa_ad@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('11111111-1111-1111-1111-111111111111','qa_tk@test.local','QA ThuKho','ThuKho','Hoạt động'),
 ('33333333-3333-3333-3333-333333333333','qa_kt@test.local','QA KeToan','KeToan','Hoạt động'),
 ('44444444-4444-4444-4444-444444444444','qa_tbp@test.local','QA TBP','TruongBoPhan','Hoạt động'),
 ('55555555-5555-5555-5555-555555555555','qa_ad@test.local','QA Admin','Admin','Hoạt động');
insert into oil_types (id,name) values ('a0000000-0000-0000-0000-000000000001','QA DO');
insert into tanks (id,name,oil_type_id,capacity_liters) values ('a0000000-0000-0000-0000-000000000002','QA Tec','a0000000-0000-0000-0000-000000000001',10000);
insert into vehicles (id,plate,has_odometer) values ('a0000000-0000-0000-0000-000000000004','QA-NOODO',false);

do $$
declare
  v_a uuid := '11111111-1111-1111-1111-111111111111';
  v_kt uuid := '33333333-3333-3333-3333-333333333333';
  v_tbp uuid := '44444444-4444-4444-4444-444444444444';
  v_ad uuid := '55555555-5555-5555-5555-555555555555';
  v_veh uuid := 'a0000000-0000-0000-0000-000000000004';
  v_tank uuid := 'a0000000-0000-0000-0000-000000000002';
  v_oil uuid := 'a0000000-0000-0000-0000-000000000001';
  v_xuat uuid; v jsonb; id1 uuid; id2 uuid; c ledger;
begin
  select id into v_xuat from transaction_types where code='xuat_noi_bo';

  -- ThuKho tạo + duyệt thẳng 1 phiếu
  perform set_config('request.jwt.claim.sub', (v_a)::text, true);
  v := rpc_pump_create(v_veh, v_xuat, v_oil, 100, v_tank, null, null);  id1 := (v->>'id')::uuid;
  perform rpc_pump_photo_add(id1, 'pump_meter', id1::text||'/pm.jpg');
  perform rpc_pump_submit_day();
  v := rpc_pump_create(v_veh, v_xuat, v_oil, 40, v_tank, null, null);  id2 := (v->>'id')::uuid; -- để Nháp

  -- TBP gắn cờ phiếu đã duyệt
  perform set_config('request.jwt.claim.sub', (v_tbp)::text, true);
  perform rpc_ledger_flag(id1, 'Sai lít, nhờ Admin sửa');
  select * into c from ledger where id=id1;
  perform pg_temp.rec('TBP gắn cờ phiếu đã duyệt', c.flagged and c.flag_status='open', 'flag_status='||coalesce(c.flag_status,'null'));

  -- Chỉ gắn cờ phiếu ĐÃ DUYỆT (id2 còn Nháp)
  begin
    perform rpc_ledger_flag(id2, 'x');
    perform pg_temp.rec('Chặn gắn cờ phiếu chưa duyệt', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn gắn cờ phiếu chưa duyệt', sqlerrm like '%đã duyệt%', sqlerrm);
  end;

  -- ThuKho KHÔNG có ledger:flag
  perform set_config('request.jwt.claim.sub', (v_a)::text, true);
  begin
    perform rpc_ledger_flag(id1, 'x');
    perform pg_temp.rec('Chặn ThuKho gắn cờ', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn ThuKho gắn cờ', true, 'đã chặn: '||sqlerrm);
  end;

  -- KeToan KHÔNG có ledger:admin → không sửa được
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);
  begin
    perform rpc_admin_ledger_update(id1, null, 150);
    perform pg_temp.rec('Chặn KeToan sửa phiếu (chỉ Admin)', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn KeToan sửa phiếu (chỉ Admin)', true, 'đã chặn: '||sqlerrm);
  end;

  -- Admin sửa (gửi lại đủ trường, chỉ đổi lít 100→150)
  perform set_config('request.jwt.claim.sub', (v_ad)::text, true);
  select * into c from ledger where id=id1;
  perform rpc_admin_ledger_update(id1, c.entry_date, 150, c.note, c.vehicle_id, c.txn_type_id,
    c.tank_id, c.oil_type_id, c.km_old, c.km_new, c.supplier_id, c.unit_price, c.supplier_invoice_no);
  select * into c from ledger where id=id1;
  perform pg_temp.rec('Admin sửa lít 100→150 + đóng dấu edited_by',
    c.liters=150 and c.edited_by=v_ad, 'liters='||c.liters||' edited_by='||coalesce(c.edited_by::text,'null'));

  -- Admin gỡ cờ
  perform rpc_admin_flag_resolve(id1);
  perform pg_temp.rec('Admin gỡ cờ (flag_status=resolved)',
    (select flag_status from ledger where id=id1)='resolved', 'flag_status');

  -- Audit có lịch sử
  v := rpc_admin_ledger_audit(id1);
  perform pg_temp.rec('Audit ghi lại thao tác trên phiếu', (v->>'ok')='true', 'ok='||coalesce(v->>'ok','null'));
end $$;

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
