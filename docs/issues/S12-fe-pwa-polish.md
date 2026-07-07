# S12 · Hoàn thiện PWA (icon, manifest, service worker network-first)

> Nguồn: `docs/PRD_frontend_uplift.md`. Phạm vi: CHỈ frontend/asset PWA. GIỮ nguyên hành vi push/VAPID của S7.
> User stories phủ: 17,22,23.

## What to build

Hoàn thiện phần PWA để cài lên màn hình chính điện thoại đẹp và mở được khi mạng chập chờn, theo mẫu app tham chiếu.

- **Asset icon** trong `public/`: `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` (+ `logo.png`/`logo.svg` nếu chưa có từ S10) — sinh từ `Logo.png` ở gốc repo.
- **`manifest.webmanifest` đầy đủ**: `name`/`short_name`, `icons` (192/512 + maskable), `theme_color`/`background_color`, `display: standalone`, `lang: vi` — thay manifest hiện tại đang có `icons: []`.
- **Meta trong `<head>`**: apple-touch-icon, apple/mobile web-app meta, theme-color.
- **Service worker network-first**: ưu tiên bản mới khi có mạng (deploy mới hiện ngay), chỉ dùng cache khi mất mạng; **KHÔNG can thiệp** request Supabase/CDN (khác origin); **GIỮ nguyên** handler `push` + `notificationclick` của S7 (bấm push mở đúng màn Cảnh báo).

## Acceptance criteria

- [x] `manifest.webmanifest` hợp lệ, `icons` không rỗng (có 192/512 + maskable); cài lên màn hình chính điện thoại thấy icon đẹp, tên rút gọn đúng.
- [x] Service worker phục vụ vỏ app từ cache khi offline; khi có mạng lấy bản mới (network-first); không cache lời gọi Supabase.
- [x] Bấm vào thông báo push mở app đúng **màn Cảnh báo** (hành vi S7 không đổi).
- [x] apple-touch-icon + meta apple/mobile hiển thị đúng khi thêm vào Home Screen (iOS cần cài PWA).
- [x] Kiểm thử tĩnh (`node --check` FE/config) + QA cài đặt/offline/push đạt.

## Blocked by

- S10 (header dùng logo; asset trình bày chung).
