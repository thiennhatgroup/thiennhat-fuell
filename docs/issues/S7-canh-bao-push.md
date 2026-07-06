# S7 · Cảnh báo tồn thấp + Web Push

## What to build
Sinh cảnh báo khi tồn Téc dưới reorder point, tồn âm, hoặc vượt sức chứa → tạo notification + đẩy **web push (VAPID)** tới Kế toán/Admin (kể cả khi đóng app). Đăng ký push subscription trên thiết bị; Edge Function gửi push có xác thực secret (theo mẫu thiennhat).

## Acceptance criteria
- [ ] Khi tồn xuống dưới reorder point → tạo notification + push tới Kế toán/Admin.
- [ ] Cảnh báo tồn âm/vượt sức chứa hoạt động.
- [ ] Bật/tắt push trên thiết bị; iOS cần cài PWA mới nhận.
- [ ] Edge Function gửi push xác thực secret; không secret thì bỏ qua an toàn.

## Blocked by
- S5
