-- ============================================================================
-- qa_09_reconcile_report_REAL.sql — ĐỐI SOÁT báo cáo tháng vs Excel v11.
-- CHẠY TRÊN DỮ LIỆU THẬT (1.738 dòng legacy). Chỉ ĐỌC: tạo 1 Admin tạm để gọi
-- rpc_report_monthly rồi so tổng với số cộng tay từ sheet DATA_GOC. begin…rollback
-- ⇒ KHÔNG ghi gì vào DB thật (Admin tạm cũng bị rollback).
--
-- Số kỳ vọng (cộng tay từ DATA_GOC, đơn vị lít):
--   Tháng | tongDiesel (=xuất nội bộ diesel + bơm ngoài) | bomNgoai | tongOilKhac(dầu phụ)
--   2026-01 |  72069.00  |  2350.00 |  422.00
--   2026-04 |  75431.52  |  7534.52 |  521.00
--   2026-06 |  74680.60  |  2004.60 |  528.00
--
-- LƯU Ý: FAIL có thể là PHÁT HIỆN THẬT — xe bị Ngừng (active=false) bị loại khỏi
-- báo cáo, hoặc dòng migrate lệch téc. Cột Chi tiết in kỳ vọng vs thực tế để dò.
-- ============================================================================
begin;
create temp table _t (n serial primary key, name text, pass boolean, note text) on commit drop;
create or replace function pg_temp.rec(p_name text, p_pass boolean, p_note text default null)
returns void language sql as $fn$ insert into pg_temp._t(name,pass,note) values(p_name,p_pass,p_note); $fn$;

-- Admin tạm (chỉ để có report:read; rollback sẽ xóa).
insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','59999999-9999-9999-9999-999999999999','authenticated','authenticated','qa_recon_admin@test.local','x',now(),now(),now(),'{"provider":"email"}','{}');
insert into profiles (id,email,name,role,status) values
 ('59999999-9999-9999-9999-999999999999','qa_recon_admin@test.local','QA Recon Admin','Admin','Hoạt động');

do $$
declare
  v_ad uuid := '59999999-9999-9999-9999-999999999999';
  v jsonb; t jsonb; v_sum_rows numeric;
  -- (tháng, năm, kv_tongDiesel, kv_bomNgoai, kv_oilKhac)
  months numeric[][] := array[
    [1, 2026, 72069.00, 2350.00, 422.00],
    [4, 2026, 75431.52, 7534.52, 521.00],
    [6, 2026, 74680.60, 2004.60, 528.00]
  ];
  i int; m int; y int; kd numeric; kb numeric; ko numeric;
  ad numeric; ab numeric; ao numeric;
begin
  perform set_config('request.jwt.claim.sub', (v_ad)::text, true);

  for i in 1 .. array_length(months,1) loop
    m := months[i][1]::int; y := months[i][2]::int;
    kd := months[i][3]; kb := months[i][4]; ko := months[i][5];
    v := rpc_report_monthly(m, y);
    t := v->'totals';
    ad := round((t->>'tongDiesel')::numeric, 2);
    ab := round((t->>'bomNgoai')::numeric, 2);
    ao := round((t->>'tongOilKhac')::numeric, 2);

    perform pg_temp.rec(
      format('T%s/%s — Tổng diesel (kv %s)', m, y, kd),
      ad = kd, format('thực tế=%s | lệch=%s', ad, ad-kd));
    perform pg_temp.rec(
      format('T%s/%s — Bơm ngoài (kv %s)', m, y, kb),
      ab = kb, format('thực tế=%s | lệch=%s', ab, ab-kb));
    perform pg_temp.rec(
      format('T%s/%s — Dầu phụ (kv %s)', m, y, ko),
      ao = ko, format('thực tế=%s | lệch=%s', ao, ao-ko));

    -- Nhất quán nội bộ: Σ tongDiesel theo dòng xe = totals.tongDiesel
    select coalesce(sum((e.value->>'tongDiesel')::numeric),0) into v_sum_rows
      from jsonb_array_elements(v->'rows') e(value);
    perform pg_temp.rec(
      format('T%s/%s — Σ dòng xe = tổng (nhất quán RPC)', m, y),
      round(v_sum_rows,2) = ad, format('Σdòng=%s vs tổng=%s', round(v_sum_rows,2), ad));
  end loop;
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
    (case when (select bool_and(pass) from pg_temp._t) then 'ALL PASS - Báo cáo khớp Excel' else '*** CÓ LỆCH — xem cột Chi tiết ***' end) kq,
    ('TỔNG '||(select count(*) filter(where pass) from pg_temp._t)||'/'||(select count(*) from pg_temp._t)||' PASS') test, '' note
  union all
  select n, case when pass then 'PASS' else 'FAIL' end, name, coalesce(note,'') from pg_temp._t
) z order by n;
rollback;
