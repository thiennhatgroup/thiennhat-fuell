-- ============================================================================
-- pump_flow_simulation.sql — S2 kiểm thử hành vi ở ranh giới RPC.
-- Mô phỏng end-to-end vòng đời Phiếu bơm bằng cách giả lập auth.uid() qua
-- request.jwt.claim.sub (đúng cách Supabase đọc auth.uid()).
--
-- CÁCH CHẠY: dán vào Supabase SQL Editor (đã deploy 0001..0007). Toàn bộ nằm
-- trong BEGIN...ROLLBACK nên KHÔNG để lại dữ liệu. Sandbox không có psql/DB
-- nên script này CHƯA chạy thật — chạy sau khi deploy để validate.
--
-- Khẳng định (dùng `assert`, lỗi sẽ dừng ngay):
--   1. Tạo/sửa/xóa Nháp; Submit ngày → ChoDoiChieu + cấp Số phiếu.
--   2. RutLai được khi chưa đối chiếu.
--   3. ThuKho KHÔNG tự duyệt được phiếu của chính mình.
--   4. Khớp → DaDuyet; Lệch → về Nhap kèm lý do.
--   5. Chỉ DaDuyet nằm trong tập "tính vào tồn kho".
-- ============================================================================
begin;

-- Hai thủ kho test (fixed uuid). auth.users tối thiểu để thỏa FK profiles.id.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','sim_a@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}'),
  ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','sim_b@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}');
insert into profiles (id, email, name, role, status) values
  ('11111111-1111-1111-1111-111111111111','sim_a@test.local','Thủ kho A','ThuKho','Hoạt động'),
  ('22222222-2222-2222-2222-222222222222','sim_b@test.local','Thủ kho B','ThuKho','Hoạt động');

-- Danh mục tối thiểu.
insert into oil_types (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001','SIM DO');
insert into tanks (id, name, capacity_liters) values ('aaaaaaaa-0000-0000-0000-000000000002','SIM Téc', 10000);
insert into vehicles (id, plate) values ('aaaaaaaa-0000-0000-0000-000000000003','SIM-99');

do $$
declare
  v_uid_a uuid := '11111111-1111-1111-1111-111111111111';
  v_uid_b uuid := '22222222-2222-2222-2222-222222222222';
  v_oil uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_tank uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  v_veh uuid := 'aaaaaaaa-0000-0000-0000-000000000003';
  v_txn uuid;
  v_id uuid;
  v_res jsonb;
  v_status text;
  v_code text;
  v_n int;
begin
  select id into v_txn from transaction_types where code = 'xuat_noi_bo';

  -- === Thủ kho A tạo 2 phiếu nháp ===
  perform set_config('request.jwt.claim.sub', v_uid_a::text, true);
  v_res := rpc_pump_create(v_veh, v_txn, v_oil, 100, v_tank, 5000, 4000);
  v_id := (v_res->>'id')::uuid;
  perform rpc_pump_create(v_veh, v_txn, v_oil, 50, v_tank, 6000, 5000);
  select count(*) into v_n from ledger where created_by = v_uid_a and status = 'Nhap';
  assert v_n = 2, '(1) phải có 2 phiếu Nháp, có ' || v_n;

  -- Sửa phiếu Nháp
  perform rpc_pump_update(v_id, v_veh, v_txn, v_oil, 120, v_tank, 5200, 4000);
  assert (select liters from ledger where id = v_id) = 120, '(1) sửa lít thất bại';

  -- Đính ảnh bắt buộc cho mọi phiếu Nháp (S3: submit chặn nếu thiếu ảnh).
  -- SIM-99 có công-tơ-mét (mặc định) nên cần cả pump_meter + odometer.
  insert into pump_photos (ledger_id, kind, storage_path, created_by)
  select l.id, k.kind, l.id::text || '/' || k.kind || '.jpg', v_uid_a
  from ledger l cross join (values ('pump_meter'),('odometer')) k(kind)
  where l.created_by = v_uid_a and l.entry_type = 'bom' and l.status = 'Nhap'
    and not exists (select 1 from pump_photos p where p.ledger_id = l.id and p.kind = k.kind);

  -- === Submit ngày → ChoDoiChieu + cấp Số phiếu ===
  v_res := rpc_pump_submit_day();
  assert (v_res->>'count')::int = 2, '(1) submit phải chốt 2 phiếu';
  select status, code into v_status, v_code from ledger where id = v_id;
  assert v_status = 'ChoDoiChieu', '(1) sau submit phải ChoDoiChieu';
  assert v_code like 'BOM-%', '(1) phải có Số phiếu BOM-, có ' || coalesce(v_code,'NULL');

  -- === RutLai khi chưa đối chiếu ===
  perform rpc_pump_withdraw(v_id);
  select status into v_status from ledger where id = v_id;
  assert v_status = 'Nhap', '(2) rút lại phải về Nhap';
  -- Submit lại để đối chiếu tiếp (giữ nguyên Số phiếu cũ)
  perform rpc_pump_submit_day();
  assert (select code from ledger where id = v_id) = v_code, '(2) rút lại rồi submit phải giữ Số phiếu';

  -- === Chặn tự-duyệt: A không được duyệt phiếu của A ===
  begin
    perform rpc_pump_approve(v_id);
    assert false, '(3) A tự duyệt phiếu của mình lẽ ra phải lỗi';
  exception when others then
    assert sqlerrm like '%tự đối chiếu%' or sqlerrm like '%không có quyền%', '(3) sai thông báo: ' || sqlerrm;
  end;

  -- === Thủ kho B đối chiếu: Lệch → về Nhap kèm lý do ===
  perform set_config('request.jwt.claim.sub', v_uid_b::text, true);
  perform rpc_pump_reject(v_id, 'Ảnh mờ, số không khớp');
  select status, reject_reason into v_status, v_code from ledger where id = v_id;
  assert v_status = 'Nhap', '(4) Lệch phải về Nhap';
  assert v_code = 'Ảnh mờ, số không khớp', '(4) phải lưu lý do trả về';

  -- A sửa và submit lại; B duyệt Khớp → DaDuyet
  perform set_config('request.jwt.claim.sub', v_uid_a::text, true);
  perform rpc_pump_submit_day();
  perform set_config('request.jwt.claim.sub', v_uid_b::text, true);
  perform rpc_pump_approve(v_id);
  select status into v_status from ledger where id = v_id;
  assert v_status = 'DaDuyet', '(4) Khớp phải thành DaDuyet';

  -- === Chỉ DaDuyet tính vào tồn kho ===
  select count(*) into v_n from ledger where status = 'DaDuyet' and created_by = v_uid_a;
  assert v_n = 1, '(5) đúng 1 phiếu DaDuyet, có ' || v_n;
  select count(*) into v_n from ledger where status in ('Nhap','ChoDoiChieu') and created_by = v_uid_a;
  assert v_n = 1, '(5) phiếu thứ 2 vẫn ChoDoiChieu (chưa duyệt), có ' || v_n;

  raise notice 'PUMP FLOW SIMULATION: TẤT CẢ ASSERT PASS ✅';
end $$;

rollback;
