# S3 · Ảnh chứng từ (bắt buộc) + OCR-ready

## What to build
Bắt buộc đính kèm Ảnh chứng từ cho Phiếu bơm: ≥2 ảnh có kiểu (`pump_meter` = đồng hồ bơm, `odometer` = công-tơ-mét); ảnh KM bỏ được cho Xe không có công-tơ-mét. Lưu Supabase Storage **bucket riêng tư**, truy cập qua URL ký/RPC; chỉ ThuKho/KeToan/Admin xem. Mỗi bản ghi ảnh có sẵn trường OCR: `ocr_value`, `ocr_confidence`, `manually_corrected` (V1 để trống). Màn đối chiếu mở ảnh khi cần (phóng to) cạnh số liệu.

## Acceptance criteria
- [ ] Không submit được phiếu bơm thiếu ảnh đồng hồ bơm (ảnh KM tùy thiết bị).
- [ ] Ảnh lưu ở bucket riêng tư; người ngoài vai trò không truy cập được URL.
- [ ] Chụp bằng camera điện thoại từ card nhập bơm.
- [ ] Schema ảnh có ocr_value/confidence/manually_corrected (rỗng ở V1).
- [ ] Màn đối chiếu hiển thị/mở được 2 ảnh của phiếu.

## Blocked by
- S2
