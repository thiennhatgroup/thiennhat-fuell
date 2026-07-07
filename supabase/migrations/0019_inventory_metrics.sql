-- ============================================================================
-- 0019 — Batch 4: Tồn kho thời gian thực nâng cấp.
--   (a) Kẹp KHÔNG ÂM cho téc đặc biệt (cát nghiền): tồn cuối = greatest(.,0).
--       Dùng cờ tanks.clamp_negative để không hard-code tên trong RPC.
--   (b) Thêm chỉ số:
--       - Tiêu hao BQ ngày theo tuần (7 ngày) và theo tháng (30 ngày gần nhất).
--       - Số ngày tồn còn lại = tồn cuối / tiêu hao BQ tháng (tự tính).
--       - Số ngày chờ NCC = tanks.lead_time_days (nhập tay ở Danh mục).
--       - Mức tồn tối thiểu cần dự trữ = tiêu hao BQ tháng × lead_time_days (tự tính).
-- OVERRIDE lại rpc_inventory_stock (giữ đúng công thức tồn của S5/S6). KHÔNG sửa migration cũ.
-- ============================================================================

-- (a) Cờ kẹp không âm + bật cho téc cát nghiền (khớp tên đã bỏ dấu).
alter table tanks add column if not exists clamp_negative boolean not null default false;
update tanks set clamp_negative = true where normalize_text(name) like '%cat nghien%';

create or replace function rpc_inventory_stock() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('inventory:read');
  select coalesce(jsonb_agg(r order by r_name), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'tankId', t.id, 'tankName', t.name, 'oilTypeName', ot.name,
      'capacity', t.capacity_liters, 'reorderPoint', t.reorder_point,
      'opening', coalesce(op.liters, 0),
      'nhap', coalesce(nh.s, 0),
      'xuat', coalesce(xu.s, 0),
      'tinhAm', coalesce(aj.am, 0),
      'tinhDuong', coalesce(aj.duong, 0),
      'adjust', coalesce(aj.duong, 0) - coalesce(aj.am, 0),
      'closing', c.closing,
      'clampNegative', t.clamp_negative,
      'pctFull', case when t.capacity_liters > 0 then round(c.closing / t.capacity_liters * 100, 1) else null end,
      -- Chỉ số tiêu hao (theo xuất nội bộ từ téc, bút toán đã chốt).
      'avgDailyWeek', round(coalesce(x7.s, 0) / 7.0, 1),
      'avgDailyMonth', round(coalesce(x30.s, 0) / 30.0, 1),
      'leadTimeDays', t.lead_time_days,
      'daysLeft', case when coalesce(x30.s,0) > 0
        then round(c.closing / (x30.s / 30.0), 1) else null end,
      'minStock', round(coalesce(x30.s,0) / 30.0 * t.lead_time_days, 0),
      'openingAsOf', to_char(op.as_of_date, 'YYYY-MM-DD')
    ) as r, t.name as r_name
    from tanks t
    left join oil_types ot on ot.id = t.oil_type_id
    left join tank_opening op on op.tank_id = t.id
    left join lateral (
      select sum(l.liters) s from ledger l
       where l.tank_id = t.id and l.entry_type = 'nhap' and (l.status = 'DaDuyet' or l.legacy)
    ) nh on true
    left join lateral (
      select sum(l.liters) s from ledger l
       join transaction_types tt on tt.id = l.txn_type_id
       where l.tank_id = t.id and l.entry_type = 'bom' and tt.kind = 'xuat'
         and (l.status = 'DaDuyet' or l.legacy)
    ) xu on true
    left join lateral (
      select sum(l.liters) s from ledger l
       join transaction_types tt on tt.id = l.txn_type_id
       where l.tank_id = t.id and l.entry_type = 'bom' and tt.kind = 'xuat'
         and (l.status = 'DaDuyet' or l.legacy)
         and l.entry_date >= current_date - 7
    ) x7 on true
    left join lateral (
      select sum(l.liters) s from ledger l
       join transaction_types tt on tt.id = l.txn_type_id
       where l.tank_id = t.id and l.entry_type = 'bom' and tt.kind = 'xuat'
         and (l.status = 'DaDuyet' or l.legacy)
         and l.entry_date >= current_date - 30
    ) x30 on true
    left join lateral (
      select sum(sp.tinh_am) am, sum(sp.tinh_duong) duong from stock_period sp
       where sp.tank_id = t.id and sp.status = 'DaChot'
    ) aj on true
    -- Tồn cuối (kẹp không âm nếu téc bật cờ).
    left join lateral (
      select case when t.clamp_negative
        then greatest(coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0) - coalesce(aj.am,0) + coalesce(aj.duong,0), 0)
        else coalesce(op.liters,0) + coalesce(nh.s,0) - coalesce(xu.s,0) - coalesce(aj.am,0) + coalesce(aj.duong,0)
      end as closing
    ) c on true
    where t.active
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;
