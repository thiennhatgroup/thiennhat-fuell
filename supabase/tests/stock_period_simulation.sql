-- ============================================================================
-- stock_period_simulation.sql — S6 kiểm thử Kỳ điều chỉnh tồn + Phân bổ tịnh.
-- Nạp trực tiếp bút toán xuất vào ledger (vai trò SQL Editor) để cô lập công thức;
-- giả lập auth.uid() cho RPC. BEGIN...ROLLBACK. Chạy trong SQL Editor sau deploy 0012.
--
-- Kịch bản: Tồn đầu 5000. 3 xe bơm (xuất) mỗi xe 1000 → tổng 3000.
--   Tồn sổ tại chốt = 5000 − 3000 = 2000. Tồn thực tế đo tay = 1900.
--   ⇒ Tịnh âm = 100, Tịnh dương = 0.
-- Phân bổ đều 100/3 = 33.33/33.33/33.34 (dồn dư 0.01) → TỔNG khớp tuyệt đối 100.
-- Tồn kho sau chốt = 5000 − 3000 − 100 = 1900 (= thực tế).
-- ============================================================================
begin;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000000','88888888-8888-8888-8888-888888888888','authenticated','authenticated','sim_kt6@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}');
insert into profiles (id, email, name, role, status) values
  ('88888888-8888-8888-8888-888888888888','sim_kt6@test.local','Kế toán S6','KeToan','Hoạt động');

insert into oil_types (id, name) values ('eeeeeeee-0000-0000-0000-000000000001','SIM DO S6');
insert into tanks (id, name, oil_type_id, capacity_liters) values
  ('eeeeeeee-0000-0000-0000-000000000002','SIM Téc S6','eeeeeeee-0000-0000-0000-000000000001', 10000);
insert into vehicles (id, plate, has_odometer) values
  ('eeeeeeee-0000-0000-0000-0000000000a1','SIM-X1', true),
  ('eeeeeeee-0000-0000-0000-0000000000a2','SIM-X2', true),
  ('eeeeeeee-0000-0000-0000-0000000000a3','SIM-X3', true);

do $$
declare
  v_kt uuid := '88888888-8888-8888-8888-888888888888';
  v_oil uuid := 'eeeeeeee-0000-0000-0000-000000000001';
  v_tank uuid := 'eeeeeeee-0000-0000-0000-000000000002';
  v_txn_xuat uuid; v_start date := current_date - 10; v_close date := current_date;
  v_pid uuid; v_res jsonb; v_sum_am numeric; v_cnt int; v_mn numeric; v_mx numeric;
  v_stock jsonb; v_row jsonb;
begin
  select id into v_txn_xuat from transaction_types where code = 'xuat_noi_bo';
  perform set_config('request.jwt.claim.sub', v_kt::text, true);

  -- Tồn đầu 5000.
  perform rpc_tank_opening_set(v_tank, 5000, v_start, 'seed');

  -- 3 xe xuất mỗi xe 1000 trong kỳ (DaDuyet).
  insert into ledger (entry_type, tank_id, oil_type_id, txn_type_id, vehicle_id, liters, status, entry_date, created_by) values
    ('bom', v_tank, v_oil, v_txn_xuat, 'eeeeeeee-0000-0000-0000-0000000000a1', 1000, 'DaDuyet', current_date-5, v_kt),
    ('bom', v_tank, v_oil, v_txn_xuat, 'eeeeeeee-0000-0000-0000-0000000000a2', 1000, 'DaDuyet', current_date-5, v_kt),
    ('bom', v_tank, v_oil, v_txn_xuat, 'eeeeeeee-0000-0000-0000-0000000000a3', 1000, 'DaDuyet', current_date-5, v_kt);

  -- Tạo + chốt kỳ với tồn thực tế 1900.
  v_res := rpc_stock_period_create(v_tank, 'tinh_tec', v_start, 'test');
  v_pid := (v_res->>'id')::uuid;
  v_res := rpc_stock_period_close(v_pid, 1900, v_close);
  assert (v_res->>'book')::numeric = 2000, 'tồn sổ sai (kỳ vọng 2000): ' || (v_res->>'book');
  assert (v_res->>'tinhAm')::numeric = 100, 'tịnh âm sai (kỳ vọng 100): ' || (v_res->>'tinhAm');
  assert (v_res->>'tinhDuong')::numeric = 0, 'tịnh dương sai (kỳ vọng 0)';
  assert (select code from stock_period where id = v_pid) like 'TINH-%', 'phải cấp Số kỳ TINH';

  -- Phân bổ: đúng 3 xe, TỔNG khớp tuyệt đối 100, mỗi xe ~33.33–33.34.
  select count(*), sum(tinh_am), min(tinh_am), max(tinh_am)
    into v_cnt, v_sum_am, v_mn, v_mx from stock_period_alloc where period_id = v_pid;
  assert v_cnt = 3, 'phải có 3 dòng phân bổ, có ' || v_cnt;
  assert v_sum_am = 100, 'TỔNG phân bổ tịnh âm phải = 100 (không lệch làm tròn), = ' || v_sum_am;
  assert v_mn >= 33.33 and v_mx <= 33.34, 'phân bổ đều sai: min=' || v_mn || ' max=' || v_mx;

  -- Tồn kho phản ánh tịnh: 5000 − 3000 − 100 = 1900.
  v_stock := rpc_inventory_stock();
  select r into v_row from jsonb_array_elements(v_stock->'rows') r where (r->>'tankId')::uuid = v_tank;
  assert (v_row->>'tinhAm')::numeric = 100, 'inventory tịnh âm sai';
  assert (v_row->>'closing')::numeric = 1900, 'tồn cuối sau tịnh sai (kỳ vọng 1900): ' || (v_row->>'closing');

  raise notice 'STOCK PERIOD SIMULATION: TẤT CẢ ASSERT PASS ✅';
end $$;

rollback;
