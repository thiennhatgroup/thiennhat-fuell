-- ============================================================================
-- pump_photo_flow.sql — S3 kiểm thử Ảnh chứng từ bắt buộc + RPC metadata.
-- Giả lập auth.uid() qua request.jwt.claim.sub. BEGIN...ROLLBACK, không để lại
-- dữ liệu. Sandbox không có DB → chạy trong Supabase SQL Editor sau deploy 0008.
--
-- Khẳng định:
--   1. Submit chặn khi thiếu ảnh đồng hồ bơm.
--   2. Submit vẫn chặn khi có đồng hồ bơm nhưng thiếu công-tơ-mét (xe có ĐH KM).
--   3. Đủ 2 ảnh → submit thành công, cấp Số phiếu.
--   4. rpc_pump_photo_add từ chối path không thuộc phiếu.
--   5. Không đính/xóa ảnh được khi phiếu đã rời trạng thái Nháp.
--   6. Xe KHÔNG có công-tơ-mét: chỉ cần ảnh đồng hồ bơm là submit được.
-- ============================================================================
begin;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values ('00000000-0000-0000-0000-000000000000','33333333-3333-3333-3333-333333333333','authenticated','authenticated','sim_p@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}');
insert into profiles (id, email, name, role, status) values
  ('33333333-3333-3333-3333-333333333333','sim_p@test.local','Thủ kho P','ThuKho','Hoạt động');

insert into oil_types (id, name) values ('bbbbbbbb-0000-0000-0000-000000000001','SIM DO P');
insert into tanks (id, name, capacity_liters) values ('bbbbbbbb-0000-0000-0000-000000000002','SIM Téc P', 10000);
insert into vehicles (id, plate, has_odometer) values
  ('bbbbbbbb-0000-0000-0000-000000000003','SIM-ODO', true),
  ('bbbbbbbb-0000-0000-0000-000000000004','SIM-NOODO', false);

do $$
declare
  v_uid uuid := '33333333-3333-3333-3333-333333333333';
  v_oil uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_tank uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_veh uuid := 'bbbbbbbb-0000-0000-0000-000000000003';   -- có công-tơ-mét
  v_veh_no uuid := 'bbbbbbbb-0000-0000-0000-000000000004'; -- không công-tơ-mét
  v_txn uuid;
  v_id uuid; v_pid uuid; v_res jsonb; v_status text;
begin
  select id into v_txn from transaction_types where code = 'xuat_noi_bo';
  perform set_config('request.jwt.claim.sub', v_uid::text, true);

  -- Phiếu cho xe có công-tơ-mét
  v_res := rpc_pump_create(v_veh, v_txn, v_oil, 100, v_tank, 5000, 4000);
  v_id := (v_res->>'id')::uuid;

  -- (1) Thiếu hết ảnh → submit chặn.
  begin
    perform rpc_pump_submit_day();
    assert false, '(1) submit thiếu ảnh lẽ ra phải lỗi';
  exception when others then
    assert sqlerrm like '%đồng hồ bơm%', '(1) sai thông báo: ' || sqlerrm;
  end;

  -- (4) path không thuộc phiếu → từ chối.
  begin
    perform rpc_pump_photo_add(v_id, 'pump_meter', 'khac/anh.jpg');
    assert false, '(4) path lạ lẽ ra phải lỗi';
  exception when others then
    assert sqlerrm like '%không thuộc phiếu%', '(4) sai thông báo: ' || sqlerrm;
  end;

  -- Đính ảnh đồng hồ bơm (đúng path).
  v_res := rpc_pump_photo_add(v_id, 'pump_meter', v_id::text || '/pump_meter.jpg');
  v_pid := (v_res->>'id')::uuid;

  -- (2) Có đồng hồ bơm nhưng thiếu công-tơ-mét (xe có ĐH KM) → vẫn chặn.
  begin
    perform rpc_pump_submit_day();
    assert false, '(2) submit thiếu công-tơ-mét lẽ ra phải lỗi';
  exception when others then
    assert sqlerrm like '%công-tơ-mét%', '(2) sai thông báo: ' || sqlerrm;
  end;

  -- Đủ 2 ảnh.
  perform rpc_pump_photo_add(v_id, 'odometer', v_id::text || '/odometer.jpg');

  -- (3) Đủ ảnh → submit thành công.
  v_res := rpc_pump_submit_day();
  select status into v_status from ledger where id = v_id;
  assert v_status = 'ChoDoiChieu', '(3) đủ ảnh phải submit được, status=' || v_status;
  assert (select code from ledger where id = v_id) like 'BOM-%', '(3) phải cấp Số phiếu';

  -- (5) Phiếu đã rời Nháp → không đính/xóa ảnh được.
  begin
    perform rpc_pump_photo_add(v_id, 'pump_meter', v_id::text || '/again.jpg');
    assert false, '(5) đính ảnh khi không phải Nháp lẽ ra phải lỗi';
  exception when others then
    assert sqlerrm like '%còn Nháp%', '(5a) sai thông báo: ' || sqlerrm;
  end;
  begin
    perform rpc_pump_photo_delete(v_pid);
    assert false, '(5) xóa ảnh khi không phải Nháp lẽ ra phải lỗi';
  exception when others then
    assert sqlerrm like '%còn Nháp%', '(5b) sai thông báo: ' || sqlerrm;
  end;

  -- (6) Xe không công-tơ-mét: chỉ cần ảnh đồng hồ bơm.
  v_res := rpc_pump_create(v_veh_no, v_txn, v_oil, 80, v_tank, null, null);
  v_id := (v_res->>'id')::uuid;
  perform rpc_pump_photo_add(v_id, 'pump_meter', v_id::text || '/pump_meter.jpg');
  perform rpc_pump_submit_day();
  select status into v_status from ledger where id = v_id;
  assert v_status = 'ChoDoiChieu', '(6) xe không công-tơ-mét chỉ cần 1 ảnh, status=' || v_status;

  raise notice 'PUMP PHOTO FLOW SIMULATION: TẤT CẢ ASSERT PASS ✅';
end $$;

rollback;
