-- ============================================================================
-- inventory_stock_simulation.sql — S5 kiểm thử Tồn kho thời gian thực.
-- Nạp trực tiếp bút toán vào `ledger` (chạy dưới vai trò SQL Editor) để cô lập
-- CÔNG THỨC tồn kho; giả lập auth.uid() qua request.jwt.claim.sub cho các RPC.
-- BEGIN...ROLLBACK, không để lại dữ liệu. Chạy trong Supabase SQL Editor sau
-- deploy 0011.
--
-- Kịch bản (téc SIM): Tồn đầu 5000; Nhập 2000 (DaDuyet) + 1000 (legacy) +
-- 500 (ChoDoiChieu, KHÔNG tính); Xuất 800 (DaDuyet) + 100 (Nhap, KHÔNG tính);
-- Bơm ngoài 300 (tank_id null, KHÔNG trừ tồn).
-- Kỳ vọng: Nhập=3000, Xuất=800, Tồn cuối = 5000 + 3000 − 800 = 7200.
-- ============================================================================
begin;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000','66666666-6666-6666-6666-666666666666','authenticated','authenticated','sim_tk@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}'),
  ('00000000-0000-0000-0000-000000000000','77777777-7777-7777-7777-777777777777','authenticated','authenticated','sim_kt@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}');
insert into profiles (id, email, name, role, status) values
  ('66666666-6666-6666-6666-666666666666','sim_tk@test.local','Thủ kho S5','ThuKho','Hoạt động'),
  ('77777777-7777-7777-7777-777777777777','sim_kt@test.local','Kế toán S5','KeToan','Hoạt động');

insert into oil_types (id, name) values ('dddddddd-0000-0000-0000-000000000001','SIM DO S5');
insert into tanks (id, name, oil_type_id, capacity_liters, reorder_point) values
  ('dddddddd-0000-0000-0000-000000000002','SIM Téc S5','dddddddd-0000-0000-0000-000000000001', 10000, 1000);

do $$
declare
  v_tk uuid := '66666666-6666-6666-6666-666666666666';
  v_kt uuid := '77777777-7777-7777-7777-777777777777';
  v_oil uuid := 'dddddddd-0000-0000-0000-000000000001';
  v_tank uuid := 'dddddddd-0000-0000-0000-000000000002';
  v_txn_xuat uuid;
  v_stock jsonb; v_row jsonb;
begin
  select id into v_txn_xuat from transaction_types where code = 'xuat_noi_bo';

  -- Tồn đầu 5000 (KeToan chốt).
  perform set_config('request.jwt.claim.sub', v_kt::text, true);
  perform rpc_tank_opening_set(v_tank, 5000, current_date, 'seed test');

  -- Bút toán (nạp trực tiếp): nhập/xuất/bơm ngoài với trạng thái khác nhau.
  insert into ledger (entry_type, tank_id, oil_type_id, txn_type_id, liters, status, legacy, created_by) values
    ('nhap', v_tank, v_oil, null,        2000, 'DaDuyet',     false, v_tk),  -- tính
    ('nhap', v_tank, v_oil, null,        1000, 'Nhap',        true,  v_tk),  -- legacy → tính
    ('nhap', v_tank, v_oil, null,         500, 'ChoDoiChieu', false, v_tk),  -- KHÔNG tính
    ('bom',  v_tank, v_oil, v_txn_xuat,   800, 'DaDuyet',     false, v_tk),  -- xuất, tính
    ('bom',  v_tank, v_oil, v_txn_xuat,   100, 'Nhap',        false, v_tk),  -- KHÔNG tính
    ('bom',  null,   v_oil, null,         300, 'DaDuyet',     false, v_tk);  -- bơm ngoài, không trừ

  -- Đọc tồn kho (ThuKho có inventory:read).
  perform set_config('request.jwt.claim.sub', v_tk::text, true);
  v_stock := rpc_inventory_stock();
  select r into v_row from jsonb_array_elements(v_stock->'rows') r
   where (r->>'tankId')::uuid = v_tank;

  assert v_row is not null, 'không thấy téc SIM trong tồn kho';
  assert (v_row->>'opening')::numeric = 5000, 'Tồn đầu sai: ' || (v_row->>'opening');
  assert (v_row->>'nhap')::numeric = 3000, 'Nhập sai (kỳ vọng 3000): ' || (v_row->>'nhap');
  assert (v_row->>'xuat')::numeric = 800,  'Xuất sai (kỳ vọng 800): ' || (v_row->>'xuat');
  assert (v_row->>'closing')::numeric = 7200, 'Tồn cuối sai (kỳ vọng 7200): ' || (v_row->>'closing');
  assert (v_row->>'pctFull')::numeric = 72.0, '%đầy sai (kỳ vọng 72): ' || (v_row->>'pctFull');

  raise notice 'INVENTORY STOCK SIMULATION: TẤT CẢ ASSERT PASS ✅';
end $$;

rollback;
