-- ============================================================================
-- nhap_flow_simulation.sql — S4 kiểm thử Phiếu nhập (NHAP): vòng đời + ảnh +
-- đối chiếu chéo. Giả lập auth.uid() qua request.jwt.claim.sub. BEGIN...ROLLBACK,
-- không để lại dữ liệu. Sandbox không có DB → chạy trong Supabase SQL Editor sau
-- deploy 0010.
--
-- Khẳng định:
--   1. Validate: thiếu NCC/téc/loại dầu/lít≤0/đơn giá≤0 → lỗi.
--   2. Tạo phiếu nhập Nháp; sửa được khi Nháp.
--   3. Submit chặn khi thiếu ảnh phiếu nhập ('receipt').
--   4. rpc_nhap_photo_add từ chối path không thuộc phiếu.
--   5. Có ≥1 ảnh → submit thành công, cấp Số phiếu NHAP-YYYY-######.
--   6. Không tự đối chiếu phiếu do mình tạo.
--   7. Người KHÁC Khớp → DaDuyet.
--   8. Lệch → về Nhap + reject_reason; rồi submit lại được.
-- ============================================================================
begin;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000','44444444-4444-4444-4444-444444444444','authenticated','authenticated','sim_n1@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}'),
  ('00000000-0000-0000-0000-000000000000','55555555-5555-5555-5555-555555555555','authenticated','authenticated','sim_n2@test.local', crypt('tn-pin::0000', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}', '{}');
insert into profiles (id, email, name, role, status) values
  ('44444444-4444-4444-4444-444444444444','sim_n1@test.local','Thủ kho N1','ThuKho','Hoạt động'),
  ('55555555-5555-5555-5555-555555555555','sim_n2@test.local','Thủ kho N2','ThuKho','Hoạt động');

insert into oil_types (id, name) values ('cccccccc-0000-0000-0000-000000000001','SIM DO N');
insert into suppliers (id, name) values ('cccccccc-0000-0000-0000-000000000002','SIM NCC N');
insert into tanks (id, name, oil_type_id, capacity_liters) values
  ('cccccccc-0000-0000-0000-000000000003','SIM Téc N','cccccccc-0000-0000-0000-000000000001', 20000);

do $$
declare
  v_u1 uuid := '44444444-4444-4444-4444-444444444444';  -- người nhập
  v_u2 uuid := '55555555-5555-5555-5555-555555555555';  -- người đối chiếu
  v_oil uuid := 'cccccccc-0000-0000-0000-000000000001';
  v_sup uuid := 'cccccccc-0000-0000-0000-000000000002';
  v_tank uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_id uuid; v_res jsonb; v_status text; v_code text;
begin
  perform set_config('request.jwt.claim.sub', v_u1::text, true);

  -- (1) Validate.
  begin
    perform rpc_nhap_create(null, v_tank, v_oil, 1000, 20000);
    assert false, '(1a) thiếu NCC lẽ ra phải lỗi';
  exception when others then assert sqlerrm like '%nhà cung cấp%', '(1a) sai: ' || sqlerrm; end;
  begin
    perform rpc_nhap_create(v_sup, v_tank, v_oil, 0, 20000);
    assert false, '(1b) lít<=0 lẽ ra phải lỗi';
  exception when others then assert sqlerrm like '%Số lít%', '(1b) sai: ' || sqlerrm; end;
  begin
    perform rpc_nhap_create(v_sup, v_tank, v_oil, 1000, 0);
    assert false, '(1c) đơn giá<=0 lẽ ra phải lỗi';
  exception when others then assert sqlerrm like '%Đơn giá%', '(1c) sai: ' || sqlerrm; end;

  -- (2) Tạo + sửa.
  v_res := rpc_nhap_create(v_sup, v_tank, v_oil, 1000, 20000, 'HD-2026-001');
  v_id := (v_res->>'id')::uuid;
  assert (select entry_type from ledger where id = v_id) = 'nhap', '(2) entry_type phải là nhap';
  perform rpc_nhap_update(v_id, v_sup, v_tank, v_oil, 1200, 21000, 'HD-2026-001b');
  assert (select liters from ledger where id = v_id) = 1200, '(2) sửa số lít thất bại';

  -- (3) Submit chặn khi thiếu ảnh.
  begin
    perform rpc_nhap_submit_day();
    assert false, '(3) submit thiếu ảnh lẽ ra phải lỗi';
  exception when others then assert sqlerrm like '%ảnh phiếu nhập%', '(3) sai: ' || sqlerrm; end;

  -- (4) path lạ → từ chối.
  begin
    perform rpc_nhap_photo_add(v_id, 'khac/anh.jpg');
    assert false, '(4) path lạ lẽ ra phải lỗi';
  exception when others then assert sqlerrm like '%không thuộc phiếu%', '(4) sai: ' || sqlerrm; end;

  -- (5) Đính ảnh đúng path → submit thành công, cấp số.
  perform rpc_nhap_photo_add(v_id, v_id::text || '/receipt.jpg');
  v_res := rpc_nhap_submit_day();
  select status, code into v_status, v_code from ledger where id = v_id;
  assert v_status = 'ChoDoiChieu', '(5) đủ ảnh phải submit được, status=' || v_status;
  assert v_code like 'NHAP-%', '(5) phải cấp Số phiếu NHAP, code=' || coalesce(v_code,'null');

  -- (6) Không tự đối chiếu.
  begin
    perform rpc_nhap_approve(v_id);
    assert false, '(6) tự đối chiếu lẽ ra phải lỗi';
  exception when others then assert sqlerrm like '%tự đối chiếu%', '(6) sai: ' || sqlerrm; end;

  -- (8) Người khác Lệch → về Nhap + lý do.
  perform set_config('request.jwt.claim.sub', v_u2::text, true);
  perform rpc_nhap_reject(v_id, 'Số lít trên hóa đơn khác');
  select status, reject_reason into v_status, v_code from ledger where id = v_id;
  assert v_status = 'Nhap', '(8) Lệch phải về Nhap, status=' || v_status;
  assert v_code = 'Số lít trên hóa đơn khác', '(8) thiếu reject_reason';

  -- Người nhập submit lại (ảnh vẫn còn), rồi người khác Khớp → DaDuyet.
  perform set_config('request.jwt.claim.sub', v_u1::text, true);
  perform rpc_nhap_submit_day();
  perform set_config('request.jwt.claim.sub', v_u2::text, true);
  perform rpc_nhap_approve(v_id);
  select status into v_status from ledger where id = v_id;
  assert v_status = 'DaDuyet', '(7) Khớp phải thành DaDuyet, status=' || v_status;

  raise notice 'NHAP FLOW SIMULATION: TẤT CẢ ASSERT PASS ✅';
end $$;

rollback;
