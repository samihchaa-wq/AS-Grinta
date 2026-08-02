// Service worker Ma Petite Grinta : cache réseau-d'abord, mise à jour automatique
// et réception des notifications Web Push.
// Révision de déploiement 0.3.2+95 : force la prise en compte du bundle courant.
importScripts('build_version.js');

const WEB_VERSION = String(self.AS_GRINTA_WEB_VERSION || 'dev');
const CACHE_NAME = `as-grinta-${WEB_VERSION.replace(/[^a-zA-Z0-9._-]/g, '-')}`;
const APP_SHELL = [
  './',
  'index.html',
  'build_version.js',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

self.addEventListener('install', (event) => {
  // Le socle minimal est disponible hors ligne après une première installation
  // réussie. Lors d’une mise à jour, le worker reste en attente jusqu’au signal
  // automatique envoyé par la page courante.
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)),
  );
});

// Activation immédiate demandée par la page lorsqu'une nouvelle version existe.
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name)),
      );
      await self.clients.claim();
    })(),
  );
});

async function cachedNavigationFallback(cache) {
  return (await cache.match('index.html')) || (await cache.match('./'));
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request, { cache: 'no-store' });
        if (response && response.ok) {
          await cache.put(request, response.clone());
          return response;
        }
        if (request.mode === 'navigate') {
          const index = await cachedNavigationFallback(cache);
          if (index) return index;
        }
        return response;
      } catch (error) {
        const cached = await cache.match(request);
        if (cached) return cached;
        if (request.mode === 'navigate') {
          const index = await cachedNavigationFallback(cache);
          if (index) return index;
        }
        throw error;
      }
    })(),
  );
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'Ma Petite Grinta', {
      body: data.body || '',
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: data.tag || undefined,
      data: { url: data.url || '.' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(
    (event.notification.data && event.notification.data.url) || '.',
    self.registration.scope,
  ).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clients) => {
        for (const client of clients) {
          if ('focus' in client) {
            client.navigate(target);
            return client.focus();
          }
        }
        return self.clients.openWindow(target);
      },
    ),
  );
});
