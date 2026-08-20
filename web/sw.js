// Service worker AS La Grinta : navigation fraîche, fichiers statiques locaux,
// mise à jour contrôlée et réception des notifications Web Push.
const workerUrl = new URL(self.location.href);
const WEB_VERSION = workerUrl.searchParams.get('v') || 'dev';
const CACHE_NAME = `as-grinta-${WEB_VERSION.replace(/[^a-zA-Z0-9._-]/g, '-')}`;
const APP_SHELL = [
  './',
  'index.html',
  'build_version.js',
  'app_shell.js',
  'asg_logo.webp',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)),
  );
});

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

async function networkFirst(request, cache) {
  try {
    const response = await fetch(request, { cache: 'no-store' });
    if (response && response.ok) {
      await cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const cached = await cache.match(request);
    if (cached) return cached;
    throw error;
  }
}

async function staleWhileRevalidate(request, cache, event) {
  const cached = await cache.match(request);
  const refresh = fetch(request).then(async (response) => {
    if (response && response.ok) {
      await cache.put(request, response.clone());
    }
    return response;
  }).catch(() => null);

  if (cached) {
    event.waitUntil(refresh);
    return cached;
  }

  const response = await refresh;
  if (response) return response;
  throw new Error('Ressource indisponible hors ligne');
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_NAME);

      if (request.mode === 'navigate') {
        try {
          const response = await networkFirst(request, cache);
          if (response && response.ok) return response;
        } catch (_) {}
        const index = await cachedNavigationFallback(cache);
        if (index) return index;
        throw new Error('Navigation indisponible hors ligne');
      }

      const path = url.pathname;
      const mustStayFresh =
          path.endsWith('/build_version.js') ||
          path.endsWith('/sw.js') ||
          path.endsWith('/index.html');

      if (mustStayFresh) {
        return networkFirst(request, cache);
      }

      // Les bundles, images, polices et autres ressources versionnées sont
      // rendus immédiatement depuis le cache. Une vérification réseau se fait
      // en arrière-plan sans bloquer l'interface.
      return staleWhileRevalidate(request, cache, event);
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
    self.registration.showNotification(data.title || 'AS La Grinta', {
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
