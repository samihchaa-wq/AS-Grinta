// Service worker AS La Grinta : navigation fraîche, programme gardé par
// version, fichiers statiques locaux, mise à jour contrôlée et réception des
// notifications Web Push.
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

// Programme principal de cette version. Son adresse porte la version
// (tool/stamp_web_release.py la réécrit dans flutter_bootstrap.js) : une page
// d'une version ne peut donc jamais recevoir le programme d'une autre.
const VERSIONED_MAIN_JS = `main.dart.js?v=${encodeURIComponent(WEB_VERSION)}`;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      await cache.addAll(APP_SHELL);
      // Préchargement : une nouvelle version découverte pendant que
      // l'application est ouverte télécharge son programme tout de suite, en
      // arrière-plan. L'ouverture suivante n'attend plus ce téléchargement.
      // Un échec (réseau coupé) ne bloque pas l'installation : le programme
      // sera simplement demandé au réseau à l'ouverture.
      if (WEB_VERSION !== 'dev') {
        await cache.add(VERSIONED_MAIN_JS).catch(() => {});
      }
    }),
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

// Accusés d'affichage : Apple et Google confirment avoir pris en charge une
// notification, jamais qu'elle s'est affichée. Le service worker note donc
// chaque notification que le téléphone a accepté de montrer ; l'application
// transmet ces accusés au serveur à sa prochaine ouverture
// (web/app_shell.js). Une notification envoyée sans accusé, alors que le
// joueur a rouvert l'application depuis, n'a pas été affichée.
const RECEIPTS_CACHE = 'as-grinta-push-receipts';
const RECEIPTS_KEY = 'asg-push-receipts';
const RECEIPTS_MAX = 50;

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) =>
            name !== CACHE_NAME &&
            name !== RECEIPTS_CACHE)
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

  // Vidéos et sons : le navigateur les télécharge par morceaux (en-tête
  // Range, réponses 206) que le cache refuse de stocker. Passés par ici, ils
  // échouaient : la vidéo du stade restait une image fixe sur tous les
  // téléphones. Ils vont donc directement au réseau.
  if (
    request.headers.has('range') ||
    request.destination === 'video' ||
    request.destination === 'audio'
  ) {
    return;
  }

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

      // Programme principal versionné : il ne change jamais pour une même
      // adresse. Il est donc servi depuis le téléphone dès qu'il y est, y
      // compris depuis le cache préchargé par une version plus récente pas
      // encore activée (caches.match parcourt tous les caches). Sans version
      // dans l'adresse (ancien bootstrap), il reste demandé au réseau.
      if (path.endsWith('/main.dart.js') && url.searchParams.has('v')) {
        const kept = await caches.match(request);
        if (kept) return kept;
        // Cache HTTP du navigateur autorisé (pas de `no-store`) : l'adresse
        // porte la version. Le préchargement de l'installation et la page
        // demandent souvent ce même programme au même moment, juste après
        // une mise à jour ; le second est alors servi par le navigateur au
        // lieu d'être téléchargé une deuxième fois.
        const response = await fetch(request);
        if (response && response.ok) {
          await cache.put(request, response.clone());
        }
        return response;
      }

      const mustStayFresh =
          path.endsWith('/build_version.js') ||
          path.endsWith('/sw.js') ||
          path.endsWith('/index.html') ||
          path.endsWith('/main.dart.js') ||
          // Morceaux de programme chargés à la demande : leur adresse ne
          // porte pas la version, ils doivent donc toujours venir du réseau
          // tant qu'il répond.
          path.endsWith('.part.js');

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

// Pastille de l'icône : le serveur glisse dans chaque notification le nombre
// de notifications non lues du joueur (app_badge), le même que la cloche de
// l'application. Sans ce nombre (essai, ancien serveur), la pastille ne
// bouge pas. L'application la remet aussi à jour elle-même à chaque
// changement (web/app_shell.js, asGrintaPush.setBadge). L'ancien compteur
// propre à l'appareil (cache as-grinta-badge) est effacé à l'activation.
function applyServerBadge(value) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
    return Promise.resolve();
  }
  const nav = self.navigator;
  if (!nav) return Promise.resolve();
  let update = null;
  if (value === 0) {
    if (typeof nav.clearAppBadge === 'function') update = nav.clearAppBadge();
  } else if (typeof nav.setAppBadge === 'function') {
    update = nav.setAppBadge(value);
  }
  return Promise.resolve(update).catch(() => {});
}

// Application ouverte : elle met à jour sa cloche tout de suite.
async function notifyOpenWindows(data) {
  try {
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    for (const client of windows) {
      if (typeof client.postMessage === 'function') {
        client.postMessage({ type: 'ASG_PUSH_RECEIVED', tag: data.tag || null });
      }
    }
  } catch (_) {
    // Une fenêtre fermée entre-temps ne doit pas faire échouer la réception.
  }
}

// Même file d'attente que la pastille : deux notifications arrivées ensemble
// ne doivent pas écraser l'accusé l'une de l'autre.
let receiptUpdates = Promise.resolve();

function recordDisplayReceipt(tag) {
  receiptUpdates = receiptUpdates.then(async () => {
    const cache = await caches.open(RECEIPTS_CACHE);
    const key = new URL(RECEIPTS_KEY, self.registration.scope).href;
    const stored = await cache.match(key);
    let receipts = [];
    if (stored) {
      try {
        const parsed = JSON.parse(await stored.text());
        if (Array.isArray(parsed)) receipts = parsed;
      } catch (_) {}
    }
    receipts.push({ tag: tag || 'sans-tag', at: new Date().toISOString() });
    await cache.put(
      key,
      new Response(JSON.stringify(receipts.slice(-RECEIPTS_MAX))),
    );
  }).catch(() => {});
  return receiptUpdates;
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
      }).then(() => recordDisplayReceipt(data.tag)),
      applyServerBadge(data.app_badge),
      notifyOpenWindows(data),
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

// Une compo ouverte depuis sa notification lance sa vidéo : l'adresse le dit
// à l'application par `from=notification`. Une compo ouverte autrement (onglet
// Compo, lien de la fiche) ne porte pas cette marque.
function markCompositionFromNotification(targetUrl) {
  const hashIndex = targetUrl.indexOf('#/');
  if (hashIndex < 0) return targetUrl;
  const route = targetUrl.slice(hashIndex + 2);
  const queryIndex = route.indexOf('?');
  const path = queryIndex < 0 ? route : route.slice(0, queryIndex);
  if (!/^matches\/[^/?#]+\/lineup$/.test(path)) return targetUrl;
  const params = new URLSearchParams(queryIndex < 0 ? '' : route.slice(queryIndex + 1));
  if (params.get('section') !== 'composition') return targetUrl;
  params.set('from', 'notification');
  return `${targetUrl.slice(0, hashIndex)}#/${path}?${params.toString()}`;
}

// Version de l'application en ligne en ce moment, ou '' si on ne peut pas la
// lire (hors ligne, serveur lent) : on ne retarde alors pas l'ouverture.
async function deployedWebVersion(scopeUrl) {
  try {
    const url = new URL('build_version.js', scopeUrl);
    url.searchParams.set('notification-check', String(Date.now()));
    const response = await Promise.race([
      fetch(url.href, { cache: 'no-store' }),
      new Promise((resolve) => setTimeout(() => resolve(null), 2500)),
    ]);
    if (!response || !response.ok) return '';
    const match = (await response.text())
      .match(/AS_GRINTA_WEB_VERSION\s*=\s*['"]([^'"]+)['"]/);
    return match ? match[1] : '';
  } catch (_) {
    return '';
  }
}

// Une application restée ouverte en arrière-plan garde sa version jusqu'à la
// prochaine ouverture, pour ne pas couper ce qu'on y faisait. Toucher une
// notification, c'est passer à autre chose : si une version plus récente est
// en ligne, la page de la notification est rechargée dessus (avec la marque
// de mise à jour de app_shell.js) au lieu de rester sur l'ancienne.
function withDeploymentMarker(target, version) {
  const url = new URL(target);
  url.searchParams.set('_asg_release', version);
  return url.href;
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = markCompositionFromNotification(notificationTargetUrl(
    event.notification.data && event.notification.data.url,
    self.registration.scope,
  ));
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clients) => {
        // Une fenêtre de l'application déjà ouverte est mise au premier plan
        // et amenée sur la page de la notification ; sinon, une fenêtre
        // s'ouvre directement sur cette page (et donc sur la dernière version).
        const appWindow = clients.find(
          (client) => client.url.startsWith(self.registration.scope) && 'focus' in client,
        );
        if (!appWindow) return self.clients.openWindow(target);

        const canNavigate = 'navigate' in appWindow;
        // Ouverture immédiate, sans rien attendre : un téléphone n'autorise
        // l'ouverture que juste après le toucher.
        const navigation = canNavigate
          ? appWindow.navigate(target).catch(() => self.clients.openWindow(target))
          : self.clients.openWindow(target);
        // Ensuite seulement, la version : plus récente, la page est rechargée
        // dessus, à la même adresse.
        const refresh = canNavigate
          ? Promise.all([deployedWebVersion(self.registration.scope), navigation])
            .then(([deployed, opened]) => {
              if (!deployed || deployed === WEB_VERSION) return null;
              const client = opened && typeof opened.navigate === 'function'
                ? opened
                : appWindow;
              return client.navigate(withDeploymentMarker(target, deployed));
            })
            .catch(() => null)
          : null;
        return Promise.all([appWindow.focus(), navigation, refresh]);
      },
    ),
  );
});
