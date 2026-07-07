# Cài đặt Web Push (S7) — làm MỘT LẦN qua Dashboard/CLI

Cảnh báo tồn (tồn thấp/âm/vượt sức chứa) luôn hiển thị trong app (màn **Cảnh báo** + chuông 🔔)
kể cả khi CHƯA cấu hình push. Push (thông báo cả khi đóng app) là phần thêm — nếu bỏ qua các
bước dưới, app vẫn chạy bình thường (RPC `push_dispatch` tự bỏ qua an toàn khi thiếu cấu hình).

## 1. Tạo cặp khóa VAPID
Chạy một lần (máy bất kỳ có Node):
```
npx web-push generate-vapid-keys
```
Ghi lại `Public Key` và `Private Key`.

## 2. Nhúng public key vào frontend
`public/config.js` → `vapidPublicKey: "<Public Key>"`. Commit + push → deploy gh-pages.
(Để trống ⇒ nút "Bật thông báo" ẩn.)

## 3. Deploy Edge Function `send-push`
- CLI: `supabase functions deploy send-push --no-verify-jwt`
- hoặc để GitHub Action **Deploy Edge Functions** chạy khi push `supabase/functions/**`
  (cần secret `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` — đã có sẵn cho db push).

## 4. Đặt Secrets cho Edge Function
Supabase → Project Settings → Edge Functions → **Secrets** (hoặc `supabase secrets set`):
| Secret | Giá trị |
|---|---|
| `PUSH_WEBHOOK_SECRET` | một chuỗi ngẫu nhiên bí mật (vd `openssl rand -hex 24`) |
| `VAPID_PUBLIC_KEY` | Public Key ở bước 1 |
| `VAPID_PRIVATE_KEY` | Private Key ở bước 1 |
| `VAPID_SUBJECT` | `mailto:admin@thiennhatgroup.com` |
(`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` được runtime tự cấp — không cần đặt.)

## 5. Cho DB gọi Edge Function
- Bật extension **pg_net**: Dashboard → Database → Extensions → bật `pg_net`
  (hoặc `create extension if not exists pg_net;`). Thiếu pg_net ⇒ push bị bỏ qua an toàn.
- Nạp URL + secret vào `app_config` (SQL Editor), khớp `PUSH_WEBHOOK_SECRET` ở bước 4:
```sql
insert into app_config (key, value) values
  ('edge_push_url',    to_jsonb('https://<project-ref>.supabase.co/functions/v1/send-push'::text)),
  ('edge_push_secret', to_jsonb('<PUSH_WEBHOOK_SECRET>'::text))
on conflict (key) do update set value = excluded.value;
```

## 6. Bật trên thiết bị
Đăng nhập vai trò **Kế toán/Admin** → màn **Cảnh báo** → "Bật thông báo đẩy trên thiết bị này".
- **iOS**: bắt buộc "Thêm vào Màn hình chính" (cài PWA) trước, rồi mới bật được push.

## Luồng chạy
Tồn đổi (duyệt phiếu / chốt tịnh / mở màn Tồn kho) → FE gọi `rpc_alerts_scan` →
`alerts_scan()` chèn cảnh báo mới (dedup 1/loại/téc/ngày) → nếu có cảnh báo mới gọi
`push_dispatch()` → `net.http_post` tới `send-push` kèm `x-webhook-secret` →
function xác thực secret, gửi Web Push (VAPID) tới subscription của Kế toán/Admin, set `pushed_at`.
