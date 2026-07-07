// send-push — Edge Function gửi Web Push (VAPID) cho các cảnh báo tồn chưa đẩy.
// Kích hoạt: DB gọi push_dispatch() → net.http_post tới function này kèm header
//   x-webhook-secret. Function tự truy DB (service role) lấy notification chưa push
//   + push_subscription của Kế toán/Admin, gửi push rồi set pushed_at.
//
// Secrets (Supabase → Project Settings → Edge Functions → Secrets):
//   PUSH_WEBHOOK_SECRET  — phải khớp app_config.edge_push_secret (nếu THIẾU → bỏ qua an toàn, trả 200).
//   VAPID_PUBLIC_KEY     — trùng public key nhúng ở public/config.js (vapidPublicKey).
//   VAPID_PRIVATE_KEY    — private key VAPID (giữ bí mật).
//   VAPID_SUBJECT        — 'mailto:...' hoặc URL (mặc định mailto:admin@thiennhat).
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — Supabase tự cấp trong runtime.
//
// Deploy: supabase functions deploy send-push --no-verify-jwt  (gọi bằng secret, không JWT).

import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
  const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
  const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
  const vapidSubject = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@thiennhat.local";

  // Chưa cấu hình secret/VAPID → bỏ qua an toàn (không lỗi).
  if (!webhookSecret || !vapidPublic || !vapidPrivate) {
    return json({ ok: true, skipped: "push not configured" });
  }
  if (req.headers.get("x-webhook-secret") !== webhookSecret) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Cảnh báo chưa đẩy (giới hạn để tránh gửi hàng loạt cũ).
  const { data: notes, error: nErr } = await supabase
    .from("notification")
    .select("id, kind, level, title, body")
    .is("pushed_at", null)
    .order("created_at", { ascending: true })
    .limit(50);
  if (nErr) return json({ ok: false, error: nErr.message }, 500);
  if (!notes || notes.length === 0) return json({ ok: true, sent: 0 });

  // Người nhận: subscription của Kế toán/Admin đang Hoạt động.
  const { data: subs, error: sErr } = await supabase
    .from("push_subscription")
    .select("id, endpoint, p256dh, auth, profiles!inner(role, status)")
    .in("profiles.role", ["KeToan", "Admin"])
    .eq("profiles.status", "Hoạt động");
  if (sErr) return json({ ok: false, error: sErr.message }, 500);

  let sent = 0;
  const gone: string[] = [];
  for (const n of notes) {
    const payload = JSON.stringify({
      title: n.title,
      body: n.body,
      level: n.level,
      kind: n.kind,
      url: "/",
    });
    for (const s of subs ?? []) {
      const subscription = {
        endpoint: s.endpoint,
        keys: { p256dh: s.p256dh, auth: s.auth },
      };
      try {
        await webpush.sendNotification(subscription, payload);
        sent++;
      } catch (err) {
        const code = (err as { statusCode?: number })?.statusCode;
        if (code === 404 || code === 410) gone.push(s.endpoint); // hết hạn → dọn
      }
    }
  }

  // Đánh dấu đã đẩy + dọn subscription chết.
  await supabase
    .from("notification")
    .update({ pushed_at: new Date().toISOString() })
    .in("id", notes.map((n) => n.id));
  if (gone.length) {
    await supabase.from("push_subscription").delete().in("endpoint", gone);
  }

  return json({ ok: true, notifications: notes.length, sent, cleaned: gone.length });
});
