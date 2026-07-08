# Bộ kiểm thử luồng nghiệp vụ (QA "grill")

Kiểm thử **tất cả các luồng** của app theo đúng nghiệp vụ đã deploy (nhánh `s9-migrate-v2`,
migration tới `0031`). Mỗi file dán thẳng vào **Supabase SQL Editor** và bấm **Run**.

## Cách chạy & đọc kết quả

- Mỗi file tự chứa (self-contained): tạo user/danh mục giả → chạy các test → in **bảng điểm PASS/FAIL** → `rollback`.
- **Không để lại rác**: toàn bộ bọc trong `begin … rollback`. An toàn tuyệt đối với 1.738 dòng dữ liệu thật.
- Kết quả là **lưới (grid) cuối cùng**: cột `KQ` = `PASS`/`FAIL`, dòng đầu là **TỔNG n/m PASS**.
  Nếu SQL Editor chỉ hiện thông báo, xem tab **Results** cho lưới điểm; tab **Messages** cũng in tóm tắt.
- **Mốc pass/fail**: một test PASS khi hành vi thật của RPC khớp kỳ vọng nghiệp vụ ghi ở cột `Test`.
  Test "chặn …" PASS khi RPC **ném lỗi đúng lúc** (kiểm soát quyền/validate).

## Luồng nghiệp vụ được phản ánh (bám ĐÚNG code hiện tại `0023`)

> Lưu ý: code hiện tại **DUYỆT THẲNG** — Thủ kho Submit là phiếu vào tồn ngay
> (không còn đối chiếu chéo). Trưởng bộ phận/Kế toán **xem lại + gắn cờ nhờ Admin sửa**.
> Admin **sửa phiếu + gỡ cờ**. Đây là luồng được test, không phải chuỗi phê duyệt tuần tự.

| File | Luồng / feature | Vai trò chính |
| --- | --- | --- |
| `qa_00_roles_permissions.sql` | Ma trận quyền 4 vai trò (S0) | tất cả |
| `qa_01_catalog.sql` | Danh mục & Xe: CRUD, ngừng, xóa-có-chặn (S1, B5) | KeToan/TBP/Admin |
| `qa_02_pump_flow.sql` | Phiếu bơm: nháp→submit **auto-duyệt**, chặn thiếu ảnh, số phiếu theo ngày, bơm ngoài (S2,S3,B8) | ThuKho |
| `qa_03_nhap_flow.sql` | Phiếu nhập: nháp→submit **auto-duyệt**, chặn thiếu 2 ảnh, cộng tồn (S4,B3) | ThuKho |
| `qa_04_inventory.sql` | Công thức tồn kho + kẹp âm + chỉ tính DaDuyet/legacy (S5,B4) | KeToan |
| `qa_05_stock_period.sql` | Tịnh téc/Kiểm kê: chốt, phân bổ khớp tuyệt đối, biên bản bắt buộc, tồn=thực tế (S6) | KeToan/TBP |
| `qa_06_alerts.sql` | Cảnh báo tồn thấp/âm/vượt sức chứa + dedup + quyền (S7) | KeToan |
| `qa_07_flag_admin.sql` | Gắn cờ → Admin sửa → gỡ cờ + audit + chặn không-Admin (B6,B8) | TBP/KeToan/Admin |
| `qa_08_e2e_full_flow.sql` | **Luồng đầy đủ**: ThuKho→(tồn)→KeToan→TBP gắn cờ→Admin sửa→báo cáo | cả 4 vai trò |
| `qa_09_reconcile_report_REAL.sql` | **Đối soát báo cáo tháng vs Excel v11** trên DỮ LIỆU THẬT (chỉ đọc) | Admin tạm |

## Thứ tự khuyến nghị

Chạy `qa_00` → `qa_08` trước (dữ liệu giả, roll back). Cuối cùng `qa_09` (đọc dữ liệu thật).

## Nếu `qa_09` FAIL

`qa_09` so tổng báo cáo với số cộng tay từ `DATA_GOC` (sheet gốc). Lệch có thể là **phát hiện thật**:
- Xe bị **ngừng** (`active=false`) sẽ bị loại khỏi báo cáo nhưng vẫn có trong Excel → thiếu lít.
- Dòng migrate không khớp téc (tank_id null) sẽ nhảy cột diesel↔dầu phụ.
Cột `Chi tiết` in cả **kỳ vọng vs thực tế** để dò điểm lệch.
