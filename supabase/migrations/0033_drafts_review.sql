-- ============================================================================
-- 0033_drafts_review.sql — Batch 9 · Mục 3: các thủ kho cùng xem phiếu nháp
-- trong ngày trước khi submit. Chỉ XEM chéo; sửa/upload lại ảnh vẫn do người tạo
-- (đã ép ở 0008/0018: rpc_pump_update/rpc_nhap_update + ảnh chỉ created_by=auth.uid()
-- và chỉ khi status='Nhap'). Đây chỉ thêm 2 RPC ĐỌC.
-- KHÔNG sửa migration cũ.
-- ============================================================================

-- Danh sách mọi phiếu còn Nháp (bom+nhap) của mọi thủ kho, kèm người tạo, cờ
-- canEdit (= của chính mình) và các loại ảnh đã đính (để biết còn thiếu ảnh nào).
create or replace function rpc_drafts_pending(p_entry_type text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_rows jsonb;
begin
  v_actor := require_permission('pump:create');
  select coalesce(jsonb_agg(r order by r_date desc, r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'entryType', l.entry_type,
      'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'vehiclePlate', ve.plate, 'txnName', tt.name, 'txnKind', tt.kind,
      'tankName', tk.name, 'oilTypeName', ot.name, 'supplierName', su.name,
      'liters', l.liters, 'kmOld', l.km_old, 'kmNew', l.km_new,
      'unitPrice', l.unit_price, 'amount', round(coalesce(l.liters,0)*coalesce(l.unit_price,0),2),
      'supplierInvoiceNo', l.supplier_invoice_no, 'note', l.note,
      'createdByName', pc.name, 'canEdit', (l.created_by = v_actor.id),
      'hasOdometer', coalesce(ve.has_odometer,false),
      'photoKinds', coalesce((select jsonb_agg(distinct pp.kind) from pump_photos pp where pp.ledger_id = l.id), '[]'::jsonb)
    ) as r, l.entry_date as r_date, l.created_at as r_created
    from ledger l
    left join vehicles ve on ve.id = l.vehicle_id
    left join transaction_types tt on tt.id = l.txn_type_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    left join suppliers su on su.id = l.supplier_id
    left join profiles pc on pc.id = l.created_by
    where l.status = 'Nhap' and l.entry_type in ('bom','nhap')
      and (p_entry_type is null or l.entry_type = p_entry_type)
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- Xem ảnh của MỘT phiếu nháp bất kỳ (chỉ đọc) — cho thủ kho soi chéo trước submit.
create or replace function rpc_draft_photo_list(p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('pump:create');
  if not exists (select 1 from ledger where id = p_ledger_id and status = 'Nhap'
                   and entry_type in ('bom','nhap')) then
    raise exception 'Chỉ xem ảnh phiếu còn Nháp.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'path', storage_path) order by kind), '[]'::jsonb) into v_rows
  from pump_photos where ledger_id = p_ledger_id;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_drafts_pending(text) to authenticated;
grant execute on function rpc_draft_photo_list(uuid) to authenticated;
