# Project Instructions — Tồn kho Xăng dầu (Thiên Nhật)

App tồn kho xăng dầu dùng Supabase RPC + frontend một-file (PWA). Port từ Google Sheets + Apps Script.

## Đọc trước khi làm (theo thứ tự)
1. `docs/HANDOFF.md` — hiện trạng + việc tiếp theo (đọc ĐẦU TIÊN).
2. `docs/PRD_ton_kho_xang_dau.md` — quyết định sản phẩm/kỹ thuật.
3. `UBIQUITOUS_LANGUAGE.md` — ngôn ngữ chung (dùng đúng thuật ngữ này ở code/issue).
4. `docs/issues/S0..S9` — lộ trình build theo lát dọc.

## Quy tắc
- Audit trước khi sửa. Thay đổi theo từng lát (slice), phạm vi hẹp.
- **KHÔNG sửa migration cũ**; thêm migration mới `NNNN_*.sql` override RPC đang chạy.
- Giữ mô hình bảo mật RPC-first: mọi bảng RLS deny-by-default, mọi ghi qua RPC `SECURITY DEFINER` + `require_permission()`, có `set search_path = public, pg_temp`.
- KHÔNG chuyển sang RLS-everywhere trừ khi được duyệt.
- Sổ cái append-only là nguồn sự thật; tồn kho/báo cáo *tính ra*, không ghi đè.
- Đăng nhập email + PIN: FE prefix `tn-pin::<pin>`. Vai trò: `ThuKho`, `KeToan`, `Admin`.
- Không revert thay đổi không liên quan của người dùng.
- Commit chỉ phần của lát hiện tại.

## Kiểm thử tĩnh (sandbox không có Supabase/psql/Deno)
- SQL: `python3 -c "from pglast import parse_sql,parse_plpgsql; ..."` nếu cài được; nếu không, kiểm tra cấu trúc ($$ cân bằng, ngoặc, mỗi function có language) + để deploy/Supabase SQL Editor validate thật.
- FE: trích `<script>` từ `public/index.html` rồi `node --check`. `node --check public/config.js`.
- Không kết nối được GitHub/PyPI từ sandbox (mạng chặn). Deploy qua GitHub Actions.

## Deploy
- Repo GitHub: `thiennhatgroup/thiennhat-fuell`. Supabase project ref: `zaipiepimqkbulaiaupe`.
- Push `main` → Actions: "Deploy Supabase migrations" (`supabase db push`) + "Deploy frontend" (đẩy `public/` lên `gh-pages`).
- Secrets Actions: `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_ACCESS_TOKEN`.
- Người dùng thao tác git qua **GitHub Desktop** (người mới), Supabase qua **web dashboard** (không CLI).
