-- ============================================================================
-- qa_03_nhap_flow.sql — Vòng đời Phiếu nhập (S4 + Batch 3 duyệt-thẳng).
-- Nháp→Submit: CHẶN thiếu 1 trong 2 ảnh (Biên bản giao nhận + Phiếu nhập kho),
-- rồi DUYỆT THẲNG, cấp Số phiếu NHAP-YYYYMMDD-##. Số HĐ NCC ≠ Số phiếu.
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','qa_tka@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('11111111-1111-1111-1111-111111111111','qa_tka@test.local','QA ThuKho A','ThuKho','Hoạt động');
insert into oil_types (id,name) values ('a0000000-0000-0000-0000-000000000001','QA DO');
insert into tanks (id,name,oil_type_id,capacity_liters) values ('a0000000-0000-0000-0000-000000000002','QA Tec','a0000000-0000-0000-0000-000000000001',10000);
insert into suppliers (id,name) values ('a0000000-0000-0000-0000-000000000006','QA NCC');

do $$
declare
  v_a uuid := '11111111-1111-1111-1111-111111111111';
  v_oil uuid := 'a0000000-0000-0000-0000-000000000001';
  v_tank uuid := 'a0000000-0000-0000-0000-000000000002';
  v_sup uuid := 'a0000000-0000-0000-0000-000000000006';
  v jsonb; id1 uuid; v_status text; v_code text;
begin
  perform set_config('request.jwt.claim.sub', (v_a)::text, true);

  -- 1) Tạo phiếu nhập nháp (Số HĐ NCC = 'HD-777')
  v := rpc_nhap_create(v_sup, v_tank, v_oil, 5000, 21000, 'HD-777');  id1 := (v->>'id')::uuid;
  perform pg_temp.rec('Tạo Phiếu nhập Nháp',
    (select status from ledger where id=id1)='Nhap' and (select entry_type from ledger where id=id1)='nhap',
    'id='||id1);

  -- 2) Submit thiếu cả 2 ảnh → chặn (Biên bản giao nhận)
  begin
    perform rpc_nhap_submit_day();
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh Biên bản giao nhận', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh Biên bản giao nhận', sqlerrm like '%Biên bản%', sqlerrm);
  end;

  -- 3) Có Biên bản, thiếu Phiếu nhập kho → chặn
  perform rpc_nhap_photo_add(id1, 'bien_ban_giao_nhan', id1::text||'/bb.jpg');
  begin
    perform rpc_nhap_submit_day();
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh Phiếu nhập kho', false, 'KHÔNG chặn — sai');
  exception when others then
    perform pg_temp.rec('Chặn Submit khi thiếu ảnh Phiếu nhập kho', sqlerrm like '%Phiếu nhập kho%', sqlerrm);
  end;

  -- 4) Đủ 2 ảnh → Submit DUYỆT THẲNG + số phiếu theo ngày
  perform rpc_nhap_photo_add(id1, 'phieu_nhap_kho', id1::text||'/pnk.jpg');
  v := rpc_nhap_submit_day();
  select status, code into v_status, v_code from ledger where id=id1;
  perform pg_temp.rec('Submit → DUYỆT THẲNG (DaDuyet)', v_status='DaDuyet', 'status='||v_status);
  perform pg_temp.rec('Cấp Số phiếu theo ngày NHAP-YYYYMMDD-##',
    v_code like 'NHAP-'||to_char(current_date,'YYYYMMDD')||'-%', 'code='||coalesce(v_code,'null'));

  -- 5) Số HĐ NCC nhập tay, khác Số phiếu
  perform pg_temp.rec('Số HĐ NCC nhập tay ≠ Số phiếu',
    (select supplier_invoice_no from ledger where id=id1)='HD-777'
      and (select supplier_invoice_no from ledger where id=id1) <> coalesce(v_code,''),
    'HĐ NCC='||coalesce((select supplier_invoice_no from ledger where id=id1),'null'));

  -- 6) Phiếu nhập đã duyệt gắn đúng téc (để cộng tồn ở qa_04)
  perform pg_temp.rec('Phiếu nhập gắn Téc + đủ điều kiện cộng tồn',
    (select tank_id from ledger where id=id1)=v_tank, 'tank khớp');
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
