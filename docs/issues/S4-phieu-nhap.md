# S4 · Phiếu nhập (NHAP) + ảnh + đối chiếu

## What to build
Luồng nhập dầu về téc, tái dùng máy trạng thái + ảnh + đối chiếu của S2/S3. Trường: Nhà cung cấp, Téc nhận, Loại dầu, số lít, đơn giá, thành tiền, **Số HĐ NCC** (nhập tay, khác Số phiếu tự cấp), ảnh phiếu nhập (kiểu `receipt`). Cùng vòng đời Nhap→Submit→ĐốiChiếu→DaDuyet/TraVe.

## Acceptance criteria
- [x] Tạo phiếu nhập với NCC/téc/loại dầu/số lít/đơn giá; thành tiền tự tính.
- [x] Số phiếu tự cấp NHAP-YYYY-######; ô Số HĐ NCC riêng, nhập tay.
- [x] Bắt ≥1 ảnh phiếu nhập; qua đối chiếu chéo như phiếu bơm.
- [x] DaDuyet → vào Sổ cái (loại NHAP).

## Blocked by
- S3

## Đã build (0010_nhap_receipt.sql + FE)
- Cột `ledger.supplier_invoice_no` (Số HĐ NCC); `pump_photos.kind` mở rộng 'receipt'.
- RPC vòng đời `rpc_nhap_*` (create/update/delete/submit_day/withdraw/list_mine/
  review_queue/approve/reject) + ảnh `rpc_nhap_photo_add/delete/list`, tái dùng
  bucket 'chung-tu' + helper Storage của S3. Vai trò dùng chung phiếu bơm:
  tạo `pump:create`, đối chiếu `pump:review` (chặn tự-duyệt).
- FE: màn "Phiếu nhập" (form NCC/téc/loại dầu/lít/đơn giá/thành tiền tự tính/
  Số HĐ NCC + panel ảnh phiếu nhập + danh sách + Submit ngày) và "Đối chiếu nhập".
- Test: `supabase/tests/nhap_flow_simulation.sql` (chạy trong SQL Editor sau deploy).
