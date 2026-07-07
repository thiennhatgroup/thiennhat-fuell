-- ============================================================================
-- 0026_kiemke_bienban_required.sql — Batch 9 follow-up (code review)
-- Bịt lỗ hổng: "Kiểm kê phải đính kèm biên bản" trước đây CHỈ chặn ở frontend.
-- RPC rpc_stock_period_record (0025) vẫn nhận p_bien_ban_path = null cho kiểm kê,
-- nên gọi thẳng RPC (hoặc upload lỗi rồi thử lại) có thể ghi một kỳ kiểm kê KHÔNG
-- có biên bản. Đưa bất biến này về đúng chỗ — mặt seam của RPC — để mọi caller đều
-- bị ràng buộc, không chỉ một caller ở FE.
-- KHÔNG sửa migration cũ: create-or-replace nguyên hàm 0025 + thêm ĐÚNG một guard.
-- Phần tính tịnh âm/dương + phân bổ cho xe giữ NGUYÊN VĂN so với 0025 (không đụng
-- toán học phân bổ nhiên liệu theo xe).
-- ============================================================================
create or replace function rpc_stock_period_record(
  p_tank_id uuid, p_kind text, p_start_date date, p_close_date date,
  p_actual_liters numeric, p_note text default null, p_bien_ban_path text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_actor profiles; v_id uuid; v_close date := coalesce(p_close_date, current_date);
  v_book numeric; v_diff numeric; v_am numeric; v_duong numeric; v_total numeric;
  v_rec record; v_sum_am numeric := 0; v_sum_duong numeric := 0; v_max_veh uuid; v_a numeric; v_d numeric;
  v_row stock_period;
begin
  v_actor := require_permission('adjust:manage');
  if p_tank_id is null or not exists (select 1 from tanks where id = p_tank_id and active) then
    raise exception 'Téc không hợp lệ hoặc đã ngừng.'; end if;
  if p_kind not in ('tinh_tec','kiem_ke') then raise exception 'Loại kỳ không hợp lệ.'; end if;
  -- Bất biến mới: kiểm kê bắt buộc có biên bản xác nhận (đưa về mặt seam của RPC).
  if p_kind = 'kiem_ke' and nullif(trim(coalesce(p_bien_ban_path,'')),'') is null then
    raise exception 'Kiểm kê phải đính kèm biên bản xác nhận.'; end if;
  if p_start_date is null then raise exception 'Chọn ngày bắt đầu.'; end if;
  if p_actual_liters is null or p_actual_liters < 0 then raise exception 'Tồn thực tế không hợp lệ.'; end if;
  if v_close < p_start_date then raise exception 'Ngày chốt phải ≥ ngày bắt đầu.'; end if;

  v_book := tank_book_before(p_tank_id, v_close);
  v_diff := round(v_book - p_actual_liters, 2);
  v_am := greatest(v_diff, 0);
  v_duong := greatest(-v_diff, 0);

  -- Tổng lít xe bơm (xuất) từ téc trong kỳ.
  select coalesce(sum(l.liters), 0) into v_total from ledger l
    join transaction_types tt on tt.id = l.txn_type_id
    where l.tank_id = p_tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
      and l.vehicle_id is not null and (l.status = 'DaDuyet' or l.legacy)
      and l.entry_date between p_start_date and v_close;

  insert into stock_period (code, tank_id, kind, start_date, close_date, actual_liters,
      book_liters, tinh_am, tinh_duong, total_liters, status, note, bien_ban_path,
      created_by, closed_by, closed_at)
  values (next_code_year('TINH'), p_tank_id, p_kind, p_start_date, v_close, p_actual_liters,
      v_book, v_am, v_duong, v_total, 'DaChot', nullif(trim(coalesce(p_note,'')),''),
      nullif(trim(coalesce(p_bien_ban_path,'')),''), v_actor.id, v_actor.id, now())
  returning * into v_row;
  v_id := v_row.id;

  -- Phân bổ theo tỉ lệ lít (chỉ khi có tịnh và có xe bơm).
  if v_total > 0 and (v_am > 0 or v_duong > 0) then
    for v_rec in
      select l.vehicle_id, sum(l.liters) as lit from ledger l
        join transaction_types tt on tt.id = l.txn_type_id
        where l.tank_id = p_tank_id and l.entry_type = 'bom' and tt.kind = 'xuat'
          and l.vehicle_id is not null and (l.status = 'DaDuyet' or l.legacy)
          and l.entry_date between p_start_date and v_close
        group by l.vehicle_id
        order by sum(l.liters) desc
    loop
      if v_max_veh is null then v_max_veh := v_rec.vehicle_id; end if;
      v_a := round(v_am * v_rec.lit / v_total, 2);
      v_d := round(v_duong * v_rec.lit / v_total, 2);
      insert into stock_period_alloc (period_id, vehicle_id, liters_in_period, tinh_am, tinh_duong)
      values (v_id, v_rec.vehicle_id, v_rec.lit, v_a, v_d);
      v_sum_am := v_sum_am + v_a; v_sum_duong := v_sum_duong + v_d;
    end loop;
    if v_max_veh is not null then
      update stock_period_alloc
        set tinh_am = tinh_am + (v_am - v_sum_am), tinh_duong = tinh_duong + (v_duong - v_sum_duong)
        where period_id = v_id and vehicle_id = v_max_veh;
    end if;
  end if;

  perform write_audit(v_actor, 'RECORD_STOCK_PERIOD', 'stock_period', v_id::text, null,
    jsonb_build_object('kind', p_kind, 'book', v_book, 'actual', p_actual_liters,
      'tinhAm', v_am, 'tinhDuong', v_duong, 'totalLit', v_total));
  return jsonb_build_object('ok', true, 'id', v_id, 'tinhAm', v_am, 'tinhDuong', v_duong, 'book', v_book);
end;
$$;

grant execute on function rpc_stock_period_record(uuid, text, date, date, numeric, text, text) to authenticated;
