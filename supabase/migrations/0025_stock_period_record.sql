-- ============================================================================
-- 0025_stock_period_record.sql — Batch 9: nhập tịnh téc / kiểm kê trực tiếp
-- (một bước: tạo + chốt) kèm khối lượng thực tế ngay trên form, tách rõ:
--   • Tịnh téc  → cần cả ngày bắt đầu lẫn ngày chốt.
--   • Kiểm kê   → lưu người kiểm kê + thời điểm + ảnh biên bản xác nhận.
-- KHÔNG sửa migration cũ; giữ nguyên rpc_stock_period_create/close cũ (kỳ Mo cũ vẫn
-- chốt được nếu còn). Bổ sung cột ảnh biên bản + RPC ghi-thẳng + mở quyền upload.
-- ============================================================================

-- Ảnh biên bản xác nhận kiểm kê (đường dẫn object trong bucket 'chung-tu').
alter table stock_period add column if not exists bien_ban_path text;

-- ----------------------------------------------------------------------------
-- Mở quyền upload bucket 'chung-tu' cho vai trò quản tồn (adjust:manage) — để
-- Kế toán / Trưởng bộ phận đính ảnh biên bản kiểm kê (trước chỉ pump:create).
-- (Chỉ sửa hàm helper — policy Storage vẫn tham chiếu helper này; không đụng policy.)
-- ----------------------------------------------------------------------------
create or replace function chungtu_can_upload() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from profiles pr
    where pr.id = auth.uid() and pr.status = 'Hoạt động'
      and (public.has_permission(pr.role, 'pump:create')
        or public.has_permission(pr.role, 'adjust:manage'))
  );
$$;
grant execute on function chungtu_can_upload() to authenticated;

-- ----------------------------------------------------------------------------
-- GHI THẲNG một kỳ (tạo + chốt trong một giao dịch) — nhập khối lượng thực tế
-- ngay trên form. Tính tồn sổ tại ngày chốt, tịnh âm/dương, phân bổ cho xe.
-- Kiểm kê: đóng dấu closed_by (người kiểm kê) + closed_at (thời điểm) + ảnh biên bản.
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- Override danh sách kỳ: bổ sung người ghi (closed_by) + thời điểm + ảnh biên bản.
-- ----------------------------------------------------------------------------
create or replace function rpc_stock_period_list()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('adjust:manage');
  select coalesce(jsonb_agg(r order by r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', sp.id, 'code', sp.code, 'tankId', sp.tank_id, 'tankName', tk.name, 'kind', sp.kind,
      'startDate', to_char(sp.start_date,'YYYY-MM-DD'), 'closeDate', to_char(sp.close_date,'YYYY-MM-DD'),
      'actual', sp.actual_liters, 'book', sp.book_liters, 'tinhAm', sp.tinh_am, 'tinhDuong', sp.tinh_duong,
      'totalLiters', sp.total_liters, 'status', sp.status, 'note', sp.note,
      'closedByName', pc.name, 'closedAt', to_char(sp.closed_at,'YYYY-MM-DD HH24:MI'),
      'bienBanPath', sp.bien_ban_path
    ) as r, sp.created_at as r_created
    from stock_period sp
    left join tanks tk on tk.id = sp.tank_id
    left join profiles pc on pc.id = sp.closed_by
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_stock_period_record(uuid, text, date, date, numeric, text, text) to authenticated;
grant execute on function rpc_stock_period_list() to authenticated;
