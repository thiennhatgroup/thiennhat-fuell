-- ============================================================================
-- 0031_report_diesel_detail_fix.sql — Sửa báo cáo "Diesel chi tiết" cho đúng
-- bản chất sheet gốc TIEU HAO DIESEL_1:
--   • "Định mức" thật ra là ĐỊNH MỨC BƠM BOM (pump_norm = _DM_BOM_BOM), KHÔNG
--     phải L/100km. Bỏ cột "Chênh lệch L/100km − định mức" (vô nghĩa).
--   • Tỷ lệ tiêu hao là L/km = (bơm đầu xe = diesel xuất nội bộ từ téc) ÷ (km
--     theo phiếu bơm), KHÔNG nhân 100. Kèm L/km tháng trước và thay đổi.
--   • Tiêu hao thực (cột E) = tổng diesel + tịnh âm − tịnh dương.
--   • Liệt kê mọi xe active, tách theo entity, hỗ trợ khoảng ngày (như 0030).
-- Chỉ bút toán DaDuyet/legacy. Gated report:read. KHÔNG sửa migration cũ.
-- ============================================================================

create or replace function rpc_report_diesel_detail(
  p_month int, p_year int, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_d0 date; v_from date; v_to date; v_prev date; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);
  v_prev := (v_d0 - interval '1 month')::date;
  v_from := coalesce(p_from, v_d0);
  v_to := coalesce(p_to, (v_d0 + interval '1 month' - interval '1 day')::date);
  if v_from > v_to then raise exception 'Từ ngày phải trước hoặc bằng Đến ngày.'; end if;

  with cur as (select * from report_range_agg(v_from, v_to)),
  prv as (select * from report_month_agg(v_prev)),
  base as (
    select v.plate, v.pump_norm, v.entity,
      -- Diesel xuất nội bộ từ téc cho xe (≈ cột O "Bơm đầu xe" của sheet gốc).
      (select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(coalesce(c.tanks,'{}'::jsonb)) e) diesel_tec,
      coalesce(c.bom_ngoai,0) bom_ngoai, coalesce(c.km,0) km,
      coalesce(c.tinh_am,0) tinh_am, coalesce(c.tinh_duong,0) tinh_duong,
      -- KM theo phiếu bơm tháng trước & diesel téc tháng trước (để tính L/km tháng trước).
      coalesce(p.km,0) prev_km,
      (select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(coalesce(p.tanks,'{}'::jsonb)) e) prev_diesel_tec
    from vehicles v
    left join cur c on c.vehicle_id = v.id
    left join prv p on p.vehicle_id = v.id
    where v.active
  ),
  final as (
    select b.*,
      (b.diesel_tec + b.bom_ngoai) tong_diesel,
      -- Tiêu hao thực (cột E) = tổng diesel + tịnh âm − tịnh dương.
      (b.diesel_tec + b.bom_ngoai + b.tinh_am - b.tinh_duong) tieu_hao_thuc,
      case when b.km > 0 then round(b.diesel_tec / b.km, 4) else null end l_per_km,
      case when b.prev_km > 0 then round(b.prev_diesel_tec / b.prev_km, 4) else null end l_per_km_prev
    from base b
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'plate', plate, 'entity', entity,
      'dinhMucBom', pump_norm,                 -- Định mức bơm bom
      'dieselTec', diesel_tec, 'bomNgoai', bom_ngoai, 'tongDiesel', tong_diesel,
      'km', km, 'tieuHaoThuc', tieu_hao_thuc,
      'lPerKm', l_per_km, 'lPerKmPrev', l_per_km_prev,
      'thayDoiLPerKm', case when l_per_km is not null and l_per_km_prev is not null
        then round(l_per_km - l_per_km_prev, 4) else null end
    ) order by plate),'[]'::jsonb),
    jsonb_build_object('dieselTec', coalesce(sum(diesel_tec),0), 'bomNgoai', coalesce(sum(bom_ngoai),0),
      'tongDiesel', coalesce(sum(tong_diesel),0), 'km', coalesce(sum(km),0),
      'tieuHaoThuc', coalesce(sum(tieu_hao_thuc),0))
    into v_rows, v_tot
  from final;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

grant execute on function rpc_report_diesel_detail(int, int, date, date) to authenticated;
