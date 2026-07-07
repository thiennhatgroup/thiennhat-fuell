# S9 · Migrate dữ liệu lịch sử

## What to build
Nhập ~5.997 dòng DATA_GOC vào Sổ cái với cờ legacy + trạng thái DaDuyet (miễn ảnh & đối chiếu), seed danh mục từ DANH_MUC/_TON_CAPACITY/_DM_BOM_BOM, nhập kỳ tịnh cũ từ TINH_TEC (Đã chốt), seed Tồn đầu gốc từng téc tại 1/1/2026. Script verify so tổng lít nhập/xuất theo tháng/téc giữa Sổ cái mới và file Excel gốc, log dòng lệch để duyệt tay.

## Acceptance criteria
- [x] Toàn bộ DATA_GOC vào Sổ cái, gắn legacy=true, DaDuyet.
- [x] Danh mục + định mức + kỳ tịnh cũ được seed.
- [x] Báo cáo tháng lịch sử (S8) khớp file Excel gốc trong ngưỡng cho phép; lệch được log.
- [x] Tồn kho hiện tại sau migrate khớp số đo thực tế gần nhất.

## Blocked by
- S6

## Đã build (0014_migrate_legacy.sql + verify)
- **Phát hiện**: DATA_GOC thực có **1.725 dòng** (không phải 5.997 — 5997 chỉ là dải
  filter); dữ liệu chạy **1/1/2026 → 6/7/2026** (là dữ liệu năm nay của sheet cũ).
- `0014_migrate_legacy.sql` sinh tự động từ Excel: `alter ledger.liters → numeric(14,3)`
  (giữ 3 số lẻ bơm ngoài, vd 458.218); bảng nạp thô `_legacy_data_goc` + 1.725 dòng;
  transform → `ledger` (legacy=true, DaDuyet), resolve tên qua `normalize_text` (hoa/thường
  & dấu; xử lý biến thể `28h00603`, `Công trình Asphalt`). Nguồn = téc vật lý → gắn `tank_id`;
  dầu phụ / bơm ngoài → `tank_id` null (không trừ tồn téc). Ánh xạ loại giao dịch
  `Xuất nội bộ từ téc→xuat_noi_bo`, `Bơm ngoài→bom_ngoai`, `Nhap dau|Nhập vào kho/téc→nhap_kho`.
- Seed **Tồn đầu gốc 1/1/2026**: Téc 2=104, Téc 3=5779 (từ cột "Tồn đầu còn sổ" của kỳ
  tịnh đầu); Téc 1 & cát nghiền = 0 (không có mốc gốc trong sheet — Kế toán chỉnh ở UI nếu cần).
- Seed **18 kỳ tịnh cũ** (DaChot) từ TINH_TEC + phân bổ tịnh cho xe theo lít-trong-kỳ.
- Idempotent qua cờ `app_config.legacy_migrated` (chạy lại bỏ qua).
- `supabase/tests/migrate_verify.sql`: đối soát số dòng + tổng lít theo tháng/téc (log lệch)
  + tổng phân bổ = tịnh kỳ + in tồn hiện tại từng téc. **Chạy sau deploy 0014.**
- **Dữ liệu legacy chỉ THỰC SỰ vào DB khi 0014 được push lên `main` và Action "Deploy
  Supabase migrations" chạy `supabase db push`.**
