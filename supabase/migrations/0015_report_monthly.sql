-- ============================================================================
-- 0015_report_monthly.sql — S8 Báo cáo tiêu hao tháng (tái hiện sheet cũ).
-- Tái hiện logic SUMIFS của TONG HOP TIEU HAO / TIEU HAO DIESEL của file gốc:
--   • Diesel theo TÉC   = Σ lít BOM 'xuat' từ téc vật lý trong tháng, theo xe.
--   • Bơm ngoài         = Σ lít BOM kind 'bom_ngoai' trong tháng, theo xe.
--   • Tổng diesel       = Σ(téc) + bơm ngoài.
--   • Dầu khác (động cơ/thủy lực/cầu/số) = Σ lít BOM 'xuat' không gắn téc, theo loại dầu.
--   • KM                = Σ km_run (KM đi) của phiếu BOM trong tháng, theo xe.
--   • Tịnh (phân bổ)    = Σ phân bổ tịnh âm/dương cho xe của các KỲ CHỐT trong tháng.
--   • Tiêu hao thực     = Tổng diesel + tịnh âm − tịnh dương.
--   • L/100km           = Tiêu hao thực / KM × 100 (khi KM > 0). Kèm L/100km tháng trước.
-- Chỉ bút toán DaDuyet hoặc legacy. Gated report:read (KeToan/Admin). Read-only.
-- KHÔNG sửa migration cũ.
-- ============================================================================

-- Gộp số liệu tiêu hao của MỘT tháng theo xe (dùng lại cho tháng này & tháng trước).
create or replace function report_month_agg(p_d0 date)
returns table (
  vehicle_id uuid, tanks jsonb, bom_ngoai numeric, other_oils jsonb,
  km numeric, tinh_am numeric, tinh_duong numeric
) language sql stable set search_path = public, pg_temp as $$
  with bnd as (select p_d0 d0, (p_d0 + interval '1 month')::date d1),
  led as (
    select l.vehicle_id, l.tank_id, l.oil_type_id, tt.kind, l.liters, l.km_run
    from ledger l join transaction_types tt on tt.id = l.txn_type_id
    join bnd on l.entry_date >= bnd.d0 and l.entry_date < bnd.d1
    where l.entry_type = 'bom' and (l.status = 'DaDuyet' or l.legacy)
  )
  select v.id,
    -- diesel theo téc: {tankId: lít}
    coalesce((select jsonb_object_agg(x.tank_id, x.s) from (
      select led.tank_id, sum(led.liters) s from led
      where led.vehicle_id = v.id and led.kind = 'xuat' and led.tank_id is not null
      group by led.tank_id) x), '{}'::jsonb),
    coalesce((select sum(led.liters) from led
      where led.vehicle_id = v.id and led.kind = 'bom_ngoai'), 0),
    -- dầu khác: {oilTypeId: lít} (xuất không gắn téc, tức dầu phụ)
    coalesce((select jsonb_object_agg(x.oil_type_id, x.s) from (
      select led.oil_type_id, sum(led.liters) s from led
      where led.vehicle_id = v.id and led.kind = 'xuat' and led.tank_id is null
        and led.oil_type_id is not null
      group by led.oil_type_id) x), '{}'::jsonb),
    coalesce((select sum(led.km_run) from led
      where led.vehicle_id = v.id and led.km_run is not null), 0),
    coalesce((select sum(a.tinh_am) from stock_period_alloc a
      join stock_period sp on sp.id = a.period_id
      join bnd on sp.close_date >= bnd.d0 and sp.close_date < bnd.d1
      where a.vehicle_id = v.id and sp.status = 'DaChot'), 0),
    coalesce((select sum(a.tinh_duong) from stock_period_alloc a
      join stock_period sp on sp.id = a.period_id
      join bnd on sp.close_date >= bnd.d0 and sp.close_date < bnd.d1
      where a.vehicle_id = v.id and sp.status = 'DaChot'), 0)
  from vehicles v;
$$;

-- Báo cáo tháng: trả cột (téc active + dầu phụ) + dòng theo xe + tổng.
create or replace function rpc_report_monthly(p_month int, p_year int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_d0 date; v_prev date; v_tanks jsonb; v_oils jsonb; v_rows jsonb; v_tot jsonb;
begin
  perform require_permission('report:read');
  if p_month is null or p_month < 1 or p_month > 12 then raise exception 'Tháng không hợp lệ.'; end if;
  if p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'Năm không hợp lệ.'; end if;
  v_d0 := make_date(p_year, p_month, 1);
  v_prev := (v_d0 - interval '1 month')::date;

  -- Cột téc (téc vật lý đang hoạt động).
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb)
    into v_tanks from tanks where active;
  -- Cột dầu phụ (loại dầu không phải diesel chính).
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb)
    into v_oils from oil_types where active and normalize_text(name) not like 'do%';

  with cur as (select * from report_month_agg(v_d0)),
  prv as (select * from report_month_agg(v_prev)),
  merged as (
    select v.id vehicle_id, v.plate, v.pump_norm,
      c.tanks, c.bom_ngoai, c.other_oils, c.km, c.tinh_am, c.tinh_duong,
      -- tổng diesel = Σ téc + bơm ngoài
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
      'vehicleId', vehicle_id, 'plate', plate, 'pumpNorm', pump_norm,
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
    'tanks', v_tanks, 'oils', v_oils, 'rows', coalesce(v_rows,'[]'::jsonb), 'totals', v_tot);
end;
$$;

grant execute on function rpc_report_monthly(int, int) to authenticated;
