-- ============================================================================
-- qa_06_alerts.sql — Cảnh báo tồn (S7): tồn thấp / tồn âm / vượt sức chứa,
-- dedup theo kind:tank:ngày, danh sách + đánh dấu đã đọc + phân quyền alert:read.
-- Chạy trên DB thật trong begin…rollback; chỉ soi 3 téc QA (uuid riêng).
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333','authenticated','authenticated','qa_kt@test.local','x',now(),now(),now(),'{"provider":"email"}','{}'),
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','qa_tk@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('33333333-3333-3333-3333-333333333333','qa_kt@test.local','QA KeToan','KeToan','Hoạt động'),
 ('11111111-1111-1111-1111-111111111111','qa_tk@test.local','QA ThuKho','ThuKho','Hoạt động');
insert into oil_types (id,name) values ('a0000000-0000-0000-0000-000000000001','QA DO');
insert into vehicles (id,plate) values ('a0000000-0000-0000-0000-000000000003','QA-AL');
-- T-low: tồn 1500 ≤ reorder 2000 → ton_thap
-- T-neg: 100 − xuất 500 = −400 → ton_am
-- T-over: 12000 > sức chứa 10000 → vuot_suc_chua
insert into tanks (id,name,capacity_liters,reorder_point) values
  ('a0000000-0000-0000-0000-000000000041','QA T-low',10000,2000),
  ('a0000000-0000-0000-0000-000000000042','QA T-neg',10000,0),
  ('a0000000-0000-0000-0000-000000000043','QA T-over',10000,0);
insert into tank_opening (tank_id,liters) values
  ('a0000000-0000-0000-0000-000000000041',1500),
  ('a0000000-0000-0000-0000-000000000042',100),
  ('a0000000-0000-0000-0000-000000000043',12000);
insert into ledger (entry_type,entry_date,vehicle_id,txn_type_id,tank_id,oil_type_id,liters,status,created_by)
  values ('bom',current_date,'a0000000-0000-0000-0000-000000000003',
          (select id from transaction_types where code='xuat_noi_bo'),
          'a0000000-0000-0000-0000-000000000042','a0000000-0000-0000-0000-000000000001',500,'DaDuyet',
          '33333333-3333-3333-3333-333333333333');

do $$
declare
  v_kt uuid := '33333333-3333-3333-3333-333333333333';
  v_low uuid := 'a0000000-0000-0000-0000-000000000041';
  v_neg uuid := 'a0000000-0000-0000-0000-000000000042';
  v_over uuid := 'a0000000-0000-0000-0000-000000000043';
  v jsonb; v_created int; v_n int; v_nid uuid;
begin
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);

  -- 1) Quét lần 1
  v := rpc_alerts_scan();  v_created := (v->>'created')::int;
  perform pg_temp.rec('Quét tạo ≥ 3 cảnh báo (gồm 3 téc QA)', v_created >= 3, 'created='||v_created);

  -- 2) Đúng loại cảnh báo cho từng téc QA
  perform pg_temp.rec('T-low → ton_thap',
    exists(select 1 from notification where tank_id=v_low and kind='ton_thap'), null);
  perform pg_temp.rec('T-neg → ton_am',
    exists(select 1 from notification where tank_id=v_neg and kind='ton_am'), null);
  perform pg_temp.rec('T-over → vuot_suc_chua',
    exists(select 1 from notification where tank_id=v_over and kind='vuot_suc_chua'), null);

  -- 3) Dedup: quét lần 2 KHÔNG nhân đôi cảnh báo của téc QA
  perform rpc_alerts_scan();
  select count(*) into v_n from notification where tank_id in (v_low,v_neg,v_over);
  perform pg_temp.rec('Dedup: mỗi téc QA vẫn đúng 1 cảnh báo sau 2 lần quét', v_n=3, 'đếm='||v_n);

  -- 4) Danh sách (KeToan có alert:read) chứa cảnh báo téc QA
  v := rpc_alerts_list(200);
  perform pg_temp.rec('KeToan xem được danh sách cảnh báo', (v->>'ok')='true',
    'unread='||coalesce(v->>'unread','null'));

  -- 5) Đánh dấu đã đọc 1 cảnh báo
  select id into v_nid from notification where tank_id=v_low limit 1;
  perform rpc_alerts_mark_read(v_nid);
  perform pg_temp.rec('Đánh dấu đã đọc ghi nhận',
    exists(select 1 from notification_read where notification_id=v_nid and user_id=v_kt), null);

  -- 6) ThuKho KHÔNG có alert:read → chặn
  perform set_config('request.jwt.claim.sub', ('11111111-1111-1111-1111-111111111111')::text, true);
  begin
    perform rpc_alerts_list(50);
    perform pg_temp.rec('Chặn ThuKho xem cảnh báo', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn ThuKho xem cảnh báo', true, 'đã chặn: '||sqlerrm);
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
