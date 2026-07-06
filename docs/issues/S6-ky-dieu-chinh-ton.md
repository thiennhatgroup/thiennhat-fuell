# S6 · Kỳ điều chỉnh tồn (Tịnh téc + Kiểm kê) + Phân bổ tịnh

## What to build
Một thực thể Kỳ điều chỉnh tồn dùng chung cho Tịnh téc (khi téc cạn) và Kiểm kê (giữa chừng): Téc, ngày bắt đầu, ngày chốt, tồn thực tế. Khi chốt: tính Tịnh âm/dương ở mức téc, rồi **Phân bổ tịnh** cho từng Xe đã bơm từ téc trong kỳ theo tỉ lệ lít-trong-kỳ (giữ nguyên 100% công thức cũ: Tịnh âm PB = Lít_xe × Tịnh_âm_kỳ / Tổng_lít_kỳ; tịnh dương tương tự). Do Kế toán nhập & chốt, không qua đối chiếu ThuKho. Xử lý làm tròn để tổng phân bổ khớp tuyệt đối tịnh âm/dương kỳ.

## Acceptance criteria
- [ ] Kế toán tạo kỳ (tịnh téc hoặc kiểm kê), nhập tồn thực tế, chốt → sinh tịnh âm/dương.
- [ ] Phân bổ tịnh cho đúng các Xe bơm trong kỳ theo tỉ lệ lít; tổng phân bổ = tịnh âm/dương kỳ (không lệch do làm tròn).
- [ ] Tịnh âm/dương phản ánh vào tồn kho (S5) và tiêu hao xe.
- [ ] Test: kịch bản 3 xe + hao hụt → phân bổ khớp, tổng khớp.

## Blocked by
- S5
