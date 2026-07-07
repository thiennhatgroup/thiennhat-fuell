# S11 · Bảng tự xếp thẻ dọc trên điện thoại (mobile reflow)

> Nguồn: `docs/PRD_frontend_uplift.md`. Phạm vi: CHỈ frontend (`public/index.html`). KHÔNG đụng backend.
> User stories phủ: 4,5.

## What to build

Trên điện thoại, bảng dữ liệu **tự xếp thành thẻ dọc** (mỗi ô có nhãn cột) thay vì tràn/cuộn ngang; bảng **nhập liệu** xếp dọc với ô nhập chiếm nguyên chiều ngang. Cắt ngang mọi màn có bảng (Tồn kho, Báo cáo, hàng đợi Đối chiếu, Danh mục…).

- Helper `labelTableCells(root)`: đọc `<thead th>` gắn `data-label` cho từng `<td>` (bỏ qua ô đã có nhãn).
- `MutationObserver` trên vùng nội dung màn: mỗi khi bảng mới render thì tự gắn `data-label` (không cần sửa từng hàm `renderXxx`).
- CSS breakpoint hẹp:
  - `table:not(.line-table)` (bảng chỉ đọc) → xếp thẻ: ẩn `thead`, mỗi hàng thành thẻ có bo góc/bóng, mỗi ô hiện `data-label` bên trái + giá trị bên phải.
  - `.line-table` (bảng nhập) → xếp dọc, nhãn phía trên, ô nhập full-width.

## Acceptance criteria

- [ ] Trên khổ điện thoại (≤ ~760px), bảng ở Tồn kho/Báo cáo/hàng đợi Đối chiếu/Danh mục hiển thị **dạng thẻ có nhãn cột**, không cuộn ngang.
- [ ] Bảng nhập liệu (dòng phiếu bơm/nhập nếu có) xếp dọc, ô nhập full-width, nhãn phía trên.
- [ ] Bảng render **sau khi tải bất đồng bộ** vẫn được gắn nhãn tự động (nhờ observer), không cần sửa từng màn.
- [ ] Trên desktop/tablet bảng giữ nguyên dạng hàng-cột như thường.
- [ ] Kiểm thử tĩnh (`node --check`) + QA điện thoại đạt.

## Blocked by

- S10 (cần tokens + vùng nội dung của vỏ mới).
