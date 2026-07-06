# S4 · Phiếu nhập (NHAP) + ảnh + đối chiếu

## What to build
Luồng nhập dầu về téc, tái dùng máy trạng thái + ảnh + đối chiếu của S2/S3. Trường: Nhà cung cấp, Téc nhận, Loại dầu, số lít, đơn giá, thành tiền, **Số HĐ NCC** (nhập tay, khác Số phiếu tự cấp), ảnh phiếu nhập (kiểu `receipt`). Cùng vòng đời Nhap→Submit→ĐốiChiếu→DaDuyet/TraVe.

## Acceptance criteria
- [ ] Tạo phiếu nhập với NCC/téc/loại dầu/số lít/đơn giá; thành tiền tự tính.
- [ ] Số phiếu tự cấp NHAP-YYYY-######; ô Số HĐ NCC riêng, nhập tay.
- [ ] Bắt ≥1 ảnh phiếu nhập; qua đối chiếu chéo như phiếu bơm.
- [ ] DaDuyet → vào Sổ cái (loại NHAP).

## Blocked by
- S3
