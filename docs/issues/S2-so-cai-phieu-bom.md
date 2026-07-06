# S2 · Sổ cái + vòng đời Phiếu bơm

## What to build
Sổ cái append-only + máy trạng thái Phiếu bơm end-to-end (chưa có ảnh). Máy trạng thái (từ prototype grilling):

`Nhap` → (Submit ngày, cả lô) → `ChoDoiChieu` → `DaDuyet` | `TraVe`
- Nhap: người tạo sửa/xóa tự do trong ngày.
- Submit ngày: chốt cả lô ngày → ChoDoiChieu, khóa với người tạo.
- RutLai: ChoDoiChieu → Nhap, chỉ khi chưa ai đối chiếu.
- Đối chiếu chéo do ThuKho khác người tạo: Khớp → DaDuyet (ghi vào Sổ cái) | Lệch → TraVe (kèm lý do, về Nhap của người tạo).

Số phiếu tự cấp qua code_counters (BOM-YYYY-######). UI: card nhập bơm (chọn Xe, Loại giao dịch, Téc, Loại dầu, số lít, KM), danh sách nháp trong ngày + review cuối ngày + nút Submit ngày; hàng đợi đối chiếu (list gọn, nút Khớp/Lệch). Ghi audit ai/lúc nào.

## Acceptance criteria
- [ ] Tạo/sửa/xóa phiếu Nhap trong ngày; Submit ngày chốt cả lô sang ChoDoiChieu.
- [ ] RutLai được khi chưa đối chiếu; không được sau khi đã có người đối chiếu.
- [ ] ThuKho KHÔNG duyệt được phiếu do chính mình tạo (chặn ở RPC).
- [ ] Khớp → phiếu vào Sổ cái (DaDuyet); Lệch → về Nhap của người tạo kèm lý do.
- [ ] Số phiếu duy nhất, tăng dần theo năm.
- [ ] Test mô phỏng SQL: full vòng đời + chặn tự-duyệt + chỉ DaDuyet vào ledger.

## Blocked by
- S1
