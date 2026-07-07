// Service worker: PWA cài được + offline vỏ app (network-first) + Web Push (S7).
const CACHE = 'tn-fuel-v1';
const SHELL = [
  './',
  './index.html',
  './config.js',
  './manifest.webmanifest',
  './logo.png',
  './logo.svg',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(SHELL)).catch(() => {}).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Network-first cho request cùng origin (vỏ app). Có mạng → lấy bản mới + cập nhật cache;
// mất mạng → phục vụ từ cache. KHÔNG can thiệp request khác origin (Supabase/CDN).
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // để Supabase/CDN đi thẳng

  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res && res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() =>
        caches.match(req).then((hit) => hit || (req.mode === 'navigate' ? caches.match('./index.html') : undefined))
      )
  );
});

// Nhận push từ Edge Function send-push → hiện thông báo hệ thống.
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_e) { data = {}; }
  const title = data.title || 'Cảnh báo tồn kho';
  const options = {
    body: data.body || '',
    tag: data.kind || 'ton-kho',
    data: { url: data.url || '/' }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// Bấm vào thông báo → mở/tập trung app ở màn Cảnh báo (hành vi S7 giữ nguyên).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const raw = (event.notification.data && event.notification.data.url) || '/';
  // Push cảnh báo tồn kho: đưa về màn Cảnh báo. Giữ deep-link nếu Edge gửi path riêng.
  const target = (raw === '/' || raw === './' || raw === '') ? './#alerts' : raw;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ('focus' in c) {
          c.postMessage({ type: 'open-screen', screen: 'alerts' });
          return c.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    })
  );
});
