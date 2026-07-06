// Service worker tối thiểu để app cài được lên màn hình chính (PWA).
// S7 sẽ bổ sung xử lý push. Hiện chỉ pass-through, không cache để tránh dữ liệu cũ.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
