-- ============================================================================
-- 0027_stock_period_allocate_helper.sql — Batch 9 follow-up (code review, candidate 2)
-- Gom TOÁN HỌC phân bổ tịnh âm/dương cho xe về MỘT chỗ. Trước đây khối "tổng lít
-- xe bơm" + vòng lặp "phân bổ theo tỉ lệ lít" + "dồn dư làm tròn vào xe lớn nhất"
-- bị copy-paste giữa rpc_stock_period_close (0012) và rpc_stock_period_record (0025/0026)
-- → sửa quy tắc phân bổ phải đụng 2 hàm (shotgun surgery). Tách 2 helper nội bộ:
--   • stock_period_pump_total(tank,start,close) — tổng lít xe bơm (xuất) trong kỳ.
--   • stock_period_allocate(period,tank,start,close,am,duong,total) — phân bổ cho xe.
-- Logic BÊN TRONG helper CHÉP NGUYÊN VĂN từ bản cũ, chỉ đổi tên biến v_* → tham số.
-- Hai RPC được create-or-replace để gọi helper (giữ nguyên guard biên-bản của 0026).
-- Helper là nội bộ (SECURITY DEFINER, KHÔNG grant cho authenticated) như các helper
-- khác (tank_book_before, next_code_year).
-- ============================================================================

-- Tổng lít xe bơm (xuất) từ téc trong kỳ. (Chép nguyên văn truy vấn v_total cũ.)
create or replace function stock_period_pump_total(p_tank_id uuid, p_start date, p_close date)
returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(l.liters), 0) from ledger l
    join transaction_types tt on tt.id = l.txn_type_id
    where l.tank_id = p_tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
      and l.vehicle_id is not null and (l.status = 'DaDuyet' or l.legacy)
      and l.entry_date between p_start and p_close;
$$;

-- Phân bổ tịnh âm/dương cho xe theo tỉ lệ lít bơm trong kỳ; dồn phần dư làm tròn vào
-- xe lít lớn nhất để tổng khớp tuyệt đối. (Chép nguyên văn vòng lặp phân bổ cũ.)
create or replace function stock_period_allocate(
  p_period_id uuid, p_tank_id uuid, p_start date, p_close date,
  p_am numeric, p_duong numeric, p_total numeric
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_rec record; v_sum_am numeric := 0; v_sum_duong numeric := 0; v_max_veh uuid; v_a numeric; v_d numeric;
begin
  if p_total > 0 and (p_am > 0 or p_duong > 0) then
    for v_rec in
      select l.vehicle_id, sum(l.liters) as lit from ledger l
        join transaction_types tt on tt.id = l.txn_type_id
        where l.tank_id = p_tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
          and l.vehicle_id is not null and (l.status = 'DaDuyet' or l.legacy)
          and l.entry_date between p_start and p_close
        group by l.vehicle_id
        order by sum(l.liters) desc
    loop
      if v_max_veh is null then v_max_veh := v_rec.vehicle_id; end if;
      v_a := round(p_am * v_rec.lit / p_total, 2);
      v_d := round(p_duong * v_rec.lit / p_total, 2);
      insert into stock_period_alloc (period_id, vehicle_id, liters_in_period, tinh_am, tinh_duong)
      values (p_period_id, v_rec.vehicle_id, v_rec.lit, v_a, v_d);
      v_sum_am := v_sum_am + v_a; v_sum_duong := v_sum_duong + v_d;
    end loop;
    if v_max_veh is not null then
      update stock_period_alloc
        set tinh_am = tinh_am + (p_am - v_sum_am), tinh_duong = tinh_duong + (p_duong - v_sum_duong)
        where period_id = p_period_id and vehicle_id = v_max_veh;
    end if;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_stock_period_close — dùng helper (loại bỏ vòng lặp phân bổ trùng lặp).
-- ----------------------------------------------------------------------------
create or replace function rpc_stock_period_close(
  p_id uuid, p_actual_liters numeric, p_close_date date default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_actor profiles; v_cur stock_period; v_close date := coalesce(p_close_date, current_date);
  v_book numeric; v_diff numeric; v_am numeric; v_duong numeric; v_total numeric;
begin
  v_actor := require_permission('adjust:manage');
  select * into v_cur from stock_period where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy kỳ.'; end if;
  if v_cur.status <> 'Mo' then raise exception 'Kỳ đã chốt.'; end if;
  if p_actual_liters is null or p_actual_liters < 0 then raise exception 'Tồn thực tế không hợp lệ.'; end if;
  if v_close < v_cur.start_date then raise exception 'Ngày chốt phải ≥ ngày bắt đầu.'; end if;

  v_book := tank_book_before(v_cur.tank_id, v_close);
  v_diff := round(v_book - p_actual_liters, 2);
  v_am := greatest(v_diff, 0);
  v_duong := greatest(-v_diff, 0);
  v_total := stock_period_pump_total(v_cur.tank_id, v_cur.start_date, v_close);

  update stock_period set actual_liters = p_actual_liters, book_liters = v_book,
    tinh_am = v_am, tinh_duong = v_duong, total_liters = v_total, close_date = v_close,
    status = 'DaChot', code = coalesce(v_cur.code, next_code_year('TINH')),
    closed_by = v_actor.id, closed_at = now()
  where id = p_id;

  perform stock_period_allocate(p_id, v_cur.tank_id, v_cur.start_date, v_close, v_am, v_duong, v_total);

  perform write_audit(v_actor, 'CLOSE_STOCK_PERIOD', 'stock_period', p_id::text, to_jsonb(v_cur),
    jsonb_build_object('book', v_book, 'actual', p_actual_liters, 'tinhAm', v_am, 'tinhDuong', v_duong, 'totalLit', v_total));
  return jsonb_build_object('ok', true, 'id', p_id, 'tinhAm', v_am, 'tinhDuong', v_duong, 'book', v_book);
end;
$$;

-- ----------------------------------------------------------------------------
-- rpc_stock_period_record — dùng helper + GIỮ guard biên-bản bắt buộc (từ 0026).
-- ----------------------------------------------------------------------------
create or replace function rpc_stock_period_record(
  p_tank_id uuid, p_kind text, p_start_date date, p_close_date date,
  p_actual_liters numeric, p_note text default null, p_bien_ban_path text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_actor profiles; v_id uuid; v_close date := coalesce(p_close_date, current_date);
  v_book numeric; v_diff numeric; v_am numeric; v_duong numeric; v_total numeric;
  v_row stock_period;
begin
  v_actor := require_permission('adjust:manage');
  if p_tank_id is null or not exists (select 1 from tanks where id = p_tank_id and active) then
    raise exception 'Téc không hợp lệ hoặc đã ngừng.'; end if;
  if p_kind not in ('tinh_tec','kiem_ke') then raise exception 'Loại kỳ không hợp lệ.'; end if;
  if p_kind = 'kiem_ke' and nullif(trim(coalesce(p_bien_ban_path,'')),'') is null then
    raise exception 'Kiểm kê phải đính kèm biên bản xác nhận.'; end if;
  if p_start_date is null then raise exception 'Chọn ngày bắt đầu.'; end if;
  if p_actual_liters is null or p_actual_liters < 0 then raise exception 'Tồn thực tế không hợp lệ.'; end if;
  if v_close < p_start_date then raise exception 'Ngày chốt phải ≥ ngày bắt đầu.'; end if;

  v_book := tank_book_before(p_tank_id, v_close);
  v_diff := round(v_book - p_actual_liters, 2);
  v_am := greatest(v_diff, 0);
  v_duong := greatest(-v_diff, 0);
  v_total := stock_period_pump_total(p_tank_id, p_start_date, v_close);

  insert into stock_period (code, tank_id, kind, start_date, close_date, actual_liters,
      book_liters, tinh_am, tinh_duong, total_liters, status, note, bien_ban_path,
      created_by, closed_by, closed_at)
  values (next_code_year('TINH'), p_tank_id, p_kind, p_start_date, v_close, p_actual_liters,
      v_book, v_am, v_duong, v_total, 'DaChot', nullif(trim(coalesce(p_note,'')),''),
      nullif(trim(coalesce(p_bien_ban_path,'')),''), v_actor.id, v_actor.id, now())
  returning * into v_row;
  v_id := v_row.id;

  perform stock_period_allocate(v_id, p_tank_id, p_start_date, v_close, v_am, v_duong, v_total);

  perform write_audit(v_actor, 'RECORD_STOCK_PERIOD', 'stock_period', v_id::text, null,
    jsonb_build_object('kind', p_kind, 'book', v_book, 'actual', p_actual_liters,
      'tinhAm', v_am, 'tinhDuong', v_duong, 'totalLit', v_total));
  return jsonb_build_object('ok', true, 'id', v_id, 'tinhAm', v_am, 'tinhDuong', v_duong, 'book', v_book);
end;
$$;

grant execute on function rpc_stock_period_close(uuid, numeric, date) to authenticated;
grant execute on function rpc_stock_period_record(uuid, text, date, date, numeric, text, text) to authenticated;
