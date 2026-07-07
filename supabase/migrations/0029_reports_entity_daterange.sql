-- ============================================================================
-- 0029_reports_entity_daterange.sql — Báo cáo: tách đơn vị (entity) + khoảng ngày.
--   • Thêm report_range_agg(p_from, p_to): bản khoảng ngày của report_month_agg.
--   • Override 3 RPC báo cáo: thêm p_from/p_to (mặc định = cả tháng) và trả 'entity'
--     theo từng dòng để frontend tách 2 bảng (Thiên Nhật / Lâm Hải).
--   • Cột so sánh "tháng trước" vẫn tính theo NGUYÊN tháng đang chọn (report_month_agg).
-- Chỉ bút toán DaDuyet/legacy. Gated report:read. KHÔNG sửa migration cũ.
-- ============================================================================

-- Gộp số liệu tiêu hao theo xe trong KHOẢNG NGÀY [p_from, p_to] (bao gồm 2 đầu).
create or replace function report_range_agg(p_from date, p_to date)
returns table (
  vehicle_id uuid, tanks jsonb, bom_ngoai numeric, other_oils jsonb,
  km numeric, tinh_am numeric, tinh_duong numeric
) language sql stable set search_path = public, pg_temp as $$
  with bnd as (select p_from d0, p_to d1),
  led as (
    select l.vehicle_id, l.tank_id, l.oil_type_id, tt.kind, l.liters, l.km_run
    from ledger l join transaction_types tt on tt.id = l.txn_type_id
    join bnd on l.entry_date >= bnd.d0 and l.entry_date <= bnd.d1
    where l.entry_type = 'bom' and (l.status = 'DaDuyet' or l.legacy)
  )
  select v.id,
    coalesce((select jsonb_object_agg(x.tank_id, x.s) from (
      select led.tank_id, sum(led.liters) s from led
      where led.vehicle_id = v.id and led.kind = 'xuat' and led.tank_id is not null
      group by led.tank_id) x), '{}'::jsonb),
    coalesce((select sum(led.liters) from led
      where led.vehicle_id = v.id and led.kind = 'bom_ngoai'), 0),
    coalesce((select jsonb_object_agg(x.oil_type_id, x.s) from (
      select led.oil_type_id, sum(led.liters) s from led
      where led.vehicle_id = v.id and led.kind = 'xuat' and led.tank_id is null
        and led.oil_type_id is not null
      group by led.oil_type_id) x), '{}'::jsonb),
    coalesce((select sum(led.km_run) from led
      where led.vehicle_id = v.id and led.km_run is not null), 0),
    coalesce((select sum(a.tinh_am) from stock_period_alloc a
      join stock_period sp on sp.id = a.period_id
      join bnd on sp.close_date >= bnd.d0 and sp.close_date <= bnd.d1
      where a.vehicle_id = v.id and sp.status = 'DaChot'), 0),
    coalesce((select sum(a.tinh_duong) from stock_period_alloc a
      join stock_period sp on sp.id = a.period_id
      join bnd on sp.close_date >= bnd.d0 and sp.close_date <= bnd.d1
      where a.vehicle_id = v.id and sp.status = 'DaChot'), 0)
  from vehicles v;
$$;

-- Bỏ chữ ký cũ (chỉ month/year) để tránh nhập nhằng overload.
drop function if exists rpc_report_monthly(int, int);
drop function if exists rpc_report_diesel_daily(int, int);
drop function if exists rpc_report_diesel_detail(int, int);

-- ----------------------------------------------------------------------------
-- TỔNG HỢP TIÊU HAO — theo xe (téc + dầu phụ), tách theo entity, khoảng ngày.
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
    join cur c on c.vehicle_id = v.id
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
  from final
  where tong_diesel <> 0 or tong_oil_khac <> 0 or km <> 0 or tinh_am <> 0 or tinh_duong <> 0;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'tanks', v_tanks, 'oils', v_oils, 'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

-- ----------------------------------------------------------------------------
-- DIESEL_2 — diesel xuất nội bộ theo ngày × xe (lưới theo tháng), lọc khoảng ngày.
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
  from final
  where tong_xuat <> 0 or bom_ngoai <> 0 or km <> 0 or tinh_am <> 0 or tinh_duong <> 0;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'daysInMonth', v_dim, 'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

-- ----------------------------------------------------------------------------
-- DIESEL_1 — theo xe: Định mức (pump_norm) vs thực tế L/100km, tách entity.
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
      (select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(c.tanks) e) diesel_tec,
      c.bom_ngoai, c.km, c.tinh_am, c.tinh_duong,
      ((select coalesce(sum((e.value)::numeric),0) from jsonb_each_text(c.tanks) e) + c.bom_ngoai
        + c.tinh_am - c.tinh_duong) tieu_hao_thuc
    from vehicles v join cur c on c.vehicle_id = v.id
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
  from final
  where diesel_tec <> 0 or bom_ngoai <> 0 or km <> 0;

  return jsonb_build_object('ok', true, 'month', p_month, 'year', p_year,
    'from', to_char(v_from,'YYYY-MM-DD'), 'to', to_char(v_to,'YYYY-MM-DD'),
    'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

grant execute on function rpc_report_monthly(int, int, date, date) to authenticated;
grant execute on function rpc_report_diesel_daily(int, int, date, date) to authenticated;
grant execute on function rpc_report_diesel_detail(int, int, date, date) to authenticated;
