# Ubiquitous Language — Tồn kho Xăng dầu (Thiên Nhật)

Ngôn ngữ chung dùng thống nhất trong PRD, issue, schema và giao diện. Ưu tiên tiếng Việt; tên bảng/RPC tiếng Anh phái sinh từ đây.

## Sổ cái & chứng từ

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Sổ cái** | Bảng bút toán append-only là nguồn sự thật duy nhất; mọi tồn kho/báo cáo tính ra từ đây. | DATA_GOC, database gốc |
| **Bút toán** | Một dòng bất biến trong Sổ cái (một lần bơm, nhập, hoặc điều chỉnh). | record, dòng data |
| **Phiếu bơm** | Chứng từ một lần bơm/xuất dầu cho một Xe. | BOM, phiếu xuất |
| **Phiếu nhập** | Chứng từ một lần nhập dầu về Téc từ Nhà cung cấp. | NHAP |
| **Ảnh chứng từ** | Ảnh đính kèm phiếu; có kiểu: **Ảnh đồng hồ bơm**, **Ảnh công-tơ-mét**, **Ảnh phiếu nhập**. | ảnh đồng hồ (mơ hồ) |
| **Số phiếu** | Mã định danh chứng từ do hệ tự cấp (BOM-YYYY-######). Khác **Số HĐ NCC** nhập tay ở Phiếu nhập. | mã, số chứng từ |

## Tồn kho & điều chỉnh

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Tồn kho** | Số dư dầu theo Téc/Loại dầu, *tính ra* từ Sổ cái: Tồn đầu + Nhập − Xuất − Tịnh âm + Tịnh dương. | tồn |
| **Tồn đầu gốc** | Số dư seed một lần tại mốc khởi tạo (1/1/2026) cho mỗi Téc. | tồn đầu tháng |
| **Kỳ điều chỉnh tồn** | Một khoảng thời gian chốt chênh lệch sổ vs thực tế cho một Téc; cơ chế chung cho Tịnh téc và Kiểm kê. | — |
| **Tịnh téc** | Kỳ điều chỉnh tồn kích hoạt **khi téc cạn**. | — |
| **Kiểm kê** | Kỳ điều chỉnh tồn nhập giữa chừng (**téc chưa cạn**). | stock-take (giữ tiếng Việt) |
| **Tịnh âm** | Hao hụt (tồn sổ > thực tế) — cộng vào tiêu hao Xe. | hao hụt |
| **Tịnh dương** | Dôi (thực tế > tồn sổ) — trừ khỏi tiêu hao Xe. | dư |
| **Phân bổ tịnh** | Chia Tịnh âm/dương cho từng Xe theo tỉ lệ lít Xe bơm từ Téc trong kỳ. | — |
| **Reorder point** | Ngưỡng tồn Téc để cảnh báo đặt hàng. | mức tồn tối thiểu |

## Danh mục

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Téc** | Bồn chứa dầu; có sức chứa, reorder point, lead-time. | bồn, nguồn |
| **Loại dầu** | Chủng dầu (DO 0.05S, Dầu động cơ, thủy lực, cầu, số...). | — |
| **Xe** | Đối tượng tiêu thụ dầu, định danh bằng biển số; có Định mức bơm; có thể không có công-tơ-mét (thiết bị). | Đối tượng, DoiTuong, phương tiện |
| **Định mức bơm** | Hệ số tham chiếu mỗi Xe dùng trong điều chỉnh báo cáo. | định mức bom |
| **Loại giao dịch** | Bản chất bút toán bơm: **Xuất nội bộ từ téc**, **Bơm ngoài**, **Nhập vào kho/téc**. | — |
| **Bơm ngoài** | Xe đổ dầu ở NCC/cây ngoài — KHÔNG trừ Tồn kho téc, nhưng tính vào tiêu hao Xe. | đổ ngoài |
| **Nhà cung cấp** | Đơn vị bán dầu (cho Phiếu nhập / Bơm ngoài). | NCC |

## Con người & vai trò

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Thủ kho** | Người nhập Phiếu bơm/Phiếu nhập + chụp Ảnh chứng từ, và đối chiếu chéo phiếu của Thủ kho khác. | kho, storekeeper |
| **Thủ kho đối chiếu** | Thủ kho (khác người nhập) đang thực hiện Đối chiếu chéo một phiếu. | reviewer |
| **Kế toán** | Người xem/xuất báo cáo, chốt Kỳ điều chỉnh tồn, quản danh mục & Xe. | KeToan |
| **Admin** | Quản trị: toàn quyền + quản tài khoản. | — |
| **Đối chiếu chéo** | Bước Thủ kho đối chiếu so Ảnh chứng từ vs số liệu, duyệt/trả về từng phiếu. | kiểm tra chéo |

## Vòng đời phiếu bơm

| Term | Definition | Aliases to avoid |
| --- | --- | --- |
| **Nháp** | Phiếu người tạo còn sửa/xóa tự do trong ngày. | draft |
| **Submit ngày** | Hành động chốt cả lô phiếu Nháp của ngày → chuyển Chờ đối chiếu. | gửi |
| **Chờ đối chiếu** | Phiếu đã submit, khóa với người tạo, đợi Thủ kho đối chiếu. | pending |
| **Rút lại** | Người tạo đưa phiếu Chờ đối chiếu về Nháp (chỉ khi chưa ai đối chiếu). | withdraw |
| **Đã duyệt** | Phiếu Khớp → ghi vào Tồn kho/báo cáo. | approved |
| **Trả về** | Phiếu Lệch → quay lại Nháp của người tạo kèm lý do. | reject, bounce |
| **Legacy đã chốt** | Bút toán lịch sử migrate vào, miễn Ảnh & Đối chiếu, coi như Đã duyệt. | — |

## Relationships

- Một **Phiếu bơm** thuộc đúng một **Xe**, lấy dầu từ một **Téc** (trừ **Bơm ngoài** — không gắn Téc kho), một **Loại dầu**.
- Một **Phiếu bơm** có ≥ 2 **Ảnh chứng từ** (đồng hồ bơm + công-tơ-mét); **Phiếu nhập** có ≥ 1 (ảnh phiếu nhập).
- **Tồn kho** của một **Téc** = **Tồn đầu gốc** + Σ Nhập − Σ Xuất − Σ **Tịnh âm** + Σ **Tịnh dương** (chỉ tính bút toán Đã duyệt / Legacy đã chốt).
- Một **Kỳ điều chỉnh tồn** thuộc một **Téc**, sinh nhiều dòng **Phân bổ tịnh** cho các **Xe** bơm trong kỳ.
- **Đối chiếu chéo** một **Phiếu bơm** phải do một **Thủ kho** khác người tạo.

## Example dialogue

> **Dev:** "Khi **Thủ kho** bấm **Submit ngày**, phiếu vào **Tồn kho** luôn chưa?"
> **Domain expert:** "Chưa. Submit chỉ đưa phiếu sang **Chờ đối chiếu**. Phải một **Thủ kho đối chiếu** khác bấm Khớp → **Đã duyệt** thì mới cộng vào **Tồn kho**."
> **Dev:** "Nếu là **Bơm ngoài** thì sao?"
> **Domain expert:** "Vẫn qua **Đối chiếu chéo**, nhưng **Bơm ngoài** không trừ **Tồn kho** téc — nó chỉ vào tiêu hao **Xe** trong báo cáo."
> **Dev:** "Còn **Tịnh âm** từ một **Kỳ điều chỉnh tồn** — nó đụng tới **Xe** nào?"
> **Domain expert:** "Chia cho các **Xe** đã bơm từ **Téc** đó trong kỳ, theo tỉ lệ lít — đó là **Phân bổ tịnh**. **Tịnh téc** hay **Kiểm kê** đều chung cách này."

## Flagged ambiguities

- **"Ảnh đồng hồ"** mơ hồ: có hai đồng hồ khác nhau — **đồng hồ bơm** (số lít) và **công-tơ-mét** (KM). Luôn nói rõ loại **Ảnh chứng từ**.
- **"Tịnh téc" vs "Kiểm kê"**: đã hợp nhất thành **Kỳ điều chỉnh tồn**; Tịnh téc = trường hợp téc cạn, Kiểm kê = giữa chừng. Dùng "Kỳ điều chỉnh tồn" cho khái niệm chung.
- **"Xe" vs "Thiết bị"**: cùng là **Xe** (đối tượng tiêu thụ) trong ngôn ngữ chung; "thiết bị" chỉ là Xe không có công-tơ-mét (được phép trống KM). Tránh dùng **Đối tượng/DoiTuong**.
- **"Số phiếu"**: là **Số phiếu** do hệ tự cấp; KHÔNG lẫn với **Số HĐ NCC** nhập tay ở Phiếu nhập.
- **"Tồn đầu"**: dùng **Tồn đầu gốc** (seed 1 lần). Số đo tay giữa kỳ là **Kiểm kê**, không phải "tồn đầu tháng".
