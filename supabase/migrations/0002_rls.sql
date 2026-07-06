-- ============================================================================
-- 0002_rls.sql — Deny-by-default. Trình duyệt KHÔNG truy cập bảng trực tiếp.
-- Mọi đọc/ghi đi qua RPC SECURITY DEFINER (0003+). Bật RLS + không policy +
-- revoke = client chỉ gọi được supabase.rpc(...), không select thẳng bảng.
-- ============================================================================
alter table app_config       enable row level security;
alter table profiles         enable row level security;
alter table role_permissions enable row level security;
alter table code_counters    enable row level security;
alter table audit_log        enable row level security;

revoke all on app_config, profiles, role_permissions, code_counters, audit_log
  from anon, authenticated;
