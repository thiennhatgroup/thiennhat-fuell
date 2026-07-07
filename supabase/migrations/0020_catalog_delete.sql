-- ============================================================================
-- 0020 — Batch 5: Cho phép XÓA CỨNG mục danh mục (không chỉ ngừng).
-- Chặn xóa khi đã có dữ liệu tham chiếu (ledger / kỳ tịnh / téc dùng loại dầu…)
-- → báo dùng "Ngừng" thay thế. Loại giao dịch cố định: không cho xóa.
-- Gated catalog:manage + audit. KHÔNG sửa migration cũ.
-- ============================================================================

create or replace function rpc_catalog_delete(p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_tbl text; v_used boolean := false; v_row jsonb;
begin
  v_actor := require_permission('catalog:manage');
  if p_kind = 'txnType' then
    raise exception 'Loại giao dịch cố định, chỉ đổi tên hoặc ngừng — không xóa.';
  end if;
  v_tbl := case p_kind
    when 'oilType'  then 'oil_types'
    when 'supplier' then 'suppliers'
    when 'tank'     then 'tanks'
    when 'vehicle'  then 'vehicles'
    else null end;
  if v_tbl is null then raise exception 'Loại danh mục không hợp lệ: %', p_kind; end if;

  if p_kind = 'tank' then
    v_used := exists (select 1 from ledger where tank_id = p_id)
           or exists (select 1 from stock_period where tank_id = p_id);
  elsif p_kind = 'vehicle' then
    v_used := exists (select 1 from ledger where vehicle_id = p_id)
           or exists (select 1 from stock_period_alloc where vehicle_id = p_id);
  elsif p_kind = 'oilType' then
    v_used := exists (select 1 from ledger where oil_type_id = p_id)
           or exists (select 1 from tanks where oil_type_id = p_id);
  elsif p_kind = 'supplier' then
    v_used := exists (select 1 from ledger where supplier_id = p_id);
  end if;
  if v_used then
    raise exception 'Không thể xóa: đã có dữ liệu liên quan. Hãy dùng "Ngừng" thay vì xóa.';
  end if;

  execute format('select to_jsonb(t) from %I t where id = $1', v_tbl) into v_row using p_id;
  if v_row is null then raise exception 'Không tìm thấy mục cần xóa.'; end if;
  execute format('delete from %I where id = $1', v_tbl) using p_id;

  perform write_audit(v_actor, 'DELETE_CATALOG', v_tbl, p_id::text, v_row, null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

grant execute on function rpc_catalog_delete(text, uuid) to authenticated;
