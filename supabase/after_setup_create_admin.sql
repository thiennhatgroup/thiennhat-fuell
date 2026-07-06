-- ============================================================================
-- after_setup_create_admin.sql — CHẠY MỘT LẦN trong Supabase SQL Editor sau khi
-- đã tạo user Admin đầu tiên qua Authentication → Users (email + password =
-- 'tn-pin::<PIN>'). Thay 2 giá trị bên dưới rồi Run để gắn hồ sơ Admin.
-- ============================================================================
insert into profiles (id, email, name, role, status)
select u.id, u.email, 'Quản trị', 'Admin', 'Hoạt động'
from auth.users u
where u.email = 'REPLACE_ADMIN_EMAIL@example.com'
on conflict (id) do update set role = 'Admin', status = 'Hoạt động';
