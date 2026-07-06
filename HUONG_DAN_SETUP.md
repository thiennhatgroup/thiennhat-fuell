# Hướng dẫn set up GitHub + Supabase (cho người mới)

Làm lần lượt từng chặng. Xong chặng nào báo mình con số/đường link tương ứng.

## Chặng 1 — Tạo GitHub repo (trống) cho app xăng dầu

1. Vào https://github.com → đăng nhập tài khoản có quyền trong tổ chức **thiennhatgroup**.
2. Góc trên phải bấm dấu **+** → **New repository**.
3. Điền:
   - **Owner**: chọn **thiennhatgroup** (không phải tài khoản cá nhân).
   - **Repository name**: `thiennhat-fuel`
   - **Description**: `Phần mềm tồn kho xăng dầu`
   - Chọn **Private**.
   - **QUAN TRỌNG**: KHÔNG tích "Add a README", KHÔNG chọn .gitignore, KHÔNG chọn license. Để repo **trống hoàn toàn** (để liên kết với folder có sẵn không bị xung đột).
4. Bấm **Create repository**.
5. Copy đường link repo (dạng `https://github.com/thiennhatgroup/thiennhat-fuel`).

### Liên kết repo với folder project (GitHub Desktop)
6. Mở **GitHub Desktop**.
7. Menu **File → Add Local Repository…**
8. Bấm **Choose…**, trỏ tới folder **Phần mềm tồn kho xăng dầu** (folder đang chứa file này).
9. Nếu báo "this directory is not a Git repository", bấm **create a repository** → **Create Repository**.
10. Khoan push vội — mình sẽ dựng khung code trước, rồi bạn mới commit/push.

## Chặng 2 — Tạo Supabase project mới

1. Vào https://supabase.com → **Sign in** (GitHub cũng được).
2. Bấm **New project**.
   - **Organization**: chọn tổ chức của bạn (tạo mới nếu chưa có).
   - **Name**: `thiennhat-fuel`
   - **Database Password**: bấm **Generate a password** → **lưu lại chỗ an toàn** (cần khi deploy).
   - **Region**: chọn **Southeast Asia (Singapore)**.
3. Bấm **Create new project**, đợi ~2 phút.
4. Vào **Project Settings (bánh răng) → API**, copy 3 thứ gửi mình:
   - **Project URL** (dạng `https://xxxxxxxx.supabase.co`).
   - **anon public** key (khóa dài, an toàn để nhúng frontend).
   - **Project ref** (đoạn `xxxxxxxx` trong URL).
   - (KHÔNG gửi service_role key ở đây.)

## Chặng 3 — Token để mình đẩy 10 issue lên GitHub

Mình cần một "chìa khóa" giới hạn để tạo issue giúp bạn. Tạo loại token hẹp nhất:

1. Vào https://github.com/settings/personal-access-tokens/new (Fine-grained token).
2. **Token name**: `claude-push-issues`
3. **Expiration**: 7 days (hết hạn tự thu hồi).
4. **Resource owner**: chọn **thiennhatgroup**.
5. **Repository access** → **Only select repositories** → chọn `thiennhat-fuel`.
6. **Permissions** → **Repository permissions** → tìm **Issues** → chọn **Read and write**. (Các quyền khác để **No access**.)
7. Bấm **Generate token** → copy chuỗi `github_pat_...`.
8. Gửi mình chuỗi đó (chỉ dùng để tạo 10 issue, xong bạn có thể vào **Settings → Developer settings → Tokens** bấm **Revoke**).

> Lưu ý an toàn: đây là token của chính bạn, phạm vi chỉ 1 repo + chỉ quyền Issues, tự hết hạn sau 7 ngày. Bạn revoke bất cứ lúc nào.

## Sau đó (mình làm)
- Mình đẩy 10 issue (S0→S9) lên GitHub Issues theo đúng thứ tự phụ thuộc.
- Mình dựng khung code S0 (schema, RLS, FE shell, GitHub Actions) trong folder.
- Bạn commit & push qua GitHub Desktop; mình hướng dẫn cắm secrets Supabase cho Actions để deploy.
