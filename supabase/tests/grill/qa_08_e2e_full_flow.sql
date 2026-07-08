-- ============================================================================
-- qa_08_e2e_full_flow.sql — LUỒNG NGHIỆP VỤ ĐẦY ĐỦ, đi qua cả 4 vai trò:
--   Thủ kho nhập bơm + nhập dầu (duyệt thẳng) → Kế toán xem tồn kho realtime
--   → Trưởng bộ phận gắn cờ nhờ Admin sửa → Admin sửa + gỡ cờ
--   → Kế toán xuất báo cáo tháng phản ánh đúng số đã sửa.
-- Đây là "mốc vàng" (golden path) — mọi bước có PASS/FAIL. begin…rollback.
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
insert into tanks (id,name,oil_type_id,capacity_liters,reorder_point) values ('a0000000-0000-0000-0000-000000000002','QA Tec','a0000000-0000-0000-0000-000000000001',10000,500);
insert into vehicles (id,plate,has_odometer,pump_norm) values ('a0000000-0000-0000-0000-000000000005','QA-E2E',false,50);
insert into suppliers (id,name) values ('a0000000-0000-0000-0000-000000000006','QA NCC');

do $$
declare
  v_a uuid := '11111111-1111-1111-1111-111111111111';
  v_kt uuid := '33333333-3333-3333-3333-333333333333';
  v_tbp uuid := '44444444-4444-4444-4444-444444444444';
  v_ad uuid := '55555555-5555-5555-5555-555555555555';
  v_tank uuid := 'a0000000-0000-0000-0000-000000000002';
  v_oil uuid := 'a0000000-0000-0000-0000-000000000001';
  v_veh uuid := 'a0000000-0000-0000-0000-000000000005';
  v_sup uuid := 'a0000000-0000-0000-0000-000000000006';
  v_xuat uuid; v jsonb; r jsonb; c ledger; id_bom uuid; id_nhap uuid;
begin
  select id into v_xuat from transaction_types where code='xuat_noi_bo';

  -- B1) KẾ TOÁN đặt Tồn đầu gốc 1000
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);
  perform rpc_tank_opening_set(v_tank, 1000, current_date, 'QA tồn đầu');
  perform pg_temp.rec('B1 KeToan đặt Tồn đầu gốc = 1000',
    (select liters from tank_opening where tank_id=v_tank)=1000, null);

  -- B2) THỦ KHO nhập bơm (xuất 300) + ảnh + submit (duyệt thẳng)
  perform set_config('request.jwt.claim.sub', (v_a)::text, true);
  v := rpc_pump_create(v_veh, v_xuat, v_oil, 300, v_tank, null, null);  id_bom := (v->>'id')::uuid;
  perform rpc_pump_photo_add(id_bom, 'pump_meter', id_bom::text||'/pm.jpg');
  perform rpc_pump_submit_day();
  perform pg_temp.rec('B2 ThuKho nhập bơm → duyệt thẳng (DaDuyet)',
    (select status from ledger where id=id_bom)='DaDuyet', null);

  -- B3) THỦ KHO nhập dầu về téc (500) + 2 ảnh + submit
  v := rpc_nhap_create(v_sup, v_tank, v_oil, 500, 21000, 'HD-E2E');  id_nhap := (v->>'id')::uuid;
  perform rpc_nhap_photo_add(id_nhap, 'bien_ban_giao_nhan', id_nhap::text||'/bb.jpg');
  perform rpc_nhap_photo_add(id_nhap, 'phieu_nhap_kho',     id_nhap::text||'/pnk.jpg');
  perform rpc_nhap_submit_day();
  perform pg_temp.rec('B3 ThuKho nhập dầu về téc → duyệt thẳng',
    (select status from ledger where id=id_nhap)='DaDuyet', null);

  -- B4) KẾ TOÁN xem Tồn kho realtime = 1000 + 500 − 300 = 1200
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);
  v := rpc_inventory_stock();
  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'tankId')::uuid=v_tank;
  perform pg_temp.rec('B4 KeToan: Tồn cuối = 1200 (1000+500−300)',
    (r->>'closing')::numeric=1200, 'closing='||(r->>'closing'));

  -- B5) TRƯỞNG BỘ PHẬN gắn cờ phiếu bơm nhờ Admin sửa
  perform set_config('request.jwt.claim.sub', (v_tbp)::text, true);
  perform rpc_ledger_flag(id_bom, 'Lít bơm ghi thiếu, nhờ Admin sửa 300→320');
  perform pg_temp.rec('B5 TBP gắn cờ phiếu (chờ Admin)',
    (select flagged and flag_status='open' from ledger where id=id_bom), null);

  -- B6) ADMIN sửa lít 300→320 + gỡ cờ
  perform set_config('request.jwt.claim.sub', (v_ad)::text, true);
  select * into c from ledger where id=id_bom;
  perform rpc_admin_ledger_update(id_bom, c.entry_date, 320, c.note, c.vehicle_id, c.txn_type_id,
    c.tank_id, c.oil_type_id, c.km_old, c.km_new, c.supplier_id, c.unit_price, c.supplier_invoice_no);
  perform rpc_admin_flag_resolve(id_bom);
  select * into c from ledger where id=id_bom;
  perform pg_temp.rec('B6 Admin sửa lít→320 + gỡ cờ',
    c.liters=320 and c.flag_status='resolved' and c.edited_by=v_ad, 'liters='||c.liters);

  -- B7) KẾ TOÁN: Tồn kho phản ánh số đã sửa = 1000 + 500 − 320 = 1180
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);
  v := rpc_inventory_stock();
  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'tankId')::uuid=v_tank;
  perform pg_temp.rec('B7 KeToan: Tồn cuối sau sửa = 1180 (1000+500−320)',
    (r->>'closing')::numeric=1180, 'closing='||(r->>'closing'));

  -- B8) KẾ TOÁN: Báo cáo tháng phản ánh đúng xe với Tổng diesel = 320
  v := rpc_report_monthly(extract(month from current_date)::int, extract(year from current_date)::int);
  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'plate')='QA-E2E';
  perform pg_temp.rec('B8 KeToan: Báo cáo có xe QA-E2E, Tổng diesel = 320',
    r is not null and (r->>'tongDiesel')::numeric=320, 'tongDiesel='||coalesce(r->>'tongDiesel','(không có dòng)'));
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
    (case when (select bool_and(pass) from pg_temp._t) then 'ALL PASS - Luồng đầy đủ chạy đúng' else '*** CÓ FAIL ***' end) kq,
    ('TỔNG '||(select count(*) filter(where pass) from pg_temp._t)||'/'||(select count(*) from pg_temp._t)||' PASS') test, '' note
  union all
  select n, case when pass then 'PASS' else 'FAIL' end, name, coalesce(note,'') from pg_temp._t
) z order by n;
rollback;
