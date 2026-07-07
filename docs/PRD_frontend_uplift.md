# PRD — Nâng cấp kiến trúc & giao diện Frontend (đồng bộ khuôn `thiennhat-supabase`)

> Trạng thái: **Ready for build** · Ngày: 2026-07-07 · Nguồn: review sâu FE app tham chiếu *Mua hàng & Công nợ* (`thiennhat-supabase/public/index.html`) đối chiếu FE hiện tại *Tồn kho Xăng dầu* (`public/index.html`).
> Không có issue tracker cấu hình → PRD lưu dạng file (theo quy ước dự án). Khi có tracker, publish với nhãn `ready-for-agent`.
> Phạm vi: **CHỈ frontend** (shell điều hướng + design system + PWA polish). **KHÔNG đụng backend/RPC**, không đổi hợp đồng dữ liệu, không đổi nghiệp vụ S1–S9.

---

## Problem Statement

Hai app dùng chung một khuôn kiến trúc (single-file SPA, cùng `call()` RPC wrapper, cùng login email+PIN `tn-pin::`, cùng `rpc_bootstrap → state → SCREENS → renderScreen`), do cùng tác giả port từ Apps Script. Nhưng phần **nhìn & vỏ điều hướng** của app *Tồn kho Xăng dầu* mới chỉ là bản "mỏng":

- Điều hướng chỉ có **một dải nút pill cuộn ngang** trên đầu — không có menu ngăn kéo (drawer) theo vai trò, không có thanh tab dưới cùng cho điện thoại, không nút "về đầu trang"/"quay lại". Người dùng hiện trường (thủ kho) thao tác trên điện thoại thấy rối khi số màn tăng.
- **Bảng dữ liệu tràn ngang** trên điện thoại (cuộn ngang khó đọc) — app tham chiếu tự xếp bảng thành thẻ dọc.
- **Thiếu bộ component thống nhất**: thẻ số liệu (metric/totals), nhãn trạng thái (pill ok/warn/err), thẻ duyệt (approve-card), khung thông báo (notice), spinner khi tải, nút "đang xử lý". Mỗi màn tự chế → thiếu nhất quán, khó bảo trì.
- **Header sơ sài**: tiêu đề chữ, không logo thương hiệu, không hiệu ứng dính-mờ (sticky blur) như bản tham chiếu; chuông cảnh báo là nút trơ chưa có panel.
- **PWA chưa hoàn chỉnh**: manifest không có icon (mảng rỗng), không maskable/apple icon, không logo → cài lên màn hình chính điện thoại xấu; service worker đơn giản.

Hệ quả: cùng một hệ sinh thái phần mềm của công ty nhưng hai app **nhìn khác nhau**, và app xăng dầu **kém thân thiện trên điện thoại** — đúng nơi thủ kho dùng nhiều nhất.

## Solution

Nâng vỏ FE của *Tồn kho Xăng dầu* lên **đúng kiến trúc trình bày & cảm quan (look-and-feel) của `thiennhat-supabase`**, giữ nguyên toàn bộ logic/nghiệp vụ S1–S9 và lớp gọi RPC. Cụ thể, port các phần **thuần trình bày** sang app xăng dầu:

- **Design tokens đầy đủ**: bổ sung `--accent-dark`, `--accent-soft`, `--orange`, `--ok`, `--danger`, `--shadow`, `--input` cho đồng bộ màu/bóng.
- **Header dính, nền mờ (backdrop blur)** + logo thương hiệu + chuông cảnh báo có **panel thông báo** (tái dùng dữ liệu S7 đã có).
- **Điều hướng 2 tầng**: (1) **drawer hamburger** — danh sách màn theo vai trò, đánh số, nhóm gập được; (2) **thanh tab dưới cùng** trên điện thoại — 4 màn hàng đầu theo vai trò + nút "Thêm" mở drawer; kèm **FAB "quay lại"** và **FAB "lên đầu trang"**.
- **Khuôn workspace 2 cột** (`renderShell`) cho các màn dạng "form + dữ liệu gần đây/kết quả" (áp dụng nơi phù hợp: Tồn kho, Báo cáo, Đối chiếu…), tự co về 1 cột trên điện thoại.
- **Bộ component dùng chung**: `.metric`/`.totals` (thẻ số), `.pill` (ok/warn/err), `.approve-card`, `.notice` (ok/err/warn), `.loading-line`+`.spin`, helper `withBusy()` (nút "đang xử lý…"), `loadingText()`.
- **Tự xếp bảng thành thẻ trên điện thoại** qua `labelTableCells()` (gắn `data-label` từ `<th>`) + `MutationObserver` theo dõi vùng nội dung, cộng CSS reflow ở breakpoint hẹp; bảng nhập liệu (`.line-table`) xếp dọc, ô nhập full-width.
- **Modal giàu hơn**: `openModal()` + `promptReason()` (hộp nhập lý do thay `prompt()` — thân thiện điện thoại) thay thế modal cơ bản hiện tại.
- **PWA polish**: bổ sung icon 192/512 + maskable + apple-touch-icon + logo, hoàn thiện `manifest.webmanifest`, meta apple/mobile, và service worker network-first (giữ hành vi push S7).

Kết quả kỳ vọng: hai app **nhìn như một bộ**, app xăng dầu **dễ dùng trên điện thoại**, và FE có **từ vựng component thống nhất** để các slice sau tái dùng.

## User Stories

1. Là thủ kho dùng điện thoại ngoài hiện trường, tôi muốn có **thanh tab dưới cùng** với 4 màn tôi hay dùng (Nhập bơm, Đối chiếu, Tồn kho, Cảnh báo…), để chuyển màn bằng ngón cái mà không phải cuộn dải nút trên đầu.
2. Là thủ kho, tôi muốn nút **"Thêm"** trên thanh tab mở **drawer** đầy đủ các màn còn lại, để vẫn tới được mọi chức năng được cấp quyền.
3. Là người dùng bất kỳ, tôi muốn **drawer liệt kê màn theo vai trò, có đánh số và nhóm gập được**, để tìm nhanh việc mình cần theo đúng thứ tự công việc.
4. Là người dùng trên điện thoại, tôi muốn **bảng dữ liệu tự xếp thành thẻ dọc** (mỗi ô có nhãn cột), để đọc số liệu tồn kho/báo cáo mà không phải cuộn ngang.
5. Là người dùng nhập liệu, tôi muốn **bảng nhập (dòng phiếu bơm/nhập) xếp dọc, ô nhập chiếm nguyên chiều ngang** trên điện thoại, để bấm nhập chính xác hơn.
6. Là người dùng, tôi muốn **header dính trên đầu, có logo và hiệu ứng mờ**, để luôn thấy thương hiệu và thao tác nhanh (chuông, đăng xuất) khi cuộn dài.
7. Là Kế toán/Admin, tôi muốn **chuông cảnh báo có badge số chưa đọc và panel danh sách** (dữ liệu S7 sẵn có), để xem/đánh dấu đã đọc cảnh báo tồn ngay trên header.
8. Là người dùng, tôi muốn thấy **spinner + chữ "Đang tải…"** khi màn đang lấy dữ liệu, để biết hệ thống đang chạy chứ không đứng hình.
9. Là người dùng, tôi muốn **nút chuyển sang trạng thái "Đang xử lý…" và bị khoá** khi tôi bấm lưu/submit, để không bấm hai lần gây trùng.
10. Là người dùng, tôi muốn **thông báo dạng toast** phân biệt màu thành công/lỗi, để nhận phản hồi rõ ràng sau mỗi thao tác.
11. Là người dùng trên điện thoại, tôi muốn **nút "lên đầu trang"** xuất hiện khi cuộn sâu, để về đầu màn nhanh.
12. Là người dùng, tôi muốn **nút "quay lại"** khi đã đi sâu vào một màn/chi tiết, để trở lại màn trước mà không mất ngữ cảnh.
13. Là người dùng, tôi muốn **thẻ số liệu (metric)** hiển thị các con số chính (VD tổng tồn, số téc dưới điểm đặt hàng), để nắm nhanh tình hình đầu màn.
14. Là người xem Tồn kho, tôi muốn các cờ trạng thái (Tồn âm/Vượt sức chứa/Dưới điểm đặt hàng) hiển thị dạng **pill màu** nhất quán, để nhận diện rủi ro tức thì.
15. Là người dùng, tôi muốn khi được yêu cầu **nhập lý do** (VD từ chối phiếu khi đối chiếu) thì hiện **hộp nhập trong app** (không phải `prompt()` trình duyệt), để nhập thoải mái trên điện thoại.
16. Là người dùng, tôi muốn **màn dạng "form + kết quả/dữ liệu gần đây" xếp 2 cột trên máy tính và 1 cột trên điện thoại**, để tận dụng màn rộng mà vẫn gọn trên màn hẹp.
17. Là người cài app lên điện thoại, tôi muốn **icon app đẹp (maskable/apple) và tên rút gọn**, để biểu tượng trên màn hình chính chuyên nghiệp.
18. Là người dùng đã cấp quyền một số màn nhất định, tôi muốn **drawer, thanh tab và trang chủ chỉ hiện đúng màn tôi được phép** (không lộ chức năng ngoài quyền), để giao diện gọn theo vai trò.
19. Là Admin, tôi muốn **thứ tự màn trong drawer/tab sắp theo vai trò** (ThuKho ưu tiên nhập bơm/đối chiếu; KeToan ưu tiên tồn kho/báo cáo/tịnh téc), để mỗi vai trò thấy việc chính lên đầu.
20. Là người dùng cũ, tôi muốn **mọi màn S1–S9 hiện có vẫn chạy y như trước** sau khi đổi giao diện, để không mất chức năng nào.
21. Là người dùng, tôi muốn **màu sắc, khoảng cách, bo góc, bóng đổ đồng nhất** giữa các màn, để cảm giác app liền mạch như app Mua hàng.
22. Là người dùng mở app lúc mạng chập chờn, tôi muốn **service worker phục vụ vỏ app từ cache** (network-first), để app vẫn mở được và cập nhật khi có mạng.
23. Là người dùng nhận cảnh báo đẩy (push), tôi muốn **bấm vào thông báo mở đúng màn Cảnh báo**, để xử lý ngay (giữ hành vi S7).
24. Là người dùng máy tính, tôi muốn drawer đóng lại khi tôi chọn một màn hoặc bấm nền mờ, để không che nội dung.

## Implementation Decisions

**Kiến trúc giữ nguyên (không đổi):**
- Giữ nguyên single-file `public/index.html`, `call(name, params)` (timeout 45s, unwrap `{ok:false}`), `login()`/`mapAuthError()`/`bootstrap()`, object `state`, mảng `SCREENS` (id, nhãn, quyền, slice), `can()`/`visibleScreens()`, và **mọi hàm `renderXxx(el)` của S1–S9**. Đây là **hợp đồng seam**: mỗi màn vẫn nhận một phần tử container và tự render vào đó.
- KHÔNG đổi backend/RPC, không đổi schema, không đổi tên/hợp đồng RPC. Không đổi luồng đăng nhập, phân quyền server (`require_permission()` vẫn là chốt chặn cuối).

**Seam nâng cấp (một seam duy nhất — lớp vỏ/shell):**
- Thay `renderNav()` (dải pill) bằng bộ shell: `renderDrawer()` + `renderTabBar()` + `updateTabActive()` + `navTo(id)` + FAB back/to-top. `renderScreen()` giữ vai trò dispatch tới `renderXxx(el)` như cũ; container render đổi tên/khung nhưng **giữ nghĩa "vùng nội dung màn hiện tại"**.
- **Điều hướng theo vai trò**: bổ sung bảng thứ tự màn theo vai trò (tương tự `ROLE_MENU_ORDER`/`orderScreensForRole` bên tham chiếu) cho `ThuKho`/`KeToan`/`Admin`; drawer đánh số + nhóm gập; tab-bar lấy 4 màn đầu theo thứ tự vai trò + nút "Thêm".
- **Lịch sử điều hướng nhẹ**: `navTo` dùng `history.pushState`/`popstate` để nút "quay lại" và nút back thiết bị hoạt động (mức đơn giản như bản tham chiếu), không thêm router ngoài.

**Design system (thuần CSS + helper trình bày):**
- Bổ sung tokens: `--accent-dark`, `--accent-soft`, `--orange`, `--ok`, `--danger`, `--shadow`, `--input` (đồng bộ giá trị với bản tham chiếu; `--accent` giữ `#0E5AA7`).
- Component classes: `.metric`/`.totals`, `.pill` (+ `.ok/.warn/.err`), `.approve-card`, `.notice` (+ `.ok/.err`), `.loading-line`/`.spin`, `.drawer`/`.drawer-item`/`.drawer-group`, `.tabbar`/`.tab`, `.to-top`, `.back-fab`, `.workspace`, `.card`.
- Helper trình bày: `withBusy(btn, label, fn)`, `loadingText(text)`, `openModal()`/`closeModal()`/`modalErr()`/`promptReason()`, `labelTableCells(root)` + `MutationObserver` trên vùng nội dung để auto gắn `data-label` khi bảng mới render, `jumpTo(id)`, init FAB scroll.
- **Mobile reflow**: media query xếp `table:not(.line-table)` thành thẻ (dùng `data-label`), `.line-table` xếp dọc ô nhập full-width; workspace/grid co về 1 cột.

**Header + thông báo:**
- Header: logo (png + fallback svg), hiệu ứng sticky blur; chuông tái dùng RPC S7 (`rpc_alerts_list`/`rpc_alerts_mark_read`) render `.notif-panel` + badge chưa đọc. (Không tạo RPC mới; chỉ chuyển phần chuông hiện có sang panel giàu hơn.)

**PWA:**
- Thêm asset icon `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `logo.png`/`logo.svg` vào `public/` (dùng `Logo.png` sẵn có ở gốc repo làm nguồn); hoàn thiện `manifest.webmanifest` (name/short_name/icons/maskable/theme) và meta apple/mobile trong `<head>`.
- Service worker: network-first cho origin, bỏ qua request Supabase/CDN, giữ nguyên handler `push`/`notificationclick` của S7.

**Quyết định về áp dụng `renderShell` (khuôn 2 cột):** không ép mọi màn. Áp dụng cho màn có "form + phụ trợ" rõ ràng; các màn danh sách/bảng đơn giữ 1 cột trong `.card`. Danh sách màn áp dụng cụ thể để lại cho khâu build quyết theo từng màn, miễn giữ hành vi cũ.

## Testing Decisions

- **Nguyên tắc**: test hành vi bên ngoài, không test chi tiết nội bộ. Với FE một-file không có test-runner, "test" gồm kiểm thử tĩnh + QA thủ công theo checklist hành vi quan sát được (đúng thông lệ đã dùng ở S1–S9).
- **Kiểm thử tĩnh (bắt buộc, chạy được trong sandbox)**: trích `<script>` từ `public/index.html` rồi `node --check`; `node --check public/config.js`. Phải pass trước khi commit (theo AGENTS.md).
- **QA hồi quy chức năng (thủ công, sau deploy FE)**: với mỗi màn S1–S9, xác nhận **vẫn chạy đúng như trước** (nhập bơm/đối chiếu/nhập/tồn kho/tịnh téc/cảnh báo/báo cáo/danh mục/tài khoản) — vì seam giữ nguyên hợp đồng `renderXxx(el)`, đây là điểm gãy rủi ro nhất.
- **QA vỏ điều hướng**: drawer/tab-bar chỉ hiện màn đúng quyền theo vai trò (ThuKho/KeToan/Admin); nút "Thêm" mở drawer; back/to-top hiện đúng lúc; drawer đóng khi chọn màn/bấm nền.
- **QA đa thiết bị (đúng-nhìn)**: chụp/kiểm ở 3 khổ (điện thoại 375px, tablet 768px, desktop ≥1200px): bảng tự xếp thẻ trên điện thoại; workspace co 1 cột; toast/pill/metric/notice hiển thị đúng màu; chuông panel mở/đóng.
- **QA PWA**: manifest hợp lệ (icon không rỗng), cài lên màn hình chính điện thoại thấy icon đẹp; SW network-first phục vụ vỏ khi offline; bấm push mở màn Cảnh báo (giữ S7).
- **Prior art**: cùng phong cách kiểm thử tĩnh + mô phỏng đã dùng ở `supabase/tests/*` (SQL) và quy ước `node --check` FE trong AGENTS.md; QA thủ công như các slice trước.

## Out of Scope

- **Mọi thay đổi backend/RPC/schema/nghiệp vụ.** Không thêm/sửa migration, không đổi hợp đồng RPC, không đổi công thức tồn kho/tịnh téc/báo cáo.
- **Không thêm màn nghiệp vụ mới** ngoài S1–S9 (không port màn chat, in ấn, dashboard điều hành… của app Mua hàng — chúng thuộc nghiệp vụ khác).
- Không đổi luồng đăng nhập/phân quyền server.
- Không thêm framework FE (giữ vanilla single-file). Không thêm bundler/build step.
- Không làm OCR (vẫn để phase sau như PRD gốc).
- Không thay đổi hành vi push/VAPID của S7 (chỉ tái dùng cho panel chuông).

## Further Notes

- **Nguồn sự thật thiết kế** là chính `thiennhat-supabase/public/index.html` (không phải `REDESIGN_PROPOSAL.md` — tài liệu đó nói về mô hình dữ liệu app Mua hàng, không liên quan xăng dầu).
- **Bảng đối chiếu khoảng trống (gap)** đã lập trong review: target hiện thiếu `drawer/tabbar/labelTableCells/data-label/metric/pill/withBusy/renderShell/to-top/back-fab/loadingText/spin/refreshNotif` (đều =0), chỉ có sẵn `toast`, `closeModal` cơ bản, `totals` (2 lần). Đây là danh mục cần bù.
- **Rủi ro chính**: đổi vỏ có thể vô tình đổi cây DOM mà một số `renderXxx(el)` phụ thuộc (id container, class). Giảm rủi ro bằng cách giữ đúng id/khung container mà các hàm màn đang ghi vào, đổi trang trí quanh chúng.
- **Đề nghị build theo lát nhỏ** (đúng văn hoá dự án): (a) tokens + component CSS + toast/notice/pill/metric; (b) shell drawer+tabbar+FAB+role-order thay pill-nav; (c) labelTableCells + mobile reflow; (d) header logo + notif panel; (e) PWA assets/manifest/SW; (f) openModal/promptReason + áp renderShell nơi phù hợp. Mỗi lát: `node --check` + QA rồi commit riêng.
- Giữ chuỗi triển khai hiện có: push `main` → Actions deploy `public/` lên `gh-pages`. Không cần secrets mới.
