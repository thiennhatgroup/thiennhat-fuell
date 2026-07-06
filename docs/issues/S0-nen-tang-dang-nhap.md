# S0 · Nền tảng + đăng nhập (tracer bullet)

## What to build
Dựng khung dự án bám khuôn `thiennhat-supabase` và một đường xuyên end-to-end mỏng nhất: người dùng đăng nhập bằng email + PIN và thấy shell PWA rỗng theo vai trò. Gồm: Supabase project mới + repo mới (org thiennhatgroup), migration schema tối thiểu (profiles có role, role_permissions, app_config, code_counters, audit_log) với RLS deny-by-default; `rpc_bootstrap` trả hồ sơ + quyền theo vai trò; frontend một file (manifest + service worker, cài màn hình chính) với đăng nhập email+PIN (prefix `tn-pin::`); GitHub Actions deploy migrations theo thứ tự số + đẩy `public/` lên `gh-pages`.

Ba vai trò: `ThuKho`, `KeToan`, `Admin`. Màn quản tài khoản (Admin tạo user + PIN + vai trò, đặt lại PIN).

## Acceptance criteria
- [ ] Đăng nhập live bằng email + PIN thành công; sai PIN báo lỗi rõ.
- [ ] Sau đăng nhập, shell hiện điều hướng theo vai trò (rỗng cũng được), đọc quyền từ role_permissions qua `rpc_bootstrap`.
- [ ] Mọi bảng bật RLS, không policy, mọi truy cập qua RPC SECURITY DEFINER + `require_permission()`, có `set search_path = public, pg_temp`.
- [ ] Admin tạo được user (email+PIN+vai trò) và đặt lại PIN.
- [ ] Push `main` → Actions chạy migrations xanh + publish Pages; cài được lên màn hình chính điện thoại.
- [ ] SQL parse sạch bằng pglast; `<script>` FE qua `node --check`.

## Blocked by
None - can start immediately.
