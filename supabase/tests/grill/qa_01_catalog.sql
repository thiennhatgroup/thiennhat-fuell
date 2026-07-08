-- ============================================================================
-- qa_01_catalog.sql — Danh mục & Xe (S1 + Batch 5 xóa-cứng-có-chặn).
-- Vai trò: KeToan có catalog:manage; ThuKho KHÔNG. begin…rollback.
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

do $$
declare
  v_kt uuid := '33333333-3333-3333-3333-333333333333';
  v_oil uuid; v_tank uuid; v_veh uuid; v_oil2 uuid; v_txn uuid; v jsonb; v_n int;
begin
  perform set_config('request.jwt.claim.sub', (v_kt)::text, true);

  -- 1) Tạo loại dầu
  v := rpc_oil_type_upsert(null, 'QA Oil', true);  v_oil := (v->>'id')::uuid;
  perform pg_temp.rec('Tạo Loại dầu', exists(select 1 from oil_types where id=v_oil and active), 'id='||v_oil);

  -- 2) Tạo téc (gắn loại dầu)
  v := rpc_tank_upsert(null, 'QA Tank', v_oil, 10000, 2000, 5, true);  v_tank := (v->>'id')::uuid;
  perform pg_temp.rec('Tạo Téc (cap 10000/reorder 2000/lead 5)',
    exists(select 1 from tanks where id=v_tank and capacity_liters=10000 and reorder_point=2000 and lead_time_days=5),
    'id='||v_tank);

  -- 3) Tạo xe
  v := rpc_vehicle_upsert(null, 'QA-CAT-1', 120, true, true, 'Thiên Nhật');  v_veh := (v->>'id')::uuid;
  perform pg_temp.rec('Tạo Xe (định mức 120, có công-tơ-mét)',
    exists(select 1 from vehicles where id=v_veh and pump_norm=120 and has_odometer), 'id='||v_veh);

  -- 4) Ngừng (toggle) téc
  perform rpc_catalog_toggle('tank', v_tank, false);
  perform pg_temp.rec('Ngừng Téc (toggle active=false)',
    not (select active from tanks where id=v_tank), 'active sau toggle');

  -- 5) Đổi tên Loại giao dịch (cố định, chỉ đổi tên)
  select id into v_txn from transaction_types where code='xuat_noi_bo';
  perform rpc_txn_type_upsert(v_txn, 'QA Xuất nội bộ', true);
  perform pg_temp.rec('Đổi tên Loại giao dịch',
    (select name from transaction_types where id=v_txn)='QA Xuất nội bộ', 'tên mới');

  -- 6) Xóa loại dầu CHƯA tham chiếu → OK
  v := rpc_oil_type_upsert(null, 'QA Oil Rảnh', true);  v_oil2 := (v->>'id')::uuid;
  perform rpc_catalog_delete('oilType', v_oil2);
  perform pg_temp.rec('Xóa danh mục chưa tham chiếu',
    not exists(select 1 from oil_types where id=v_oil2), 'đã xóa');

  -- 7) Xóa Loại giao dịch → LUÔN bị chặn
  begin
    perform rpc_catalog_delete('txnType', v_txn);
    perform pg_temp.rec('Chặn xóa Loại giao dịch', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn xóa Loại giao dịch', sqlerrm like '%cố định%', 'đã chặn: '||sqlerrm);
  end;

  -- 8) Xóa Xe ĐÃ tham chiếu (có bút toán) → bị chặn, gợi ý "Ngừng"
  insert into ledger (entry_type, vehicle_id, txn_type_id, oil_type_id, liters, status, created_by)
    values ('bom', v_veh, v_txn, v_oil, 10, 'Nhap', v_kt);
  begin
    perform rpc_catalog_delete('vehicle', v_veh);
    perform pg_temp.rec('Chặn xóa Xe đã có dữ liệu', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn xóa Xe đã có dữ liệu', sqlerrm like '%liên quan%', 'đã chặn: '||sqlerrm);
  end;
end $$;

-- 9) ThuKho không có catalog:manage → tạo danh mục bị chặn
do $$
begin
  perform set_config('request.jwt.claim.sub', ('11111111-1111-1111-1111-111111111111')::text, true);
  begin
    perform rpc_oil_type_upsert(null, 'ThuKho cố tạo', true);
    perform pg_temp.rec('Chặn ThuKho sửa danh mục', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn ThuKho sửa danh mục', true, 'đã chặn: '||sqlerrm);
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
