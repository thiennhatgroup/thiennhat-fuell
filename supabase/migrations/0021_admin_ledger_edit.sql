-- ============================================================================
-- 0021 — Batch 6: Admin sửa thẳng từng phiếu lịch sử + dashboard + audit trail.
-- Admin bỏ qua ma trận quyền (has_permission trả true khi role='Admin') nên
-- gate 'ledger:admin' ⇒ chỉ Admin qua được, ThuKho/KeToan bị chặn.
-- Mọi thao tác ghi audit_log (đã có time stamp) + đóng dấu edited_by/edited_at.
-- KHÔNG sửa migration cũ.
-- ============================================================================

alter table ledger add column if not exists edited_by uuid references profiles (id);
alter table ledger add column if not exists edited_at timestamptz;

-- ----------------------------------------------------------------------------
-- Dashboard: tất cả phiếu (bom+nhap) trong N ngày gần nhất. Lọc loại + tìm kiếm.
-- ----------------------------------------------------------------------------
create or replace function rpc_admin_ledger_list(
  p_days integer default 60, p_entry_type text default null, p_q text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb; v_days integer := greatest(coalesce(p_days, 60), 1);
        v_q text := nullif(trim(coalesce(p_q,'')),'');
begin
  perform require_permission('ledger:admin');
  select coalesce(jsonb_agg(r order by r_date desc, r_created desc), '[]'::jsonb) into v_rows from (
    select jsonb_build_object(
      'id', l.id, 'code', l.code, 'entryType', l.entry_type, 'status', l.status,
      'entryDate', to_char(l.entry_date,'YYYY-MM-DD'),
      'vehicleId', l.vehicle_id, 'vehiclePlate', ve.plate,
      'txnTypeId', l.txn_type_id, 'txnName', tt.name, 'txnKind', tt.kind,
      'tankId', l.tank_id, 'tankName', tk.name,
      'oilTypeId', l.oil_type_id, 'oilTypeName', ot.name,
      'supplierId', l.supplier_id, 'supplierName', su.name,
      'liters', l.liters, 'kmOld', l.km_old, 'kmNew', l.km_new,
      'unitPrice', l.unit_price, 'amount', round(coalesce(l.liters,0)*coalesce(l.unit_price,0),2),
      'supplierInvoiceNo', l.supplier_invoice_no, 'note', l.note,
      'legacy', l.legacy, 'createdByName', pc.name,
      'editedByName', pe.name, 'editedAt', to_char(l.edited_at,'YYYY-MM-DD HH24:MI')
    ) as r, l.entry_date as r_date, l.created_at as r_created
    from ledger l
    left join vehicles ve on ve.id = l.vehicle_id
    left join transaction_types tt on tt.id = l.txn_type_id
    left join tanks tk on tk.id = l.tank_id
    left join oil_types ot on ot.id = l.oil_type_id
    left join suppliers su on su.id = l.supplier_id
    left join profiles pc on pc.id = l.created_by
    left join profiles pe on pe.id = l.edited_by
    where l.entry_type in ('bom','nhap')
      and l.entry_date >= current_date - v_days
      and (p_entry_type is null or l.entry_type = p_entry_type)
      and (v_q is null or normalize_text(
            coalesce(l.code,'')||' '||coalesce(ve.plate,'')||' '||coalesce(su.name,'')||' '||coalesce(l.note,'')
          ) like '%'||normalize_text(v_q)||'%')
  ) s;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

-- ----------------------------------------------------------------------------
-- Admin sửa thẳng một phiếu (mọi trạng thái). Áp theo entry_type. Validate nhẹ
-- (số lít không âm) để không chặn sửa phiếu legacy có trường null.
-- ----------------------------------------------------------------------------
create or replace function rpc_admin_ledger_update(
  p_id uuid, p_entry_date date default null, p_liters numeric default null, p_note text default null,
  p_vehicle_id uuid default null, p_txn_type_id uuid default null, p_tank_id uuid default null,
  p_oil_type_id uuid default null, p_km_old numeric default null, p_km_new numeric default null,
  p_supplier_id uuid default null, p_unit_price numeric default null, p_supplier_invoice_no text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger; v_row ledger; v_before jsonb;
begin
  v_actor := require_permission('ledger:admin');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  if coalesce(p_liters, v_cur.liters) < 0 then raise exception 'Số lít không được âm.'; end if;
  v_before := to_jsonb(v_cur);

  if v_cur.entry_type = 'bom' then
    update ledger set
      entry_date = coalesce(p_entry_date, entry_date),
      vehicle_id = p_vehicle_id, txn_type_id = p_txn_type_id,
      tank_id = case when txn_kind(p_txn_type_id) = 'bom_ngoai' then null else p_tank_id end,
      oil_type_id = p_oil_type_id, liters = coalesce(p_liters, liters),
      km_old = p_km_old, km_new = p_km_new, supplier_id = p_supplier_id,
      note = nullif(trim(coalesce(p_note,'')),''),
      edited_by = v_actor.id, edited_at = now()
    where id = p_id returning * into v_row;
  elsif v_cur.entry_type = 'nhap' then
    update ledger set
      entry_date = coalesce(p_entry_date, entry_date),
      supplier_id = p_supplier_id, tank_id = p_tank_id, oil_type_id = p_oil_type_id,
      liters = coalesce(p_liters, liters), unit_price = p_unit_price,
      supplier_invoice_no = nullif(trim(coalesce(p_supplier_invoice_no,'')),''),
      note = nullif(trim(coalesce(p_note,'')),''),
      edited_by = v_actor.id, edited_at = now()
    where id = p_id returning * into v_row;
  else
    update ledger set
      entry_date = coalesce(p_entry_date, entry_date),
      liters = coalesce(p_liters, liters), note = nullif(trim(coalesce(p_note,'')),''),
      edited_by = v_actor.id, edited_at = now()
    where id = p_id returning * into v_row;
  end if;

  perform write_audit(v_actor, 'ADMIN_EDIT_LEDGER', 'ledger', p_id::text, v_before, to_jsonb(v_row));
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Admin xóa thẳng một phiếu (kèm audit). Ảnh chứng từ cascade theo FK.
create or replace function rpc_admin_ledger_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor profiles; v_cur ledger;
begin
  v_actor := require_permission('ledger:admin');
  select * into v_cur from ledger where id = p_id;
  if v_cur is null then raise exception 'Không tìm thấy phiếu.'; end if;
  delete from ledger where id = p_id;
  perform write_audit(v_actor, 'ADMIN_DELETE_LEDGER', 'ledger', p_id::text, to_jsonb(v_cur), null);
  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

-- Lịch sử thao tác (audit trail) của một phiếu — cho Admin xem.
create or replace function rpc_admin_ledger_audit(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rows jsonb;
begin
  perform require_permission('ledger:admin');
  select coalesce(jsonb_agg(jsonb_build_object(
    'time', to_char(a.time,'YYYY-MM-DD HH24:MI'), 'actor', a.actor_name,
    'action', a.action, 'message', a.message
  ) order by a.time desc), '[]'::jsonb) into v_rows
  from audit_log a where a.entity_type = 'ledger' and a.entity_id = p_id::text;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

grant execute on function rpc_admin_ledger_list(integer, text, text) to authenticated;
grant execute on function rpc_admin_ledger_update(uuid, date, numeric, text, uuid, uuid, uuid, uuid, numeric, numeric, uuid, numeric, text) to authenticated;
grant execute on function rpc_admin_ledger_delete(uuid) to authenticated;
grant execute on function rpc_admin_ledger_audit(uuid) to authenticated;
