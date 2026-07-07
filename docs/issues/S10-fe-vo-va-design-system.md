# S10 · Vỏ điều hướng + Design system + Chuông thông báo + Modal (đồng bộ khuôn Mua hàng)

> Nguồn: `docs/PRD_frontend_uplift.md`. Phạm vi: CHỈ frontend (`public/index.html` + asset trình bày). KHÔNG đụng backend/RPC/schema/nghiệp vụ S1–S9.
> User stories phủ: 1,2,3,6,7,8,9,10,11,12,13,15,16,18,19,20,21,24.

## What to build

Lát xương sống của đợt nâng cấp giao diện: thay lớp **vỏ** (shell) hiện tại (dải nút pill cuộn ngang) bằng vỏ + bộ component theo đúng cảm quan app tham chiếu `thiennhat-supabase`, **giữ nguyên mọi hàm `renderXxx(el)` của S1–S9** (hợp đồng seam: mỗi màn vẫn render vào một container). Đây là một deliverable trọn gói "nhìn như app Mua hàng", gồm:

- **Design tokens đầy đủ**: bổ sung `--accent-dark`, `--accent-soft`, `--orange`, `--ok`, `--danger`, `--shadow`, `--input` (giữ `--accent` = `#0E5AA7`).
- **Component CSS dùng chung**: `.card`, `.notice` (+`.ok/.err/.warn`), `.pill` (+`.ok/.warn/.err`), `.metric`/`.totals`, `.approve-card`, `.loading-line`/`.spin`, `.workspace`, toast phân biệt `ok/err`.
- **Header**: logo thương hiệu (png + fallback svg), sticky nền mờ (backdrop blur); giữ nút đăng xuất + badge người dùng.
- **Điều hướng 2 tầng thay pill-nav**:
  - **Drawer hamburger**: liệt kê màn được cấp quyền, **đánh số**, **nhóm gập được**, **sắp theo vai trò** (`ThuKho` ưu tiên Nhập bơm/Đối chiếu; `KeToan` ưu tiên Tồn kho/Báo cáo/Tịnh téc; `Admin` sau cùng) — theo mẫu `ROLE_MENU_ORDER`/`orderScreensForRole`. Drawer đóng khi chọn màn hoặc bấm nền mờ.
  - **Thanh tab dưới cùng** (điện thoại): 4 màn đầu theo thứ tự vai trò + nút **"Thêm"** mở drawer; tab active đồng bộ màn hiện tại.
  - **FAB "quay lại"** + **FAB "lên đầu trang"** (hiện khi cuộn sâu); `navTo` dùng `history.pushState`/`popstate` để nút back thiết bị hoạt động (mức nhẹ, không thêm router).
- **Helper trình bày**: `withBusy(btn,label,fn)` (khoá nút + "Đang xử lý…"), `loadingText()` (spinner + "Đang tải…").
- **Chuông thông báo trên header**: chuyển nút chuông S7 hiện có thành **badge số chưa đọc + `.notif-panel`** (danh sách + đánh dấu đã đọc). **Tái dùng RPC S7 sẵn có** (`rpc_alerts_list`/`rpc_alerts_mark_read`) — KHÔNG tạo RPC mới.
- **Modal giàu hơn**: `openModal()`/`closeModal()`/`modalErr()` + `promptReason()` (hộp nhập lý do trong app thay `prompt()`), áp cho các chỗ đang dùng `prompt()`/modal cơ bản (VD nhập lý do từ chối khi Đối chiếu).
- **Khuôn `renderShell` 2 cột** (form + kết quả/dữ liệu phụ) áp cho màn phù hợp; tự co về 1 cột trên điện thoại. Không ép mọi màn — màn danh sách đơn giữ 1 cột trong `.card`.
- Thêm asset `logo.png`/`logo.svg` vào `public/` (nguồn từ `Logo.png` ở gốc repo) để header dùng. (Bộ icon PWA đầy đủ để ở S12.)

## Acceptance criteria

- [ ] Đăng nhập → mở được **mọi màn S1–S9** qua drawer và thanh tab; mỗi màn chạy đúng như trước (không mất chức năng).
- [ ] Drawer/tab-bar/trang chủ **chỉ hiện màn đúng quyền** theo vai trò `ThuKho`/`KeToan`/`Admin`; thứ tự màn sắp theo vai trò.
- [ ] Thanh tab dưới cùng hiện trên điện thoại với 4 màn + "Thêm"; nút "Thêm" mở drawer; tab active khớp màn hiện tại.
- [ ] FAB "lên đầu trang" hiện khi cuộn sâu; FAB/nút "quay lại" + nút back thiết bị trở về màn trước đúng.
- [ ] Header có logo + sticky blur; chuông hiện **badge số chưa đọc** và **panel** liệt kê cảnh báo, đánh dấu đã đọc cập nhật badge (dùng RPC S7, không thêm RPC).
- [ ] Nút lưu/submit chuyển "Đang xử lý…" và bị khoá khi chạy (`withBusy`); màn đang tải hiện spinner (`loadingText`); toast phân biệt màu thành công/lỗi.
- [ ] Chỗ nhập lý do (VD từ chối phiếu) dùng hộp nhập trong app (`promptReason`), không dùng `prompt()` trình duyệt.
- [ ] Ít nhất một màn dạng "form + kết quả" hiển thị 2 cột trên desktop và 1 cột trên điện thoại (`renderShell`).
- [ ] Màu/khoảng cách/bo góc/bóng đồng nhất giữa các màn (dùng tokens + component chung).
- [ ] Kiểm thử tĩnh qua: trích `<script>` → `node --check`; `node --check public/config.js`.
- [ ] QA 3 khổ (điện thoại 375px / tablet 768px / desktop ≥1200px) đạt.

## Blocked by

- None — có thể bắt đầu ngay (S0–S9 đã build).
