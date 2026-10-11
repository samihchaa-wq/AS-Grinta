// Service worker AS La Grinta : navigation fraîche, bundle applicatif frais,
// fichiers statiques locaux, mise à jour contrôlée et réception des notifications Web Push.
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
  'icons/notification-badge-96.png',
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

// Pastille de l'icône : nombre de notifications reçues depuis la dernière
// ouverture de l'application. Le compteur vit dans un cache dédié, que les
// mises à jour ne vident pas, et l'application le remet à zéro quand elle
// passe au premier plan (web/app_shell.js).
const BADGE_CACHE = 'as-grinta-badge';
const BADGE_KEY = 'asg-badge-count';

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name !== CACHE_NAME && name !== BADGE_CACHE)
          .map((name) => caches.delete(name)),
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
          path.endsWith('/index.html') ||
          path.endsWith('/main.dart.js');

      if (mustStayFresh) {
        return networkFirst(request, cache);
      }

      // Les images, polices et autres ressources statiques sont rendues
      // immédiatement depuis le cache. Une vérification réseau se fait en
      // arrière-plan sans bloquer l'interface.
      return staleWhileRevalidate(request, cache, event);
    })(),
  );
});

// Deux notifications arrivées ensemble ne doivent pas lire le même ancien
// chiffre : les mises à jour du compteur passent l'une après l'autre.
let badgeUpdates = Promise.resolve();

function bumpAppBadge() {
  badgeUpdates = badgeUpdates.then(async () => {
    // Application ouverte et visible : la notification est vue tout de suite,
    // elle ne compte pas.
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    if (windows.some((client) => client.visibilityState === 'visible')) return;

    const cache = await caches.open(BADGE_CACHE);
    const key = new URL(BADGE_KEY, self.registration.scope).href;
    const stored = await cache.match(key);
    const previous = stored ? parseInt(await stored.text(), 10) : 0;
    const count = (Number.isFinite(previous) && previous > 0 ? previous : 0) + 1;
    await cache.put(key, new Response(String(count)));

    // Chiffre affiché par iPhone (application installée). Android et les
    // navigateurs sans pastille l'ignorent.
    const nav = self.navigator;
    if (nav && typeof nav.setAppBadge === 'function') {
      await nav.setAppBadge(count);
    }
  }).catch(() => {});
  return badgeUpdates;
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    Promise.all([
      self.registration.showNotification(data.title || 'AS La Grinta', {
        body: data.body || '',
        icon: 'icons/Icon-192.png',
        // Android dessine le badge de la barre d'état avec sa seule
        // transparence : un logo sur fond plein y devient un carré uni.
        badge: 'icons/notification-badge-96.png',
        tag: data.tag || undefined,
        data: { url: data.url || '.' },
      }),
      bumpAppBadge(),
    ]),
  );
});

// Les notifications portent une adresse relative de l'application :
// `matches/<id>/vote`, `matches/<id>/lineup?section=effectif`,
// `admin/administration`… L'application ne lit ses routes qu'après `#`. Une
// adresse en forme chemin ouvrait donc le calendrier : elle est convertie en
// `<scope>#/...`. Une adresse déjà sous forme `#/...` est gardée, et tout ce
// qui sortirait de l'application ramène à son accueil.
function notificationTargetUrl(rawUrl, scopeUrl) {
  const scope = new URL(scopeUrl);
  const home = scope.href;
  const value = typeof rawUrl === 'string' ? rawUrl.trim() : '';
  if (!value || value === '.' || value === './') return home;

  let target;
  try {
    // Une route écrite `/matches/...` appartient à l'application, pas à la
    // racine du domaine.
    const relative = value.startsWith('/') && !value.startsWith('//') &&
        !value.startsWith(scope.pathname)
      ? value.slice(1)
      : value;
    target = new URL(relative, scope);
  } catch (_) {
    return home;
  }

  if (target.origin !== scope.origin) return home;
  if (!target.pathname.startsWith(scope.pathname)) return home;
  if (target.hash.startsWith('#/')) return `${home}${target.hash}`;

  const route = target.pathname.slice(scope.pathname.length).replace(/^\/+/, '');
  if (!route || route === 'index.html') return home;
  return `${home}#/${route}${target.search}`;
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = notificationTargetUrl(
    event.notification.data && event.notification.data.url,
    self.registration.scope,
  );
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clients) => {
        // Une fenêtre de l'application déjà ouverte est mise au premier plan
        // et amenée sur la page de la notification ; sinon, une fenêtre
        // s'ouvre directement sur cette page.
        const appWindow = clients.find(
          (client) => client.url.startsWith(self.registration.scope) && 'focus' in client,
        );
        if (!appWindow) return self.clients.openWindow(target);

        const navigation = 'navigate' in appWindow
          ? appWindow.navigate(target).catch(() => self.clients.openWindow(target))
          : self.clients.openWindow(target);
        return Promise.all([appWindow.focus(), navigation]);
      },
    ),
  );
});
