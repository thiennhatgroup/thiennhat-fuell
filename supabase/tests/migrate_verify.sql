-- ============================================================================
-- migrate_verify.sql — S9 đối soát sau khi chạy 0016_migrate_legacy.sql.
-- Chạy trong SQL Editor SAU khi deploy 0016 (KHÔNG rollback — chỉ đọc + RAISE).
-- Kiểm: (1) số dòng khớp, (2) tổng lít theo tháng/téc giữa Sổ cái và bảng nạp thô,
-- (3) tổng phân bổ tịnh = tịnh kỳ, (4) in tồn hiện tại từng téc để mắt-so với
-- Tồn thực tế của kỳ tịnh gần nhất. Dòng lệch được liệt kê để duyệt tay.
-- ============================================================================
do $$
declare
  v_ledger int; v_stage int; v_bad int; v_rec record; v_stock jsonb; v_row jsonb;
begin
  select count(*) into v_ledger from ledger where legacy;
  select count(*) into v_stage from _legacy_data_goc;
  raise notice 'Sổ cái legacy = % | bảng nạp thô = %', v_ledger, v_stage;
  assert v_ledger = v_stage, 'Số dòng Sổ cái legacy KHÁC bảng nạp thô!';

  -- (2) Tổng lít theo (tháng, nguồn, loại) — Sổ cái vs bảng thô. Log dòng lệch.
  v_bad := 0;
  for v_rec in
    with led as (
      select date_trunc('month', l.entry_date)::date m,
             coalesce(tk.name, '(không téc)') src, l.entry_type et, sum(l.liters) s
      from ledger l left join tanks tk on tk.id = l.tank_id
      where l.legacy group by 1,2,3
    ), stg as (
      select date_trunc('month', d.ngay)::date m,
             coalesce(d.tec_nguon, '(không téc)') src,
             case when d.loai='NHAP' then 'nhap' else 'bom' end et, sum(d.solit) s
      from _legacy_data_goc d group by 1,2,3
    )
    select coalesce(led.m,stg.m) m, coalesce(led.src,stg.src) src,
           coalesce(led.et,stg.et) et, coalesce(led.s,0) ls, coalesce(stg.s,0) sts
    from led full join stg on led.m=stg.m and led.src=stg.src and led.et=stg.et
    where round(coalesce(led.s,0),3) <> round(coalesce(stg.s,0),3)
  loop
    v_bad := v_bad + 1;
    raise notice 'LỆCH % % % : sổ cái=% thô=%', v_rec.m, v_rec.src, v_rec.et, v_rec.ls, v_rec.sts;
  end loop;
  assert v_bad = 0, format('Có %s tổ (tháng/nguồn/loại) lệch giữa Sổ cái và nguồn.', v_bad);

  -- (3) Tổng phân bổ tịnh = tịnh âm của kỳ (không lệch làm tròn).
  for v_rec in
    select sp.code, sp.tinh_am, coalesce(sum(a.tinh_am),0) alloc
    from stock_period sp left join stock_period_alloc a on a.period_id = sp.id
    where sp.status='DaChot' group by sp.code, sp.tinh_am
    having sp.tinh_am > 0 and round(coalesce(sum(a.tinh_am),0),2) <> round(sp.tinh_am,2)
  loop
    raise warning 'Kỳ % tịnh âm=% nhưng tổng phân bổ=% (lệch — có thể do kỳ không có xe bơm)',
      v_rec.code, v_rec.tinh_am, v_rec.alloc;
  end loop;

  -- (4) In tồn hiện tại từng téc (để mắt-so Tồn thực tế kỳ tịnh gần nhất).
  perform set_config('request.jwt.claim.sub',
    (select id::text from profiles where role='Admin' order by created_at limit 1), true);
  v_stock := rpc_inventory_stock();
  for v_row in select * from jsonb_array_elements(v_stock->'rows') loop
    raise notice 'TỒN % : đầu=% nhập=% xuất=% tịnhÂm=% → cuối=%',
      v_row->>'tankName', v_row->>'opening', v_row->>'nhap', v_row->>'xuat',
      v_row->>'tinhAm', v_row->>'closing';
  end loop;

  raise notice 'MIGRATE VERIFY: các assert bắt buộc PASS ✅ (mục 3/4 chỉ cảnh báo/để mắt).';
end $$;
