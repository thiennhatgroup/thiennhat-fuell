# S6 · Kỳ điều chỉnh tồn (Tịnh téc + Kiểm kê) + Phân bổ tịnh

## What to build
Một thực thể Kỳ điều chỉnh tồn dùng chung cho Tịnh téc (khi téc cạn) và Kiểm kê (giữa chừng): Téc, ngày bắt đầu, ngày chốt, tồn thực tế. Khi chốt: tính Tịnh âm/dương ở mức téc, rồi **Phân bổ tịnh** cho từng Xe đã bơm từ téc trong kỳ theo tỉ lệ lít-trong-kỳ (giữ nguyên 100% công thức cũ: Tịnh âm PB = Lít_xe × Tịnh_âm_kỳ / Tổng_lít_kỳ; tịnh dương tương tự). Do Kế toán nhập & chốt, không qua đối chiếu ThuKho. Xử lý làm tròn để tổng phân bổ khớp tuyệt đối tịnh âm/dương kỳ.

## Acceptance criteria
- [x] Kế toán tạo kỳ (tịnh téc hoặc kiểm kê), nhập tồn thực tế, chốt → sinh tịnh âm/dương.
- [x] Phân bổ tịnh cho đúng các Xe bơm trong kỳ theo tỉ lệ lít; tổng phân bổ = tịnh âm/dương kỳ (không lệch do làm tròn).
- [x] Tịnh âm/dương phản ánh vào tồn kho (S5) và tiêu hao xe *(bảng phân bổ sẵn cho báo cáo S8)*.
- [x] Test: kịch bản 3 xe + hao hụt → phân bổ khớp, tổng khớp.

## Blocked by
- S5

## Đã build (0012_stock_period.sql + FE)
- Bảng `stock_period` (kỳ chung tịnh téc/kiểm kê) + `stock_period_alloc` (phân bổ/xe).
- Helper nội bộ `tank_book_before(tank, as_of)` = Tồn đầu + Nhập − Xuất − Σtịnh âm
  + Σtịnh dương (kỳ đã chốt). RPC `rpc_stock_period_create/update/delete/close/
  list/detail` (quyền `adjust:manage`, KeToan — KHÔNG qua đối chiếu).
- CHỐT: diff = book − thực tế → tịnh âm=max(diff,0)/dương=max(−diff,0); phân bổ
  `PB(xe)=lít_xe×tịnh/tổng_lít` (round 2 số, dồn dư vào xe lít lớn nhất → tổng khớp
  tuyệt đối); cấp Số kỳ `TINH-YYYY-######`.
- OVERRIDE `rpc_inventory_stock`: cộng −Σtịnh âm +Σtịnh dương (kỳ đã chốt) vào Tồn cuối.
- FE màn "Tịnh téc / Kiểm kê": tạo kỳ, danh sách, Chốt (nhập tồn thực tế), xem Phân bổ.
- Test `supabase/tests/stock_period_simulation.sql` (3 xe, tịnh âm 100, tổng khớp).
