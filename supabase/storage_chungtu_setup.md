# Storage setup — bucket `chung-tu` (ảnh chứng từ, S3)

**Làm MỘT LẦN qua Supabase Dashboard.** Không đặt trong migration vì vai trò chạy
`supabase db push` (postgres) không sở hữu `storage.objects` → `create policy` sẽ lỗi
`must be owner of table objects` và làm hỏng toàn bộ push.

Migration `0008_pump_photos.sql` đã tạo sẵn 2 helper `public.chungtu_can_read()` và
`public.chungtu_can_upload()` — các policy dưới đây chỉ việc gọi chúng.

## 1. Tạo bucket riêng tư
Dashboard → **Storage** → **New bucket**:
- Name: `chung-tu`
- **Public bucket: TẮT** (riêng tư — chỉ truy cập qua URL ký).
- Create.

## 2. Tạo 3 policy cho bucket
Dashboard → **Storage** → **Policies** → chọn bucket `chung-tu` → **New policy** →
**For full customization** (dán trực tiếp biểu thức). Target roles: `authenticated`.

| Policy name       | Allowed operation | USING / WITH CHECK expression |
|-------------------|-------------------|-------------------------------|
| `chungtu_read`    | SELECT            | `bucket_id = 'chung-tu' AND public.chungtu_can_read()` |
| `chungtu_insert`  | INSERT            | `bucket_id = 'chung-tu' AND public.chungtu_can_upload()` |
| `chungtu_delete`  | DELETE            | `bucket_id = 'chung-tu' AND public.chungtu_can_upload()` |

> SELECT/DELETE dùng ô **USING**; INSERT dùng ô **WITH CHECK**. Nếu UI gộp thì điền
> cùng biểu thức. Không cần UPDATE.

## 3. Kiểm tra
- Đăng nhập ThuKho → màn **Nhập bơm** → tạo phiếu → chụp/tải ảnh → phải upload được.
- Đăng nhập tài khoản KHÔNG có quyền `pump:create` (KeToan) → xem được ảnh (đối chiếu
  không dùng, nhưng URL ký mở được) nhưng không upload được.
- Người ngoài (không đăng nhập) → không mở được object (bucket riêng tư).

## Cách khác (nâng cao): chạy SQL bằng vai trò storage admin
Nếu muốn tạo bằng SQL Editor, phải chạy dưới `supabase_storage_admin`:
```sql
insert into storage.buckets (id, name, public) values ('chung-tu','chung-tu',false)
  on conflict (id) do nothing;
-- rồi tạo policy như bảng trên (create policy ... on storage.objects ...)
```
Nhưng cách Dashboard ở trên đơn giản và chắc chắn hơn — ưu tiên dùng nó.
