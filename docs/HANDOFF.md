# Handoff / Context — App Tồn kho Xăng dầu

Đọc file này ĐẦU TIÊN khi mở session mới, rồi mở PRD/glossary/issues nếu cần chi tiết.

## 1. Dự án là gì
Web app tồn kho xăng dầu cho Thiên Nhật: nhập **bơm** (BOM) cho xe, **nhập** dầu về téc (NHAP), **tịnh téc/kiểm kê** khi lệch, **tồn kho thời gian thực**, **báo cáo tiêu hao tháng** cho kế toán. Port từ `File nhap lieu xang dau_v11.xlsx` + `appscript code.rtf`.
- Kiến trúc: **giống hệt `thiennhat-supabase`** — Supabase (Postgres) deny-by-default, mọi ghi qua RPC `SECURITY DEFINER` + `require_permission()`; frontend một file `public/index.html` (PWA) host GitHub Pages; auth email+PIN.
- Repo: `github.com/thiennhatgroup/thiennhat-fuell`. Supabase ref `zaipiepimqkbulaiaupe`.

## 2. Đã quyết (từ grilling — chi tiết ở PRD)
Vai trò `ThuKho`/`KeToan`/`Admin`. Đối chiếu chéo do **thủ kho khác người nhập** (per-phiếu; duyệt→vào tồn, từ chối→trả về sửa). Ảnh **bắt buộc 2 ảnh/phiếu bơm** (đồng hồ bơm + công-tơ-mét), Storage riêng tư, schema **sẵn-cho-OCR** (OCR bật phase sau). Phiếu bơm: Nháp→Submit cả lô cuối ngày→Chờ đối chiếu→Đã duyệt/Trả về; rút lại khi chưa đối chiếu. NHAP cũng có ảnh+đối chiếu; **TINH_TEC do Kế toán chốt**. Tịnh téc + **kiểm kê** hợp nhất một cơ chế, phân bổ chênh lệch cho xe theo **lít-trong-kỳ** (giữ nguyên công thức cũ). Tồn kho `= tồn đầu + nhập − xuất − tịnh âm + tịnh dương`. Bơm ngoài không trừ tồn téc. Thêm/bớt xe (soft-delete). Báo cáo **tái hiện sheet cũ 1-1** + tải Excel. Cảnh báo reorder + push PWA. Online-only. Migrate toàn bộ ~5.997 dòng DATA_GOC dạng legacy đã duyệt.

## 3. Trạng thái build
- **S0 (nền tảng) — XONG & đã push `main`** (commit "S0…"): `supabase/migrations/0001_schema..0005_admin_users`, `public/index.html` (login email+PIN, shell điều hướng theo vai trò, màn Tài khoản chạy thật), workflows, config.js đã điền URL+anon.
- **Go-live S0 đang chờ người dùng**: đặt 3 Actions secrets → chạy workflow "Deploy Supabase migrations" → bật Pages (gh-pages) → tạo Admin (Auth → Users, password `tn-pin::<PIN>`) + chạy `supabase/after_setup_create_admin.sql` → đăng nhập.
- **S1 (Danh mục & Xe) — XONG (chưa push)**: `supabase/migrations/0006_catalog.sql` (bảng oil_types/suppliers/transaction_types/tanks/vehicles deny-by-default + RPC list/active/upsert/toggle, gated `catalog:manage`; đọc active gated `catalog:read` cho mọi vai trò; seed 3 loại giao dịch) + màn "Danh mục & Xe" trong `public/index.html` (5 tab: Téc/Xe/Loại dầu/NCC/Loại giao dịch, thêm/sửa/bật-ngừng). Loại giao dịch cố định (chỉ đổi tên/ngừng). Đã qua kiểm thử tĩnh (`node --check` FE, cấu trúc SQL). **Cần push + deploy để validate DB thật.**
- **S2 (Sổ cái + vòng đời phiếu bơm) — XONG (chưa push)**: `supabase/migrations/0007_pump_ledger.sql` — bảng `ledger` append-only (entry_type bom/nhap/adjust; km_run generated; status Nhap/ChoDoiChieu/DaDuyet), deny-by-default. Máy trạng thái: Nhap→(Submit ngày, cấp Số phiếu BOM-YYYY-######)→ChoDoiChieu→DaDuyet | Lệch→về Nhap+reject_reason. RPC: create/update/delete/submit_day/withdraw/list_mine + review_queue/approve/reject (chặn tự-duyệt: created_by<>auth.uid()), vehicle_last_km (tự điền KM cũ). FE: màn Nhập bơm (form card + danh sách phiếu của tôi + Submit ngày + rút lại) và Đối chiếu chéo (hàng đợi Khớp/Lệch). Test mô phỏng `supabase/tests/pump_flow_simulation.sql` (BEGIN…ROLLBACK, giả lập auth.uid qua request.jwt.claim.sub) — **chưa chạy thật (sandbox không có DB); chạy trong SQL Editor sau deploy.** Kiểm thử tĩnh FE/SQL đã qua.
- **S3 (Ảnh chứng từ + OCR-ready) — XONG (chưa push)**: `supabase/migrations/0008_pump_photos.sql` — bảng `pump_photos` (kind pump_meter/odometer; storage_path; trường OCR ocr_value/ocr_confidence/manually_corrected rỗng V1) deny-by-default + bucket Storage RIÊNG TƯ `chung-tu` (public=false) + policy storage.objects (đọc: nhân sự Hoạt động; ghi/xóa: quyền `pump:create`, qua helper SECURITY DEFINER `chungtu_can_read/upload`). RPC `rpc_pump_photo_add/delete/list` (chỉ người tạo, chỉ khi Nháp; path phải thuộc `<ledger_id>/…`). **Override `rpc_pump_submit_day`**: chặn submit nếu thiếu ảnh đồng hồ bơm (mọi phiếu) hoặc thiếu ảnh công-tơ-mét khi Xe có công-tơ-mét — validate cả lô trước khi cấp Số phiếu. FE: card Nhập bơm sau khi lưu chuyển sang chế độ sửa, hiện panel "Ảnh chứng từ" (chụp camera `capture=environment`, upload Storage → đăng ký metadata, xem/xóa qua URL ký); màn Đối chiếu có nút "Ảnh" mở modal xem 2 ảnh. Test `supabase/tests/pump_photo_flow.sql` (gating + ranh giới RPC); cập nhật `pump_flow_simulation.sql` seed ảnh trước submit. Kiểm thử tĩnh FE/SQL đã qua; **chạy test trong SQL Editor sau deploy.**
- **Tiếp theo: S4 (Phiếu nhập)** — xem `docs/issues/S4-phieu-nhap.md`. Rồi S5→S9 theo thứ tự.

## 4. Lộ trình lát (docs/issues/)
S0 nền tảng ✅ · S1 danh mục & xe ✅ · S2 sổ cái + vòng đời phiếu bơm ✅ · S3 ảnh + OCR-ready ✅ · S4 phiếu nhập · S5 tồn kho realtime · S6 tịnh téc/kiểm kê + phân bổ · S7 cảnh báo + push · S8 báo cáo tháng · S9 migrate.

## 5. Lưu ý kỹ thuật
- KHÔNG sửa migration cũ; thêm `NNNN_*.sql` mới. Giữ RPC-first (xem AGENTS.md).
- Kiểm thử tĩnh: `node --check` cho FE; kiểm tra cấu trúc SQL (sandbox không có psql/pglast/mạng). Validate DB thật khi deploy.
- Logic gốc để tra cứu: `File nhap lieu xang dau_v11.xlsx` (sheet BOM/NHAP/TINH_TEC/TON_KHO/DATA_GOC/DANH_MUC/_TON_CAPACITY/_DM_BOM_BOM) + `appscript code.rtf` (công thức TON_KHO_ORIGINAL_FORMULAS_V20, phân bổ tịnh rows 233+, báo cáo restoreTieuHao*).
- Số phiếu tự sinh: helper `next_code_year('BOM')` → BOM-2026-000123 (đã có trong 0001).
- Tồn đầu gốc từng téc seed tại 1/1/2026 (lấy giá trị đo tay từ file cũ) — làm ở S5/S9.

## 6. Bảo mật
User đã lỡ dán service_role/secret/DB password + 1 GitHub token vào chat trước đó → đã khuyến nghị revoke/rotate. Không nhúng khóa nhạy cảm vào code/commit; chỉ anon+publishable ở frontend, service_role/secret trong Supabase secrets.
