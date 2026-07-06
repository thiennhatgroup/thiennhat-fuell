# PRD — Phần mềm Tồn kho Xăng dầu (Thiên Nhật)

> Trạng thái: **Ready for build** · Ngày: 2026-07-06 · Nguồn: grilling session + File nhap lieu xang dau_v11.xlsx + appscript code v22
> Không có issue tracker cấu hình → PRD lưu dạng file. Khi có tracker, publish với nhãn `ready-for-agent`.

## Problem Statement

Công ty đang quản lý xăng dầu (bơm cho xe, nhập về téc, tịnh téc khi cạn, theo dõi tồn, báo cáo tiêu hao tháng cho kế toán) trên một file Google Sheets + Apps Script phức tạp. Cách này có mấy điểm đau:

- Không kiểm soát được tính trung thực của số liệu thủ kho nhập: không có ảnh đồng hồ, không ai kiểm tra chéo.
- Google Sheets không hỗ trợ tốt việc thêm/bớt xe, phân quyền, quy trình duyệt, thông báo.
- Dễ sửa nhầm công thức/dữ liệu gốc; sheet khóa mật khẩu thủ công.
- Không có tồn kho thời gian thực có kiểm soát và cảnh báo đặt hàng.
- Thao tác trên điện thoại ngoài hiện trường kém.

## Solution

Xây một web app riêng (PWA) chạy trên Supabase + frontend tĩnh, **bám đúng khuôn kiến trúc & quy trình triển khai của app `thiennhat-supabase`**, tái hiện trung thực toàn bộ logic nghiệp vụ xăng dầu từ file Excel/Apps Script, và bổ sung những thứ Google Sheets không làm được:

- Thủ kho nhập **phiếu bơm** dạng card trên điện thoại, **bắt buộc chụp 2 ảnh** (đồng hồ trụ bơm + công-tơ-mét), lưu nháp trong ngày, **cuối ngày submit cả lô**.
- Một **thủ kho khác đối chiếu chéo** ảnh vs số liệu; phiếu được duyệt mới vào tồn kho, phiếu lệch bị trả về sửa.
- **Tồn kho thời gian thực** tính từ sổ cái, cảnh báo tồn thấp/đặt hàng, đẩy **push** lên điện thoại.
- **Thêm/bớt xe** (soft-delete giữ lịch sử).
- **Tịnh téc & kiểm kê** hợp nhất một cơ chế, phân bổ chênh lệch cho từng xe theo lít-trong-kỳ (giữ nguyên công thức cũ).
- **Báo cáo tháng** tái hiện từng sheet cũ 1-1, xem trên web + tải Excel.
- Thiết kế **sẵn-cho-OCR**: lưu ảnh gốc + trường giá trị máy đọc để phase sau bật AI OCR tự điền số, thủ kho chỉ check lại.

## Ubiquitous Language (Glossary)

| Thuật ngữ | Nghĩa |
|---|---|
| **Sổ cái** (ledger, `DATA_GOC`) | Bảng bút toán append-only, nguồn sự thật duy nhất. Mọi tồn kho/báo cáo *tính ra* từ đây, không ghi đè. |
| **Phiếu bơm** (BOM) | Một lần bơm/xuất dầu cho một xe/thiết bị. |
| **Phiếu nhập** (NHAP) | Một lần nhập dầu về téc từ nhà cung cấp. |
| **Téc** | Bồn chứa dầu (Téc 1, Téc 2, Téc 3, Téc cát nghiền...). Có sức chứa, reorder point, lead-time. |
| **Loại dầu** | DO 0.05S, DO, Dầu động cơ, Dầu thủy lực, Dầu cầu, Dầu số... |
| **Xe / Thiết bị** | Đối tượng tiêu thụ dầu, định danh bằng biển số. Có định mức bơm; có thể không có đồng hồ KM. |
| **Bơm ngoài** | Xe đổ dầu ở NCC/cây ngoài, KHÔNG lấy từ téc kho → không trừ tồn kho, nhưng tính vào tiêu hao xe. |
| **Tịnh téc** | Chốt chênh lệch sổ-thực-tế khi téc cạn: nhập tồn thực tế → tính tịnh âm/dương. |
| **Kiểm kê** (stock-take) | Nhập số đo thực tế bất kỳ lúc nào (không cần téc cạn); cùng cơ chế tịnh téc. |
| **Tịnh âm** | Hao hụt (sổ > thực tế) → cộng vào tiêu hao xe. |
| **Tịnh dương** | Dôi (thực tế > sổ) → trừ khỏi tiêu hao xe. |
| **Đối chiếu chéo** | Thủ kho thứ 2 (khác người nhập) kiểm tra ảnh vs số liệu, duyệt/từ chối từng phiếu. |
| **Đồng hồ bơm** | Mặt số trụ bơm hiển thị số lít. **Công-tơ-mét**: đồng hồ KM trên xe. |
| **Đã chốt** | Trạng thái kỳ tịnh/phiếu đã hoàn tất, được tính vào tồn/báo cáo. |

## User Stories

### Thủ kho — nhập liệu
1. Là thủ kho, tôi muốn đăng nhập bằng email + mã PIN ngắn, để vào app nhanh trên điện thoại.
2. Là thủ kho, tôi muốn tạo phiếu bơm dạng từng card (chọn xe → tự điền KM cũ → nhập số lít, KM mới → chụp ảnh), để thao tác một tay ngoài hiện trường.
3. Là thủ kho, tôi muốn hệ tự điền KM cũ bằng KM mới của lần bơm gần nhất của xe đó, để khỏi tra lại.
4. Là thủ kho, tôi muốn hệ tự tính KM đi = KM mới − KM cũ và cảnh báo (không chặn) khi KM lùi hoặc bất thường, để phát hiện nhập sai.
5. Là thủ kho, tôi muốn để trống KM cho thiết bị không có đồng hồ, mà vẫn lưu được phiếu.
6. Là thủ kho, tôi muốn bắt buộc đính kèm 2 ảnh mỗi phiếu bơm (đồng hồ trụ bơm + công-tơ-mét), để làm bằng chứng.
7. Là thủ kho, tôi muốn hệ tự cấp số phiếu (BOM-2026-…), để khỏi tự nghĩ/nhớ số.
8. Là thủ kho, tôi muốn chọn loại giao dịch "Xuất nội bộ từ téc" hoặc "Bơm ngoài", để phản ánh đúng nguồn dầu.
9. Là thủ kho, tôi muốn tạo phiếu nhập dầu về téc (NCC, téc nhận, loại dầu, số lít, đơn giá, số HĐ NCC) và đính ảnh, để ghi nhận nhập kho.
10. Là thủ kho, tôi muốn mọi phiếu trong ngày ở trạng thái nháp và sửa/xóa thoải mái, để chỉnh trước khi chốt.
11. Là thủ kho, tôi muốn xem lại danh sách nháp của cả ngày (số liệu + ảnh) trước khi submit, để rà soát.
12. Là thủ kho, tôi muốn cuối ngày bấm "Submit ngày" để chốt cả lô phiếu, để gửi đi đối chiếu một lần.
13. Là thủ kho, tôi muốn sau khi submit thì phiếu bị khóa, và muốn sửa phải "Rút lại" (khi chưa được đối chiếu), để tránh sửa lén sau chốt.

### Thủ kho — đối chiếu chéo
14. Là thủ kho đối chiếu, tôi muốn thấy hàng đợi các lô phiếu chờ đối chiếu (của thủ kho khác), để biết việc cần làm.
15. Là thủ kho đối chiếu, tôi muốn xem danh sách phiếu gọn với số liệu hiện sẵn và mở ảnh khi cần, để duyệt nhanh.
16. Là thủ kho đối chiếu, tôi muốn bấm "Khớp → duyệt" hoặc "Lệch → trả về" kèm lý do cho từng phiếu, để xử lý độc lập từng phiếu.
17. Là thủ kho đối chiếu, tôi KHÔNG được duyệt phiếu do chính mình nhập, để đảm bảo kiểm tra chéo thật.
18. Là thủ kho, tôi muốn nhận thông báo khi phiếu của tôi bị trả về kèm lý do, để sửa và gửi lại.
19. Là thủ kho, tôi muốn phiếu được duyệt thì tự vào tồn kho/báo cáo, còn phiếu bị trả về thì quay lại nháp của tôi.

### Kế toán
20. Là kế toán, tôi muốn xem tồn kho thời gian thực theo từng téc/loại dầu (tồn đầu, nhập, xuất, tịnh, tồn cuối, %đầy), để nắm hiện trạng.
21. Là kế toán, tôi muốn thấy cảnh báo tồn thấp/dưới reorder point và tồn âm/vượt sức chứa, để đặt hàng kịp.
22. Là kế toán, tôi muốn nhập kỳ tịnh téc khi thủ kho báo téc cạn (téc, ngày bắt đầu/hết, tồn thực tế) và hệ tự tính tịnh âm/dương, để chốt hao hụt.
23. Là kế toán, tôi muốn nhập kiểm kê định kỳ (số đo thực tế bất kỳ lúc nào kể cả téc chưa cạn) và hệ tạo bút toán điều chỉnh, để giữ tồn khớp thực tế.
24. Là kế toán, tôi muốn tịnh âm/dương được phân bổ cho từng xe theo tỉ lệ lít bơm trong kỳ, để tiêu hao xe phản ánh cả hao hụt.
25. Là kế toán, tôi muốn xem báo cáo tiêu hao tháng theo từng xe (ma trận ngày 1–31, tổng, bơm ngoài, tịnh âm/dương, tổng tiêu hao, KM, L/100km) tái hiện đúng các sheet cũ, để đối chiếu quen thuộc.
26. Là kế toán, tôi muốn tải báo cáo tháng ra Excel giữ đúng layout cũ, để gửi/lưu như trước.
27. Là kế toán, tôi muốn quản danh mục: téc (sức chứa/reorder/lead-time), loại dầu, nhà cung cấp, loại giao dịch, để cập nhật khi phát sinh.
28. Là kế toán/admin, tôi muốn thêm xe mới (biển số + định mức bơm), để đưa xe mới vào hệ.
29. Là kế toán/admin, tôi muốn "ngừng hoạt động" một xe (soft-delete): ẩn khỏi dropdown nhập liệu nhưng giữ nguyên lịch sử/báo cáo, để loại xe cũ mà không mất số liệu.

### Admin
30. Là admin, tôi muốn tạo/sửa tài khoản người dùng (email + PIN + vai trò), để quản nhân sự.
31. Là admin, tôi muốn đặt lại PIN cho người dùng, để hỗ trợ khi quên.
32. Là admin, tôi có toàn quyền trên mọi màn hình và danh mục.

### Thông báo & nền tảng
33. Là người dùng, tôi muốn cài app lên màn hình chính điện thoại (PWA) và dùng camera để chụp ảnh, để thao tác hiện trường.
34. Là kế toán/admin, tôi muốn nhận push trên điện thoại khi có cảnh báo tồn thấp/reorder, kể cả khi đóng app.
35. Là người dùng, tôi muốn giao diện tiếng Việt, gọn, tối ưu điện thoại, đồng bộ phong cách với app mua hàng.

### Sẵn-cho-OCR (thiết kế V1, bật phase sau)
36. Là hệ thống, tôi muốn lưu ảnh gốc + (giá trị máy đọc, độ tin cậy, cờ "đã sửa tay") cho mỗi ảnh, để phase sau bật OCR không phải đổi schema.
37. Là thủ kho (phase OCR), tôi muốn hệ tự điền số lít (từ ảnh đồng hồ bơm) và KM mới (từ ảnh công-tơ-mét), tôi chỉ check lại rồi submit, để nhập nhanh hơn.

## Implementation Decisions

### Kiến trúc & triển khai
- Bám khuôn `thiennhat-supabase`: Postgres (Supabase) + **RLS deny-by-default**, mọi ghi qua **RPC `SECURITY DEFINER` + `require_permission()`**, `set search_path = public, pg_temp` trên mọi hàm SECURITY DEFINER.
- Frontend **một file tĩnh** `public/index.html` (PWA: manifest + service worker), supabase-js v2 qua CDN, `public/config.js` chứa URL + anon key. Host GitHub Pages qua nhánh `gh-pages`.
- Auth email + PIN: FE prefix PIN thành password `tn-pin::<pin>`.
- **Repo mới + Supabase project mới, riêng**, cùng org `thiennhatgroup`; deploy qua GitHub Actions (migrations theo thứ tự số + đẩy `public/` lên Pages). Không dùng chung project với app mua hàng.
- Migrations đánh số `NNNN_*.sql`, **không sửa migration cũ**; override RPC bằng migration mới (đúng convention thiennhat/AGENTS.md).
- **Online-only** (bỏ offline). Mạng ổn định.

### Vai trò & quyền
- Ba vai trò + Admin: `ThuKho`, `KeToan`, `Admin`. Bảng `role_permissions` + `has_permission()`/`require_permission()`.
- Đối chiếu chéo do **một `ThuKho` khác người nhập** thực hiện; chặn tự-duyệt ở tầng RPC (so khớp `created_by <> reviewer`).

### Mô hình dữ liệu (tương đương DATA_GOC nhưng chuẩn hóa)
- **Ledger** là nguồn sự thật; tồn kho là **view/RPC tính ra**, không ghi đè (bất biến — nguyên tắc cốt lõi kế thừa từ file cũ).
- Bảng cốt lõi (đặt tên tùy build, tránh path/snippet cụ thể): người dùng/hồ sơ, danh mục **téc** (sức chứa, reorder point, lead-time ngày), **loại dầu**, **nhà cung cấp**, **loại giao dịch**, **xe/thiết bị** (biển số, định mức bơm, cờ `active`), **phiếu bơm**, **phiếu nhập**, **ảnh chứng từ**, **kỳ tịnh/kiểm kê**, **phân bổ tịnh theo xe**, `code_counters`, `audit_log`, `notifications`, `push_subscriptions`.
- **Ảnh**: mỗi dòng phiếu bơm ≥ 2 ảnh có kiểu (`pump_meter`, `odometer`); phiếu nhập ≥ 1 ảnh (`receipt`). Lưu ở **Supabase Storage bucket riêng tư**, truy cập qua RPC/URL ký; chỉ ThuKho/KeToan/Admin xem. Ảnh KM bỏ được cho thiết bị không đồng hồ.
- Mỗi bản ghi ảnh có sẵn trường OCR: `ocr_value`, `ocr_confidence`, `manually_corrected` (bool) — V1 để trống, phase OCR ghi vào.

### Máy trạng thái phiếu bơm (từ prototype grilling)
Trạng thái: `Nhap` → (Submit ngày, cả lô) → `ChoDoiChieu` → `DaDuyet` | `TraVe`.
- `Nhap`: người tạo sửa/xóa tự do. Submit khóa cả lô ngày đó.
- `ChoDoiChieu`: khóa với người tạo; người tạo có thể **RútLại → Nhap** *chỉ khi chưa có ai đối chiếu*.
- Reviewer (ThuKho khác): **Khớp → DaDuyet** (ghi vào tồn kho/báo cáo) | **Lệch → TraVe** (kèm lý do, quay lại `Nhap` của người tạo, thông báo).
- Số phiếu (`SoPhieu`) do **server cấp lúc tạo/submit** qua `code_counters` (BOM-YYYY-######, NHAP-YYYY-######).
- Phiếu nhập (NHAP) đi qua cùng vòng đời + ảnh + đối chiếu như phiếu bơm.

### Tịnh téc & Kiểm kê (hợp nhất)
- Một thực thể "kỳ điều chỉnh": có `téc`, `ngày bắt đầu`, `ngày chốt`, `tồn thực tế`. Tịnh téc = kỳ kích hoạt khi téc cạn; Kiểm kê = kỳ nhập giữa chừng.
- Khi "Đã chốt": tính `tịnh âm/dương = |tồn sổ − tồn thực tế|` ở mức téc, rồi **phân bổ cho từng xe** đã bơm từ téc trong `[bắt đầu, chốt]` theo **tỉ lệ lít-trong-kỳ** (giữ nguyên 100% công thức cũ). Tịnh âm cộng, tịnh dương trừ vào tiêu hao xe.
- Do **KeToan** nhập & chốt; **không** qua vòng đối chiếu ThuKho.
- Lưu ý build: xử lý **làm tròn** phân bổ để tổng phân bổ khớp tuyệt đối tịnh âm/dương của kỳ (tránh lệch 1–2 lít do ROUND — hiện file cũ dùng ROUND từng dòng).

### Tồn kho & cảnh báo
- `Tồn cuối = Tồn đầu + Nhập − Xuất − Tịnh âm + Tịnh dương` theo từng téc/loại dầu, tính bằng RPC/view từ ledger + kỳ đã chốt.
- Tồn đầu gốc seed **một lần** tại mốc 1/1/2026 cho từng téc/loại dầu (lấy giá trị đo tay từ file cũ). Về sau tồn thoát ra thuần từ ledger + tịnh/kiểm kê.
- Cảnh báo: dưới reorder point, tồn âm, vượt sức chứa → tạo `notification` + đẩy **web push (VAPID)** cho KeToan/Admin.
- "Bơm ngoài": bút toán phiếu bơm với nguồn ngoài-téc → **không** trừ tồn kho téc; vào tiêu hao xe (cột bơm ngoài). NCC/đơn giá tùy chọn.

### Báo cáo
- **Tái hiện từng sheet cũ 1-1**: TIEU_HAO_DIESEL_1, TIEU_HAO_DIESEL_2, TONG_HOP_TEC, TONG HOP TIEU HAO — đủ mọi cột (ngày 1–31, tổng, bơm ngoài, tịnh âm/dương, tổng tiêu hao, KM, L/100km, điều chỉnh dư kỳ trước).
- Màn web chọn tháng/năm hiển thị báo cáo + nút **tải Excel .xlsx** giữ đúng layout để kế toán copy/gửi.
- Dữ liệu legacy nhập dạng **"đã chốt/legacy"** (miễn ảnh & đối chiếu) để báo cáo lịch sử khớp file Excel gốc.

### Migrate dữ liệu
- Nhập toàn bộ ~5.997 dòng DATA_GOC vào ledger, ánh xạ cột LoaiDuLieu/Ngay/DoiTuong/Tec_Nguon/LoaiGiaoDich/LoaiDau/SoLit/KM.../NhaCungCap/DonGia/ThanhTien, gắn cờ `legacy = true`, trạng thái `DaDuyet`.
- Seed danh mục từ DANH_MUC + `_TON_CAPACITY` + `_DM_BOM_BOM`.
- Nhập lịch sử kỳ tịnh từ TINH_TEC (các kỳ "Đã chốt").

## Testing Decisions

- **Thế nào là test tốt**: chỉ test **hành vi bên ngoài** ở ranh giới RPC (input → output/side-effect quan sát được), không test chi tiết cài đặt (tên cột nội bộ, thứ tự câu lệnh).
- **Seam** (một, cao nhất): **ranh giới RPC**. Mô phỏng luồng end-to-end bằng kịch bản SQL — prior art: `thiennhat-supabase/supabase/tests/ap_flow_simulation.sql`.
- **Module test**:
  - Máy trạng thái phiếu bơm: nháp → submit lô → đối chiếu duyệt/trả về → rút lại; chặn tự-duyệt; chỉ phiếu duyệt vào tồn.
  - Tồn kho: công thức Tồn cuối theo téc, seed tồn đầu, tồn âm/vượt sức chứa, bơm ngoài không trừ tồn.
  - Tịnh téc/kiểm kê: phân bổ theo lít-trong-kỳ + tổng phân bổ khớp tịnh âm/dương (kiểm tra làm tròn).
  - Báo cáo tháng: đối chiếu số liệu RPC với giá trị đã tính sẵn trong file Excel gốc (regression theo dữ liệu thật).
  - Quyền: mỗi RPC từ chối vai trò không đủ quyền (deny-by-default).
- **Kiểm thử tĩnh trong sandbox** (không có Supabase/psql/Deno live): SQL qua `pglast.parse_sql` + `parse_plpgsql`; frontend trích `<script>` rồi `node --check`. Cùng cách thiennhat đã dùng.
- **Verify migrate**: script so tổng lít nhập/xuất theo tháng/téc giữa ledger mới và file Excel gốc, log dòng lệch để duyệt tay.

## Out of Scope

- **OCR/AI đọc ảnh tự điền**: V1 chỉ thiết kế schema/luồng sẵn-cho-OCR; không tích hợp model OCR (phase sau).
- **Offline / đồng bộ khi mất mạng**: đã loại; app online-only.
- **Email tồn kho cuối ngày** và **thông báo nhắc đối chiếu riêng**: không làm (dùng tồn thời gian thực trên web + hàng đợi trong app).
- **Vai trò Thủ kho trưởng riêng**: gộp — bất kỳ ThuKho khác người nhập đều đối chiếu được.
- **Dùng chung Supabase project với app mua hàng**: không; project riêng.
- **Định dạng CSV/PDF cho báo cáo**: chỉ web + Excel.
- **Quản lý chi phí/công nợ NCC dầu**: ngoài phạm vi (đơn giá/thành tiền chỉ ghi nhận, không làm luồng thanh toán).

## Further Notes

- Cần chốt lúc build (không blocker): giá trị **tồn đầu gốc 1/1/2026** từng téc (đọc từ file), **tên miền** trang (vd `tonkho.thiennhatgroup.com`), **danh sách tài khoản** khởi tạo (thủ kho/kế toán thực tế), thông tin **VAPID** cho push.
- Rủi ro migrate: file cũ hard-code tồn đầu theo tháng Jan–May 2026 (đo tay) → khi chạy thuần ledger, tồn sổ tháng có thể lệch nhẹ với số đo tay; dùng bút toán kiểm kê để nắn khớp tại các mốc có số đo.
- Danh mục "Loại giao dịch" gồm: "Xuất nội bộ từ téc", "Bơm ngoài" (+ biến thể nguồn), "Nhập vào kho/téc".
- Giữ khái niệm "định mức bơm/xe" (`_DM_BOM_BOM`) phục vụ cột điều chỉnh trong báo cáo diesel.
