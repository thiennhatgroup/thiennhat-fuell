# S1 · Danh mục nền

## What to build
Danh mục quản bởi Kế toán/Admin: **Téc** (biển tên, sức chứa, reorder point, lead-time ngày), **Loại dầu**, **Nhà cung cấp**, **Loại giao dịch** (Xuất nội bộ từ téc / Bơm ngoài / Nhập vào kho/téc), **Xe** (biển số, định mức bơm, cờ active). RPC list/upsert cho từng danh mục + màn Danh mục. Thêm Xe mới và **ngừng hoạt động** Xe (soft-delete: active=false, ẩn khỏi dropdown nhập liệu, giữ nguyên lịch sử).

## Acceptance criteria
- [ ] Kế toán/Admin thêm/sửa Téc với sức chứa/reorder/lead-time; ThuKho không sửa được.
- [ ] Thêm/sửa Loại dầu, NCC, Loại giao dịch.
- [ ] Thêm Xe (biển số + định mức); "ngừng hoạt động" ẩn Xe khỏi dropdown nhưng lịch sử vẫn còn.
- [ ] RPC từ chối vai trò không đủ quyền.
- [ ] Dropdown nhập liệu chỉ hiện Xe/Téc active.

## Blocked by
- S0
