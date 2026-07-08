-- ============================================================================
-- qa_05_stock_period.sql — Tịnh téc / Kiểm kê + phân bổ (S6).
-- Chốt kỳ: diff = book − thực tế → tịnh âm/dương; phân bổ theo lít-trong-kỳ,
-- dồn dư vào xe lớn nhất → tổng phân bổ KHỚP TUYỆT ĐỐI. Sau chốt: Tồn cuối = thực tế.
-- Kiểm kê BẮT BUỘC biên bản (rpc_stock_period_record); tịnh téc không.
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333','authenticated','authenticated','qa_kt@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('33333333-3333-3333-3333-333333333333','qa_kt@test.local','QA KeToan','KeToan','Hoạt động');
insert into oil_types (id,name) values ('a0000000-0000-0000-0000-000000000001','QA DO');
insert into tanks (id,name,capacity_liters) values
  ('a0000000-0000-0000-0000-000000000021','QA T-am',10000),
  ('a0000000-0000-0000-0000-000000000022','QA T-duong',10000),
  ('a0000000-0000-0000-0000-000000000023','QA T-kiemke',10000);
insert into vehicles (id,plate) values
  ('a0000000-0000-0000-0000-000000000031','QA-V1'),
  ('a0000000-0000-0000-0000-000000000032','QA-V2'),
  ('a0000000-0000-0000-0000-000000000033','QA-V3');
insert into tank_opening (tank_id, liters) values
  ('a0000000-0000-0000-0000-000000000021',1000),
  ('a0000000-0000-0000-0000-000000000022',500);

-- Xuất trong kỳ: T-am ← V1 300, V2 200, V3 100 (tổng 600). T-duong ← V1 100.
insert into ledger (entry_type,entry_date,vehicle_id,txn_type_id,tank_id,oil_type_id,liters,status,created_by)
select 'bom', current_date-5, x.veh, (select id from transaction_types where code='xuat_noi_bo'),
       x.tk, 'a0000000-0000-0000-0000-000000000001', x.lit, 'DaDuyet', '33333333-3333-3333-3333-333333333333'
from (values
  ('a0000000-0000-0000-0000-000000000031'::uuid,'a0000000-0000-0000-0000-000000000021'::uuid,300::numeric),
  ('a0000000-0000-0000-0000-000000000032'::uuid,'a0000000-0000-0000-0000-000000000021'::uuid,200::numeric),
  ('a0000000-0000-0000-0000-000000000033'::uuid,'a0000000-0000-0000-0000-000000000021'::uuid,100::numeric),
  ('a0000000-0000-0000-0000-000000000031'::uuid,'a0000000-0000-0000-0000-000000000022'::uuid,100::numeric)
) x(veh,tk,lit);

do $$
declare
  v_kt uuid := '33333333-3333-3333-3333-333333333333';
  v_tam uuid := 'a0000000-0000-0000-0000-000000000021';
  v_tdg uuid := 'a0000000-0000-0000-0000-000000000022';
  v_tkk uuid := 'a0000000-0000-0000-0000-000000000023';
  v jsonb; r jsonb; pid uuid; v_am numeric; v_book numeric; v_sum numeric; v_cnt int;
begin
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);

  -- ===== Tịnh âm: book 400 (1000−600), thực tế 350 → tịnh âm 50 =====
  v := rpc_stock_period_create(v_tam, 'tinh_tec', current_date-10, 'QA kỳ âm');  pid := (v->>'id')::uuid;
  v := rpc_stock_period_close(pid, 350, current_date);
  v_book := (v->>'book')::numeric; v_am := (v->>'tinhAm')::numeric;
  perform pg_temp.rec('Book trước chốt = 400 (1000−600 xuất)', v_book=400, 'book='||v_book);
  perform pg_temp.rec('Tịnh âm = 50 (book 400 − thực tế 350)', v_am=50, 'tinhAm='||v_am);

  select coalesce(sum(tinh_am),0), count(*) into v_sum, v_cnt from stock_period_alloc where period_id=pid;
  perform pg_temp.rec('Phân bổ đúng 3 xe', v_cnt=3, 'số dòng='||v_cnt);
  perform pg_temp.rec('Tổng phân bổ tịnh âm KHỚP TUYỆT ĐỐI = kỳ (50.00)',
    v_sum=(select tinh_am from stock_period where id=pid), 'Σalloc='||v_sum);

  -- Tồn cuối sau chốt = thực tế (350): opening 1000 − xuất 600 − tịnh âm 50
  v := rpc_inventory_stock();
  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'tankId')::uuid=v_tam;
  perform pg_temp.rec('Sau chốt: Tồn cuối = thực tế (350)', (r->>'closing')::numeric=350, 'closing='||(r->>'closing'));

  -- ===== Tịnh dương: book 400 (500−100), thực tế 450 → tịnh dương 50 =====
  v := rpc_stock_period_create(v_tdg, 'tinh_tec', current_date-10, 'QA kỳ dương');  pid := (v->>'id')::uuid;
  v := rpc_stock_period_close(pid, 450, current_date);
  perform pg_temp.rec('Tịnh dương = 50 (thực tế 450 − book 400)', (v->>'tinhDuong')::numeric=50, 'tinhDuong='||(v->>'tinhDuong'));
  select coalesce(sum(tinh_duong),0) into v_sum from stock_period_alloc where period_id=pid;
  perform pg_temp.rec('Tổng phân bổ tịnh dương KHỚP kỳ (50.00)',
    v_sum=(select tinh_duong from stock_period where id=pid), 'Σalloc='||v_sum);

  -- ===== Kiểm kê BẮT BUỘC biên bản =====
  begin
    perform rpc_stock_period_record(v_tkk, 'kiem_ke', current_date-3, current_date, 100, 'QA', null);
    perform pg_temp.rec('Chặn Kiểm kê thiếu biên bản', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn Kiểm kê thiếu biên bản', sqlerrm like '%biên bản%', sqlerrm);
  end;
  v := rpc_stock_period_record(v_tkk, 'kiem_ke', current_date-3, current_date, 100, 'QA', 'kiemke/bb.jpg');
  perform pg_temp.rec('Kiểm kê CÓ biên bản → chốt được', (v->>'ok')='true', 'ok='||coalesce(v->>'ok','null'));
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
