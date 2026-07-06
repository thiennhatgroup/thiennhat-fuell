# Thiên Nhật — Tồn kho Xăng dầu (Supabase)

Web app quản lý tồn kho xăng dầu: nhập bơm/nhập/tịnh téc, tồn kho thời gian thực, báo cáo tiêu hao tháng. Port từ file Google Sheets + Apps Script sang Supabase (Postgres + Auth) + frontend tĩnh (PWA), theo đúng khuôn `thiennhat-supabase`.

## Tài liệu
- `docs/PRD_ton_kho_xang_dau.md` — PRD đầy đủ.
- `UBIQUITOUS_LANGUAGE.md` — ngôn ngữ chung (glossary).
- `docs/issues/S0..S9` — lộ trình build theo lát dọc (tracer bullet).
- `HUONG_DAN_SETUP.md` — hướng dẫn set up GitHub + Supabase.

## Kiến trúc
- DB + Auth + logic: Supabase. Deny-by-default: mọi bảng bật RLS không policy, mọi truy cập qua RPC `SECURITY DEFINER` + `require_permission()`.
- Frontend: một file `public/index.html` (PWA), host GitHub Pages qua nhánh `gh-pages`.
- Đăng nhập email + PIN (FE prefix `tn-pin::`).
- Vai trò: `ThuKho`, `KeToan`, `Admin`.

## Deploy
- Push `main` → GitHub Actions: "Deploy Supabase migrations" (`supabase db push`) + "Deploy frontend" (đẩy `public/` lên `gh-pages`).
- Secrets cần đặt (Settings → Secrets → Actions): `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`.

## Trạng thái
- **S0 (nền tảng)**: schema người dùng/quyền, RLS, `rpc_bootstrap`, quản tài khoản, FE shell đăng nhập — xong.
- S1→S9: theo `docs/issues`.
