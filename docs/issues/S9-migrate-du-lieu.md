# S9 · Migrate dữ liệu lịch sử

## What to build
Nhập ~5.997 dòng DATA_GOC vào Sổ cái với cờ legacy + trạng thái DaDuyet (miễn ảnh & đối chiếu), seed danh mục từ DANH_MUC/_TON_CAPACITY/_DM_BOM_BOM, nhập kỳ tịnh cũ từ TINH_TEC (Đã chốt), seed Tồn đầu gốc từng téc tại 1/1/2026. Script verify so tổng lít nhập/xuất theo tháng/téc giữa Sổ cái mới và file Excel gốc, log dòng lệch để duyệt tay.

## Acceptance criteria
- [ ] Toàn bộ DATA_GOC vào Sổ cái, gắn legacy=true, DaDuyet.
- [ ] Danh mục + định mức + kỳ tịnh cũ được seed.
- [ ] Báo cáo tháng lịch sử (S8) khớp file Excel gốc trong ngưỡng cho phép; lệch được log.
- [ ] Tồn kho hiện tại sau migrate khớp số đo thực tế gần nhất.

## Blocked by
- S6
