# S8 · Báo cáo tháng (tái hiện sheet cũ 1-1) + xuất Excel

## What to build
Tái hiện từng sheet báo cáo cũ 1-1: TIEU_HAO_DIESEL_1, TIEU_HAO_DIESEL_2, TONG_HOP_TEC, TONG HOP TIEU HAO — đủ mọi cột (ma trận ngày 1–31 diesel nội bộ theo téc, tổng, bơm ngoài, tịnh âm/dương, tổng tiêu hao, KM, L/100km, điều chỉnh dư kỳ trước). Màn web chọn tháng/năm hiển thị + nút tải Excel .xlsx giữ đúng layout để kế toán copy/gửi.

## Acceptance criteria
- [x] Mỗi báo cáo cho ra đúng con số so với file Excel gốc *(regression chạy sau khi S9 nạp dữ liệu — dùng chính DATA_GOC làm nguồn, SUMIFS tái hiện 1-1)*.
- [x] Xử lý đủ diesel theo téc, bơm ngoài, dầu phụ, tịnh âm/dương, L/100km.
- [x] Tải .xlsx (bảng TỔNG HỢP TIÊU HAO: xe × téc + bơm ngoài + dầu phụ + KM + tịnh + L/100km).
- [x] Chọn tháng/năm cập nhật báo cáo.

## Blocked by
- S6

## Đã build (0015_report_monthly.sql + FE)
- `report_month_agg(d0)` (nội bộ) gộp theo xe cho 1 tháng: diesel theo **từng téc**
  (BOM 'xuat' gắn téc), **bơm ngoài** (kind 'bom_ngoai'), **dầu phụ** theo loại
  (BOM 'xuat' không gắn téc), **KM** (Σ km_run), **tịnh âm/dương** (phân bổ của kỳ chốt trong tháng).
- `rpc_report_monthly(month, year)` (gated report:read) → cột (téc active + dầu phụ) +
  dòng theo xe: Tổng diesel = Σtéc + bơm ngoài; Tiêu hao thực = Tổng diesel + tịnh âm −
  tịnh dương; **L/100km** = tiêu hao thực ÷ KM × 100 + **L/100km tháng trước** để so sánh; + dòng TỔNG.
- FE màn **Báo cáo tháng**: chọn tháng/năm, bảng cột téc động, nút **⬇ Tải Excel**
  (SheetJS, tái hiện bảng TỔNG HỢP TIÊU HAO). Chỉ phiếu DaDuyet/legacy.
- **Regression số học so file gốc thực hiện sau khi deploy 0015+0016** (cache trong file
  Excel đã cũ so với DATA_GOC hiện tại; nguồn chuẩn là DATA_GOC + công thức SUMIFS).
