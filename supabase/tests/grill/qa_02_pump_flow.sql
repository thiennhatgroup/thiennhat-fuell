-- ============================================================================
-- qa_02_pump_flow.sql — Vòng đời Phiếu bơm (S2/S3 + Batch 8 duyệt-thẳng).
-- Nháp→sửa/xóa→Submit ngày. Submit CHẶN thiếu ảnh, rồi DUYỆT THẲNG (DaDuyet),
-- cấp Số phiếu theo ngày BOM-YYYYMMDD-##. Bơm ngoài: tank NULL. begin…rollback.
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','qa_tka@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('11111111-1111-1111-1111-111111111111','qa_tka@test.local','QA ThuKho A','ThuKho','Hoạt động');

insert into oil_types (id,name) values ('a0000000-0000-0000-0000-000000000001','QA DO');
insert into tanks (id,name,oil_type_id,capacity_liters,reorder_point,lead_time_days)
  values ('a0000000-0000-0000-0000-000000000002','QA Tec','a0000000-0000-0000-0000-000000000001',10000,2000,5);
insert into vehicles (id,plate,has_odometer) values
  ('a0000000-0000-0000-0000-000000000003','QA-ODO', true),   -- có công-tơ-mét
  ('a0000000-0000-0000-0000-000000000004','QA-NOODO', false); -- không công-tơ-mét
insert into suppliers (id,name) values ('a0000000-0000-0000-0000-000000000006','QA NCC');

do $$
declare
  v_a uuid := '11111111-1111-1111-1111-111111111111';
  v_oil uuid := 'a0000000-0000-0000-0000-000000000001';
  v_tank uuid := 'a0000000-0000-0000-0000-000000000002';
  v_odo uuid := 'a0000000-0000-0000-0000-000000000003';
  v_noodo uuid := 'a0000000-0000-0000-0000-000000000004';
  v_sup uuid := 'a0000000-0000-0000-0000-000000000006';
  v_xuat uuid; v_bngoai uuid;
  v jsonb; id1 uuid; id2 uuid; id3 uuid; id4 uuid; v_status text; v_code text; v_n int;
begin
  select id into v_xuat from transaction_types where code='xuat_noi_bo';
  select id into v_bngoai from transaction_types where code='bom_ngoai';
  perform set_config('request.jwt.claim.sub', (v_a)::text, true);

  -- 1) Tạo 2 nháp
  v := rpc_pump_create(v_odo, v_xuat, v_oil, 100, v_tank, 5200, 5000);  id1 := (v->>'id')::uuid;
  v := rpc_pump_create(v_odo, v_xuat, v_oil, 50,  v_tank, 5300, 5200);  id2 := (v->>'id')::uuid;
  select count(*) into v_n from ledger where created_by=v_a and status='Nhap';
  perform pg_temp.rec('Tạo 2 phiếu Nháp', v_n=2, 'đếm='||v_n);

  -- 2) Sửa nháp
  perform rpc_pump_update(id1, v_odo, v_xuat, v_oil, 120, v_tank, 5250, 5000, null, null, null);
  perform pg_temp.rec('Sửa lít phiếu Nháp', (select liters from ledger where id=id1)=120, 'lít mới');

  -- 3) Xóa nháp
  perform rpc_pump_delete(id2);
  select count(*) into v_n from ledger where created_by=v_a and status='Nhap';
  perform pg_temp.rec('Xóa phiếu Nháp', v_n=1, 'còn '||v_n||' nháp (chỉ id1)');

  -- 4) Submit khi CHƯA có ảnh → chặn
  begin
    perform rpc_pump_submit_day();
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh đồng hồ bơm', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh đồng hồ bơm', sqlerrm like '%đồng hồ bơm%', sqlerrm);
  end;

  -- 5) Có ảnh đồng hồ bơm nhưng THIẾU công-tơ-mét (xe có công-tơ-mét) → chặn
  perform rpc_pump_photo_add(id1, 'pump_meter', id1::text||'/pm.jpg');
  begin
    perform rpc_pump_submit_day();
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh công-tơ-mét', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh công-tơ-mét', sqlerrm like '%công-tơ-mét%', sqlerrm);
  end;

  -- 6) Đủ 2 ảnh → Submit DUYỆT THẲNG + cấp số phiếu theo ngày
  perform rpc_pump_photo_add(id1, 'odometer', id1::text||'/odo.jpg');
  v := rpc_pump_submit_day();
  select status, code into v_status, v_code from ledger where id=id1;
  perform pg_temp.rec('Submit → DUYỆT THẲNG (DaDuyet)', v_status='DaDuyet', 'status='||v_status);
  perform pg_temp.rec('Cấp Số phiếu theo ngày BOM-YYYYMMDD-##',
    v_code like 'BOM-'||to_char(current_date,'YYYYMMDD')||'-%', 'code='||coalesce(v_code,'null'));
  perform pg_temp.rec('Tự duyệt (reviewed_by = người tạo, không đối chiếu chéo)',
    (select reviewed_by from ledger where id=id1)=v_a, 'reviewed_by');

  -- 7) Xe KHÔNG công-tơ-mét: chỉ cần ảnh đồng hồ bơm
  v := rpc_pump_create(v_noodo, v_xuat, v_oil, 80, v_tank, null, null);  id3 := (v->>'id')::uuid;
  perform rpc_pump_photo_add(id3, 'pump_meter', id3::text||'/pm.jpg');
  perform rpc_pump_submit_day();
  perform pg_temp.rec('Xe không công-tơ-mét: Submit chỉ cần 1 ảnh',
    (select status from ledger where id=id3)='DaDuyet', 'status');

  -- 8) Bơm ngoài: tank NULL, vẫn qua cổng ảnh (xe có công-tơ-mét → 2 ảnh)
  v := rpc_pump_create(v_odo, v_bngoai, v_oil, 200, null, 5400, 5250, v_sup, 21000);  id4 := (v->>'id')::uuid;
  perform pg_temp.rec('Bơm ngoài tạo được với Téc = NULL',
    (select tank_id is null from ledger where id=id4), 'tank_id null');
  perform rpc_pump_photo_add(id4, 'pump_meter', id4::text||'/pm.jpg');
  perform rpc_pump_photo_add(id4, 'odometer',   id4::text||'/odo.jpg');
  perform rpc_pump_submit_day();
  perform pg_temp.rec('Bơm ngoài Submit → duyệt (không gắn téc)',
    (select status from ledger where id=id4)='DaDuyet', 'status');

  -- 9) Chặn đính ảnh path không thuộc phiếu
  v := rpc_pump_create(v_noodo, v_xuat, v_oil, 10, v_tank, null, null);  id2 := (v->>'id')::uuid;
  begin
    perform rpc_pump_photo_add(id2, 'pump_meter', 'phieu-khac/pm.jpg');
    perform pg_temp.rec('Chặn đính ảnh path lạ', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn đính ảnh path lạ', sqlerrm like '%không thuộc phiếu%', sqlerrm);
  end;
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
