-- ============================================================================
-- 0022 — Batch 7: hai báo cáo tiêu hao còn lại (ngoài TONG HOP TIEU HAO ở S8).
--   • rpc_report_diesel_daily  ↔ sheet TIEU HAO DIESEL_2: lưới diesel xuất nội bộ
--       theo TỪNG NGÀY × xe + cột tổng tháng (giống AH..AP của sheet cũ).
--   • rpc_report_diesel_detail ↔ sheet TIEU HAO DIESEL_1: theo xe, kèm Định mức
--       (pump_norm) và chênh lệch L/100km thực tế − định mức (plan-vs-actual).
-- Dùng lại report_month_agg (S8) cho phần tổng tháng để nhất quán số học.
-- Chỉ bút toán DaDuyet/legacy. Gated report:read. KHÔNG sửa migration cũ.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DIESEL_2 — diesel xuất nội bộ theo ngày (1..số ngày trong tháng) cho từng xe.
-- ----------------------------------------------------------------------------
create or replace function rpc_report_diesel_daily(p_month int, p_year int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_d0 date; v_prev date; v_dim int; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);
  v_prev := (v_d0 - interval '1 month')::date;
  v_dim := extract(day from (v_d0 + interval '1 month' - interval '1 day'))::int;

  with led as (
    select l.vehicle_id, extract(day from l.entry_date)::int d, l.liters
    from ledger l join transaction_types tt on tt.id = l.txn_type_id
    where l.entry_type = 'bom' and tt.kind = 'xuat' and l.tank_id is not null
      and (l.status = 'DaDuyet' or l.legacy)
      and l.entry_date >= v_d0 and l.entry_date < (v_d0 + interval '1 month')
  ),
  daily as (
    select vehicle_id, jsonb_object_agg(d::text, s) days, sum(s) tot
    from (select vehicle_id, d, sum(liters) s from led group by vehicle_id, d) x
    group by vehicle_id
  ),
  cur as (select * from report_month_agg(v_d0)),
  prv as (select * from report_month_agg(v_prev)),
  final as (
    select v.plate,
      coalesce(dl.days, '{}'::jsonb) days,
      coalesce(dl.tot, 0) tong_xuat,
      c.bom_ngoai, c.tinh_am, c.tinh_duong, c.km,
      (coalesce(dl.tot,0) + c.bom_ngoai + c.tinh_am - c.tinh_duong) tieu_hao_thuc,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(p.tanks) e)
        + coalesce(p.bom_ngoai,0) + coalesce(p.tinh_am,0) - coalesce(p.tinh_duong,0)) prev_th,
      coalesce(p.km,0) prev_km
    from vehicles v
    join cur c on c.vehicle_id = v.id
    left join daily dl on dl.vehicle_id = v.id
    left join prv p on p.vehicle_id = v.id
    where v.active
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'plate', plate, 'days', days, 'tongXuat', tong_xuat, 'bomNgoai', bom_ngoai,
      'tinhAm', tinh_am, 'tinhDuong', tinh_duong, 'km', km, 'tieuHaoThuc', tieu_hao_thuc,
      'lPer100', case when km > 0 then round(tieu_hao_thuc / km * 100, 3) else null end,
      'lPerKm', case when km > 0 then round(tieu_hao_thuc / km, 4) else null end,
      'lPerKmPrev', case when prev_km > 0 then round(prev_th / prev_km, 4) else null end
    ) order by plate),'[]'::jsonb),
    jsonb_build_object('tongXuat', coalesce(sum(tong_xuat),0), 'bomNgoai', coalesce(sum(bom_ngoai),0),
      'tinhAm', coalesce(sum(tinh_am),0), 'tinhDuong', coalesce(sum(tinh_duong),0),
      'km', coalesce(sum(km),0), 'tieuHaoThuc', coalesce(sum(tieu_hao_thuc),0))
    into v_rows, v_tot
  from final
  where tong_xuat <> 0 or bom_ngoai <> 0 or km <> 0 or tinh_am <> 0 or tinh_duong <> 0;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'daysInMonth', v_dim, 'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

-- ----------------------------------------------------------------------------
-- DIESEL_1 — theo xe: Định mức (pump_norm) vs thực tế L/100km (plan-vs-actual).
-- ----------------------------------------------------------------------------
create or replace function rpc_report_diesel_detail(p_month int, p_year int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_d0 date; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);

  with cur as (select * from report_month_agg(v_d0)),
  final as (
    select v.plate, v.pump_norm,
      (select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(c.tanks) e) diesel_tec,
      c.bom_ngoai, c.km, c.tinh_am, c.tinh_duong,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(c.tanks) e) + c.bom_ngoai
        + c.tinh_am - c.tinh_duong) tieu_hao_thuc
    from vehicles v join cur c on c.vehicle_id = v.id
    where v.active
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'plate', plate, 'dinhMuc', pump_norm, 'dieselTec', diesel_tec, 'bomNgoai', bom_ngoai,
      'tongDiesel', diesel_tec + bom_ngoai, 'km', km, 'tieuHaoThuc', tieu_hao_thuc,
      'lPer100', case when km > 0 then round(tieu_hao_thuc / km * 100, 3) else null end,
      'chenhLech', case when km > 0 and pump_norm > 0
        then round(tieu_hao_thuc / km * 100 - pump_norm, 3) else null end
    ) order by plate),'[]'::jsonb),
    jsonb_build_object('dieselTec', coalesce(sum(diesel_tec),0), 'bomNgoai', coalesce(sum(bom_ngoai),0),
      'tongDiesel', coalesce(sum(diesel_tec + bom_ngoai),0), 'km', coalesce(sum(km),0),
      'tieuHaoThuc', coalesce(sum(tieu_hao_thuc),0))
    into v_rows, v_tot
  from final
  where diesel_tec <> 0 or bom_ngoai <> 0 or km <> 0;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

grant execute on function rpc_report_diesel_daily(int, int) to authenticated;
grant execute on function rpc_report_diesel_detail(int, int) to authenticated;
