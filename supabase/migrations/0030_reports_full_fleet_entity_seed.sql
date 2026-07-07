-- ============================================================================
-- 0030_reports_full_fleet_entity_seed.sql
--   (1) Seed đơn vị Lâm Hải cho các xe theo khối "Công ty CP Lâm Hải Logistic"
--       trong sheet gốc TIEU HAO DIESEL_1 (các xe còn lại giữ Thiên Nhật).
--   (2) Cả 3 báo cáo liệt kê CÙNG một tập xe = mọi xe active (bỏ bộ lọc
--       "chỉ xe có phát sinh" vốn khiến mỗi báo cáo ra số lượng xe khác nhau).
-- Bám sát Excel gốc: TONG HOP & DIESEL_2 liệt kê toàn bộ xe; nay đồng nhất
-- cho cả DIESEL_1 (chi tiết) để "không hơn không kém".
-- Chỉ bút toán DaDuyet/legacy. Gated report:read. KHÔNG sửa migration cũ.
-- ============================================================================

-- (1) Phân đơn vị theo Excel gốc (biển số khối Lâm Hải).
update vehicles set entity = 'Lâm Hải'
  where plate in ('29E17410','29E17269','29E18160','29E17539','29E17273','29E17417','Xe 600148','Xe ben mới');

-- ----------------------------------------------------------------------------
-- (2) TỔNG HỢP TIÊU HAO — mọi xe active (bỏ bộ lọc phát sinh).
-- ----------------------------------------------------------------------------
create or replace function rpc_report_monthly(
  p_month int, p_year int, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_d0 date; v_from date; v_to date; v_prev date;
  v_tanks jsonb; v_oils jsonb; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);
  v_prev := (v_d0 - interval '1 month')::date;
  v_from := coalesce(p_from, v_d0);
  v_to := coalesce(p_to, (v_d0 + interval '1 month' - interval '1 day')::date);
  if v_from > v_to then raise exception 'Từ ngày phải trước hoặc bằng Đến ngày.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb)
    into v_tanks from tanks where active;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb)
    into v_oils from oil_types where active and normalize_text(name) not like 'do%';

  with cur as (select * from report_range_agg(v_from, v_to)),
  prv as (select * from report_month_agg(v_prev)),
  merged as (
    select v.id vehicle_id, v.plate, v.pump_norm, v.entity,
      c.tanks, c.bom_ngoai, c.other_oils, c.km, c.tinh_am, c.tinh_duong,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(c.tanks) e) + c.bom_ngoai) tong_diesel,
      (select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(c.other_oils) e) tong_oil_khac,
      p.km prev_km,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(p.tanks) e) + p.bom_ngoai
        + p.tinh_am - p.tinh_duong) prev_tieuhao
    from vehicles v
    left join cur c on c.vehicle_id = v.id
    left join prv p on p.vehicle_id = v.id
    where v.active
  ),
  final as (
    select m.*,
      (m.tong_diesel + m.tinh_am - m.tinh_duong) tieu_hao_thuc,
      case when m.km > 0 then round((m.tong_diesel + m.tinh_am - m.tinh_duong) / m.km * 100, 3) else null end l100,
      case when m.prev_km > 0 then round(m.prev_tieuhao / m.prev_km * 100, 3) else null end l100_prev
    from merged m
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'vehicleId', vehicle_id, 'plate', plate, 'pumpNorm', pump_norm, 'entity', entity,
      'tanks', tanks, 'bomNgoai', bom_ngoai, 'tongDiesel', tong_diesel,
      'otherOils', other_oils, 'tongOilKhac', tong_oil_khac,
      'km', km, 'tinhAm', tinh_am, 'tinhDuong', tinh_duong,
      'tieuHaoThuc', tieu_hao_thuc, 'lPer100', l100, 'lPer100Prev', l100_prev
    ) order by plate), '[]'::jsonb),
    jsonb_build_object(
      'bomNgoai', coalesce(sum(bom_ngoai),0), 'tongDiesel', coalesce(sum(tong_diesel),0),
      'tongOilKhac', coalesce(sum(tong_oil_khac),0), 'km', coalesce(sum(km),0),
      'tinhAm', coalesce(sum(tinh_am),0), 'tinhDuong', coalesce(sum(tinh_duong),0),
      'tieuHaoThuc', coalesce(sum(tieu_hao_thuc),0))
    into v_rows, v_tot
  from final;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'tanks', v_tanks, 'oils', v_oils, 'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

-- ----------------------------------------------------------------------------
-- DIESEL_2 — theo ngày, mọi xe active.
-- ----------------------------------------------------------------------------
create or replace function rpc_report_diesel_daily(
  p_month int, p_year int, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_d0 date; v_from date; v_to date; v_prev date; v_dim int; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);
  v_prev := (v_d0 - interval '1 month')::date;
  v_dim := extract(day from (v_d0 + interval '1 month' - interval '1 day'))::int;
  v_from := coalesce(p_from, v_d0);
  v_to := coalesce(p_to, (v_d0 + interval '1 month' - interval '1 day')::date);
  if v_from > v_to then raise exception 'Từ ngày phải trước hoặc bằng Đến ngày.'; end if;

  with led as (
    select l.vehicle_id, extract(day from l.entry_date)::int d, l.liters
    from ledger l join transaction_types tt on tt.id = l.txn_type_id
    where l.entry_type = 'bom' and tt.kind = 'xuat' and l.tank_id is not null
      and (l.status = 'DaDuyet' or l.legacy)
      and l.entry_date >= v_from and l.entry_date <= v_to
  ),
  daily as (
    select vehicle_id, jsonb_object_agg(d::text, s) days, sum(s) tot
    from (select vehicle_id, d, sum(liters) s from led group by vehicle_id, d) x
    group by vehicle_id
  ),
  cur as (select * from report_range_agg(v_from, v_to)),
  prv as (select * from report_month_agg(v_prev)),
  final as (
    select v.plate, v.entity,
      coalesce(dl.days, '{}'::jsonb) days,
      coalesce(dl.tot, 0) tong_xuat,
      coalesce(c.bom_ngoai,0) bom_ngoai, coalesce(c.tinh_am,0) tinh_am,
      coalesce(c.tinh_duong,0) tinh_duong, coalesce(c.km,0) km,
      (coalesce(dl.tot,0) + coalesce(c.bom_ngoai,0) + coalesce(c.tinh_am,0) - coalesce(c.tinh_duong,0)) tieu_hao_thuc,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(p.tanks) e)
        + coalesce(p.bom_ngoai,0) + coalesce(p.tinh_am,0) - coalesce(p.tinh_duong,0)) prev_th,
      coalesce(p.km,0) prev_km
    from vehicles v
    left join cur c on c.vehicle_id = v.id
    left join daily dl on dl.vehicle_id = v.id
    left join prv p on p.vehicle_id = v.id
    where v.active
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'plate', plate, 'entity', entity, 'days', days, 'tongXuat', tong_xuat, 'bomNgoai', bom_ngoai,
      'tinhAm', tinh_am, 'tinhDuong', tinh_duong, 'km', km, 'tieuHaoThuc', tieu_hao_thuc,
      'lPer100', case when km > 0 then round(tieu_hao_thuc / km * 100, 3) else null end,
      'lPerKm', case when km > 0 then round(tieu_hao_thuc / km, 4) else null end,
      'lPerKmPrev', case when prev_km > 0 then round(prev_th / prev_km, 4) else null end
    ) order by plate),'[]'::jsonb),
    jsonb_build_object('tongXuat', coalesce(sum(tong_xuat),0), 'bomNgoai', coalesce(sum(bom_ngoai),0),
      'tinhAm', coalesce(sum(tinh_am),0), 'tinhDuong', coalesce(sum(tinh_duong),0),
      'km', coalesce(sum(km),0), 'tieuHaoThuc', coalesce(sum(tieu_hao_thuc),0))
    into v_rows, v_tot
  from final;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'daysInMonth', v_dim, 'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

-- ----------------------------------------------------------------------------
-- DIESEL_1 — chi tiết theo định mức, mọi xe active.
-- ----------------------------------------------------------------------------
create or replace function rpc_report_diesel_detail(
  p_month int, p_year int, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_d0 date; v_from date; v_to date; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);
  v_from := coalesce(p_from, v_d0);
  v_to := coalesce(p_to, (v_d0 + interval '1 month' - interval '1 day')::date);
  if v_from > v_to then raise exception 'Từ ngày phải trước hoặc bằng Đến ngày.'; end if;

  with cur as (select * from report_range_agg(v_from, v_to)),
  final as (
    select v.plate, v.pump_norm, v.entity,
      (select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(coalesce(c.tanks,'{}'::jsonb)) e) diesel_tec,
      coalesce(c.bom_ngoai,0) bom_ngoai, coalesce(c.km,0) km, coalesce(c.tinh_am,0) tinh_am, coalesce(c.tinh_duong,0) tinh_duong,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(coalesce(c.tanks,'{}'::jsonb)) e) + coalesce(c.bom_ngoai,0)
        + coalesce(c.tinh_am,0) - coalesce(c.tinh_duong,0)) tieu_hao_thuc
    from vehicles v left join cur c on c.vehicle_id = v.id
    where v.active
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'plate', plate, 'entity', entity, 'dinhMuc', pump_norm, 'dieselTec', diesel_tec, 'bomNgoai', bom_ngoai,
      'tongDiesel', diesel_tec + bom_ngoai, 'km', km, 'tieuHaoThuc', tieu_hao_thuc,
      'lPer100', case when km > 0 then round(tieu_hao_thuc / km * 100, 3) else null end,
      'chenhLech', case when km > 0 and pump_norm > 0
        then round(tieu_hao_thuc / km * 100 - pump_norm, 3) else null end
    ) order by plate),'[]'::jsonb),
    jsonb_build_object('dieselTec', coalesce(sum(diesel_tec),0), 'bomNgoai', coalesce(sum(bom_ngoai),0),
      'tongDiesel', coalesce(sum(diesel_tec + bom_ngoai),0), 'km', coalesce(sum(km),0),
      'tieuHaoThuc', coalesce(sum(tieu_hao_thuc),0))
    into v_rows, v_tot
  from final;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

grant execute on function rpc_report_monthly(int, int, date, date) to authenticated;
grant execute on function rpc_report_diesel_daily(int, int, date, date) to authenticated;
grant execute on function rpc_report_diesel_detail(int, int, date, date) to authenticated;
