-- ============================================================================
-- qa_04_inventory.sql — Công thức Tồn kho (S5 + Batch 4).
-- Tồn cuối = Tồn đầu + Nhập − Xuất − Tịnh âm + Tịnh dương.
-- Chỉ tính DaDuyet/legacy. Bơm ngoài (kind bom_ngoai) KHÔNG trừ tồn dù gắn téc.
-- Téc bật clamp_negative kẹp về 0. Chèn thẳng ledger để kiểm soát tuyệt đối.
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
insert into tanks (id,name,oil_type_id,capacity_liters,reorder_point,clamp_negative) values
  ('a0000000-0000-0000-0000-0000000000a1','QA T1',null,10000,2000,false),
  ('a0000000-0000-0000-0000-0000000000a2','QA T2 (clamp)',null,10000,2000,true),
  ('a0000000-0000-0000-0000-0000000000a3','QA T3',null,10000,2000,false);
insert into vehicles (id,plate) values ('a0000000-0000-0000-0000-000000000003','QA-INV');

-- Tồn đầu gốc
insert into tank_opening (tank_id, liters) values
  ('a0000000-0000-0000-0000-0000000000a1',1000),
  ('a0000000-0000-0000-0000-0000000000a2',100),
  ('a0000000-0000-0000-0000-0000000000a3',100);

-- Bút toán T1: nhap 500 (DaDuyet), xuat 300 (DaDuyet), xuat 150 (legacy),
--   xuat 100 (Nhap → BỎ), bom_ngoai 999 gắn T1 (kind bom_ngoai → KHÔNG trừ).
insert into ledger (entry_type,entry_date,vehicle_id,txn_type_id,tank_id,oil_type_id,liters,status,legacy,created_by)
select x.et, current_date, 'a0000000-0000-0000-0000-000000000003',
       (select id from transaction_types where code=x.tc),
       'a0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001',
       x.lit, x.st, x.lg, '33333333-3333-3333-3333-333333333333'
from (values
  ('nhap','nhap_kho',   500::numeric,'DaDuyet',false),
  ('bom', 'xuat_noi_bo',300::numeric,'DaDuyet',false),
  ('bom', 'xuat_noi_bo',150::numeric,'DaDuyet',true),   -- legacy
  ('bom', 'xuat_noi_bo',100::numeric,'Nhap',   false),  -- nháp → bỏ
  ('bom', 'bom_ngoai',  999::numeric,'DaDuyet',false)   -- bơm ngoài → không trừ téc
) as x(et,tc,lit,st,lg);

-- T2 (clamp): opening 100, xuat 500 (DaDuyet) → raw -400 → kẹp 0
-- T3        : opening 100, xuat 500 (DaDuyet) → -400 (không kẹp)
insert into ledger (entry_type,entry_date,vehicle_id,txn_type_id,tank_id,oil_type_id,liters,status,legacy,created_by)
select 'bom', current_date, 'a0000000-0000-0000-0000-000000000003',
       (select id from transaction_types where code='xuat_noi_bo'), tk,
       'a0000000-0000-0000-0000-000000000001', 500, 'DaDuyet', false,
       '33333333-3333-3333-3333-333333333333'
from (values ('a0000000-0000-0000-0000-0000000000a2'::uuid),('a0000000-0000-0000-0000-0000000000a3'::uuid)) v(tk);

do $$
declare
  v jsonb; r jsonb;
  v_t1 uuid := 'a0000000-0000-0000-0000-0000000000a1';
  v_t2 uuid := 'a0000000-0000-0000-0000-0000000000a2';
  v_t3 uuid := 'a0000000-0000-0000-0000-0000000000a3';
begin
  perform set_config('request.jwt.claim.sub', ('33333333-3333-3333-3333-333333333333')::text, true);
  v := rpc_inventory_stock();

  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'tankId')::uuid=v_t1;
  perform pg_temp.rec('T1 Nhập = 500', (r->>'nhap')::numeric=500, 'nhap='||(r->>'nhap'));
  perform pg_temp.rec('T1 Xuất = 450 (DaDuyet 300 + legacy 150; loại Nháp 100 & bơm ngoài)',
    (r->>'xuat')::numeric=450, 'xuat='||(r->>'xuat'));
  perform pg_temp.rec('T1 Tồn cuối = 1050 (1000+500−450)', (r->>'closing')::numeric=1050, 'closing='||(r->>'closing'));

  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'tankId')::uuid=v_t2;
  perform pg_temp.rec('T2 kẹp âm về 0 (100−500 → 0)', (r->>'closing')::numeric=0, 'closing='||(r->>'closing'));

  select value into r from jsonb_array_elements(v->'rows') e(value) where (e.value->>'tankId')::uuid=v_t3;
  perform pg_temp.rec('T3 KHÔNG kẹp → âm −400', (r->>'closing')::numeric=-400, 'closing='||(r->>'closing'));
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
