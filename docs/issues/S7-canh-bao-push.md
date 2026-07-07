# S7 · Cảnh báo tồn thấp + Web Push

## What to build
Sinh cảnh báo khi tồn Téc dưới reorder point, tồn âm, hoặc vượt sức chứa → tạo notification + đẩy **web push (VAPID)** tới Kế toán/Admin (kể cả khi đóng app). Đăng ký push subscription trên thiết bị; Edge Function gửi push có xác thực secret (theo mẫu thiennhat).

## Acceptance criteria
- [x] Khi tồn xuống dưới reorder point → tạo notification + push tới Kế toán/Admin.
- [x] Cảnh báo tồn âm/vượt sức chứa hoạt động.
- [x] Bật/tắt push trên thiết bị; iOS cần cài PWA mới nhận.
- [x] Edge Function gửi push xác thực secret; không secret thì bỏ qua an toàn.

## Blocked by
- S5

## Đã build (0013_notifications.sql + Edge Function + FE)
- Bảng `notification` (kind ton_thap/ton_am/vuot_suc_chua, level, dedup_key duy nhất,
  pushed_at) + `notification_read` (đã đọc/người) + `push_subscription` (endpoint/thiết bị).
  Quyền mới `alert:read` (KeToan; Admin ngầm).
- `alerts_scan()` (nội bộ) tính lại tồn từng téc theo ĐÚNG công thức `rpc_inventory_stock`
  rồi chèn cảnh báo, **dedup theo kind:tank:ngày** (tối đa 1/loại/téc/ngày, không spam).
  `rpc_alerts_scan` (gated inventory:read) cho FE kích hoạt; `rpc_alerts_list` +
  `rpc_alerts_mark_read` (alert:read); `rpc_push_subscribe/unsubscribe`.
- `push_dispatch()` gọi Edge Function qua `net.http_post` (URL+secret ở `app_config`),
  CÓ GUARD: thiếu cấu hình / chưa bật pg_net ⇒ bỏ qua an toàn.
- Edge Function `supabase/functions/send-push` (VAPID, `npm:web-push`): xác thực
  `x-webhook-secret`, kéo notification chưa push, gửi tới subscription KeToan/Admin,
  set pushed_at, dọn endpoint 404/410. Thiếu secret/VAPID ⇒ trả 200 bỏ qua.
- FE: màn **Cảnh báo** (danh sách + đánh dấu đã đọc + bật/tắt push) + chuông 🔔 ở header
  (đếm chưa đọc); quét cảnh báo nền khi mở Tồn kho và khi đăng nhập; `sw.js` xử lý
  push + notificationclick.
- Cấu hình: `supabase/push_setup.md` (VAPID keys, secrets, pg_net, app_config) +
  workflow `.github/workflows/deploy-functions.yml`.
- Test `supabase/tests/alerts_simulation.sql` (3 tình huống + dedup + đọc + subscribe).
  Kiểm thử tĩnh FE (`node --check`)/SQL đã qua; **chạy test trong SQL Editor sau deploy.**
