# S5 · Tồn kho thời gian thực

## What to build
RPC/view tính Tồn kho từ Sổ cái theo từng Téc/Loại dầu: `Tồn cuối = Tồn đầu gốc + Nhập − Xuất − Tịnh âm + Tịnh dương` (chỉ bút toán DaDuyet/legacy). Seed Tồn đầu gốc một lần tại mốc khởi tạo. **Bơm ngoài** không trừ tồn téc. KM cũ tự điền = KM mới lần bơm gần nhất của Xe; tự tính KM đi; cảnh báo (không chặn) khi KM lùi/bất thường; KM để trống được. Màn tồn kho: tồn đầu/nhập/xuất/tịnh/tồn cuối, %đầy theo sức chứa.

## Acceptance criteria
- [x] Tồn cuối mỗi Téc đúng công thức, cập nhật ngay khi phiếu DaDuyet.
- [x] Bơm ngoài không làm đổi tồn kho téc.
- [x] KM cũ auto-fill từ lần bơm trước; cảnh báo khi KM mới < KM cũ; vẫn lưu được KM trống. *(đã có từ S2: `rpc_vehicle_last_km` + kmHint.)*
- [x] Màn tồn kho hiện %đầy + tồn âm/vượt sức chứa được đánh dấu.
- [x] Test: seed tồn đầu + chuỗi nhập/xuất/bơm-ngoài cho ra tồn cuối kỳ vọng.

## Blocked by
- S4

## Đã build (0011_inventory.sql + FE)
- Bảng `tank_opening` (tồn đầu gốc/téc) + `rpc_tank_opening_set` (KeToan, quyền
  `adjust:manage`, upsert theo téc).
- `rpc_inventory_stock` (quyền `inventory:read`): mỗi téc trả tồn đầu/nhập/xuất/
  tồn cuối/%đầy/điểm đặt hàng. Chỉ tính bút toán `DaDuyet` hoặc `legacy`. Nhập =
  entry_type='nhap'; Xuất = entry_type='bom' kind='xuat'; bơm ngoài (tank_id null)
  không trừ. Cột `adjust`=0 — **S6 sẽ OVERRIDE** để cộng/trừ tịnh có dấu.
- FE màn "Tồn kho": bảng + thanh %đầy, đánh dấu Tồn âm/Vượt sức chứa/Dưới điểm
  đặt hàng; panel "Đặt tồn đầu gốc" chỉ hiện với KeToan.
- Test `supabase/tests/inventory_stock_simulation.sql` (tồn cuối=7200 kỳ vọng).
- Seed giá trị tồn đầu đo tay thực tế: để ở S9 (migrate).
