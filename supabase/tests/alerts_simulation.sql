-- ============================================================================
-- alerts_simulation.sql — S7 kiểm thử cảnh báo tồn (alerts_scan/rpc_alerts_*).
-- Giả lập auth.uid() (Kế toán) + nạp bút toán trực tiếp để dựng 3 tình huống téc.
-- BEGIN...ROLLBACK. Chạy trong SQL Editor sau deploy 0013.
--
-- Kịch bản:
--   Téc A: tồn đầu 100, không giao dịch, điểm đặt hàng 500 → 100 ≤ 500 ⇒ TỒN THẤP.
--   Téc B: tồn đầu 100, xuất 300 (DaDuyet) → tồn −200 ⇒ TỒN ÂM.
--   Téc C: tồn đầu 100, nhập 20000 (DaDuyet), sức chứa 10000 → 20100 ⇒ VƯỢT SỨC CHỨA.
-- Kỳ vọng: 3 cảnh báo mới; quét LẠI cùng ngày ⇒ 0 (dedup); danh sách unread=3;
--   đánh dấu đọc hết ⇒ unread=0.
-- ============================================================================
begin;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000000','77777777-7777-7777-7777-777777777777','authenticated','authenticated','sim_kt7@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}');
insert into profiles (id, email, name, role, status) values
  ('77777777-7777-7777-7777-777777777777','sim_kt7@test.local','Kế toán S7','KeToan','Hoạt động');

insert into oil_types (id, name) values ('dddddddd-0000-0000-0000-000000000001','SIM DO S7');
insert into tanks (id, name, oil_type_id, capacity_liters, reorder_point) values
  ('dddddddd-0000-0000-0000-0000000000a1','SIM Téc A','dddddddd-0000-0000-0000-000000000001', 20000, 500),
  ('dddddddd-0000-0000-0000-0000000000b1','SIM Téc B','dddddddd-0000-0000-0000-000000000001', 20000, 0),
  ('dddddddd-0000-0000-0000-0000000000c1','SIM Téc C','dddddddd-0000-0000-0000-000000000001', 10000, 0);

do $$
declare
  v_kt uuid := '77777777-7777-7777-7777-777777777777';
  v_oil uuid := 'dddddddd-0000-0000-0000-000000000001';
  v_ta uuid := 'dddddddd-0000-0000-0000-0000000000a1';
  v_tb uuid := 'dddddddd-0000-0000-0000-0000000000b1';
  v_tc uuid := 'dddddddd-0000-0000-0000-0000000000c1';
  v_txn_xuat uuid; v_txn_nhap uuid; v_res jsonb; v_n int;
begin
  select id into v_txn_xuat from transaction_types where code = 'xuat_noi_bo';
  select id into v_txn_nhap from transaction_types where code = 'nhap_kho';
  perform set_config('request.jwt.claim.sub', v_kt::text, true);

  -- Tồn đầu.
  perform rpc_tank_opening_set(v_ta, 100, current_date, 'seed');
  perform rpc_tank_opening_set(v_tb, 100, current_date, 'seed');
  perform rpc_tank_opening_set(v_tc, 100, current_date, 'seed');

  -- Téc B xuất 300 → âm; Téc C nhập 20000 → vượt sức chứa.
  insert into ledger (entry_type, tank_id, oil_type_id, txn_type_id, liters, status, entry_date, created_by) values
    ('bom',  v_tb, v_oil, v_txn_xuat, 300,   'DaDuyet', current_date, v_kt),
    ('nhap', v_tc, v_oil, v_txn_nhap, 20000, 'DaDuyet', current_date, v_kt);

  -- Quét lần 1 → 3 cảnh báo mới.
  v_res := rpc_alerts_scan();
  assert (v_res->>'created')::int = 3, 'quét lần 1 phải tạo 3 cảnh báo, có ' || (v_res->>'created');

  -- Đúng loại cảnh báo.
  assert exists (select 1 from notification where tank_id = v_ta and kind = 'ton_thap'), 'Téc A phải tồn thấp';
  assert exists (select 1 from notification where tank_id = v_tb and kind = 'ton_am'), 'Téc B phải tồn âm';
  assert exists (select 1 from notification where tank_id = v_tc and kind = 'vuot_suc_chua'), 'Téc C phải vượt sức chứa';

  -- Quét lần 2 cùng ngày → 0 (dedup theo kind:tank:ngày).
  v_res := rpc_alerts_scan();
  assert (v_res->>'created')::int = 0, 'quét lần 2 phải 0 (dedup), có ' || (v_res->>'created');

  -- Danh sách: unread = 3.
  v_res := rpc_alerts_list(100);
  assert (v_res->>'unread')::int = 3, 'unread phải 3, có ' || (v_res->>'unread');
  assert jsonb_array_length(v_res->'rows') = 3, 'phải liệt kê 3 cảnh báo';

  -- Đánh dấu đọc hết → unread = 0.
  perform rpc_alerts_mark_read(null);
  v_res := rpc_alerts_list(100);
  assert (v_res->>'unread')::int = 0, 'sau khi đọc hết unread phải 0, có ' || (v_res->>'unread');

  -- Đăng ký push (không thực gửi — chỉ lưu subscription).
  perform rpc_push_subscribe('https://push.example/ep1', 'p256dh_key', 'auth_key', 'sim-ua');
  assert exists (select 1 from push_subscription where endpoint = 'https://push.example/ep1' and user_id = v_kt),
    'phải lưu push subscription';
  perform rpc_push_unsubscribe('https://push.example/ep1');
  assert not exists (select 1 from push_subscription where endpoint = 'https://push.example/ep1'),
    'phải hủy push subscription';

  raise notice 'ALERTS SIMULATION: TẤT CẢ ASSERT PASS ✅';
end $$;

rollback;
