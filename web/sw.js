// Service worker Ma Petite Grinta : cache réseau-d'abord (jamais de bundle périmé)
// et réception des notifications push Web Push. Cache fonctionnel v59 — visibilité sportive.
const CACHE_NAME = 'as-grinta-v59';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name.startsWith('as-grinta-') && name !== CACHE_NAME)
          .map((name) => caches.delete(name)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  event.respondWith(
    (async () => {
      try {
        return await fetch(event.request, { cache: 'no-store' });
      } catch (_) {
        const cached = await caches.match(event.request);
        return cached || Response.error();
      }
    })(),
  );
});

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = { body: event.data ? event.data.text() : '' };
  }

  const title = payload.title || 'Ma Petite Grinta';
  const options = {
    body: payload.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    data: payload.data || {},
    tag: payload.tag || undefined,
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data && event.notification.data.url
    ? event.notification.data.url
    : './';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if ('focus' in client) {
          client.navigate(target);
          return client.focus();
        }
      }
      return clients.openWindow(target);
    }),
  );
});
