# S5 · Tồn kho thời gian thực

## What to build
RPC/view tính Tồn kho từ Sổ cái theo từng Téc/Loại dầu: `Tồn cuối = Tồn đầu gốc + Nhập − Xuất − Tịnh âm + Tịnh dương` (chỉ bút toán DaDuyet/legacy). Seed Tồn đầu gốc một lần tại mốc khởi tạo. **Bơm ngoài** không trừ tồn téc. KM cũ tự điền = KM mới lần bơm gần nhất của Xe; tự tính KM đi; cảnh báo (không chặn) khi KM lùi/bất thường; KM để trống được. Màn tồn kho: tồn đầu/nhập/xuất/tịnh/tồn cuối, %đầy theo sức chứa.

## Acceptance criteria
- [ ] Tồn cuối mỗi Téc đúng công thức, cập nhật ngay khi phiếu DaDuyet.
- [ ] Bơm ngoài không làm đổi tồn kho téc.
- [ ] KM cũ auto-fill từ lần bơm trước; cảnh báo khi KM mới < KM cũ; vẫn lưu được KM trống.
- [ ] Màn tồn kho hiện %đầy + tồn âm/vượt sức chứa được đánh dấu.
- [ ] Test: seed tồn đầu + chuỗi nhập/xuất/bơm-ngoài cho ra tồn cuối kỳ vọng.

## Blocked by
- S4
