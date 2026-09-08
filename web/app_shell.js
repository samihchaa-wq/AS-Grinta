(function () {
  'use strict';

  var asGrintaWebVersion = window.AS_GRINTA_WEB_VERSION || 'dev';
  var deploymentCheckInFlight = false;
  var deploymentCheckIntervalMs = 300000;
  var deploymentMarker = '_asg_release';
  var flutterFirstFrameSeen = false;

  function extractDeploymentVersion(source) {
    var match = source.match(/AS_GRINTA_WEB_VERSION\s*=\s*['"]([^'"]+)['"]/);
    return match ? match[1] : '';
  }

  function clearCurrentDeploymentMarker() {
    try {
      var currentUrl = new URL(window.location.href);
      if (currentUrl.searchParams.get(deploymentMarker) !== asGrintaWebVersion) {
        return;
      }
      currentUrl.searchParams.delete(deploymentMarker);
      window.history.replaceState(null, '', currentUrl.toString());
    } catch (_) {}
  }

  async function checkDeploymentVersion() {
    if (deploymentCheckInFlight) return;
    deploymentCheckInFlight = true;
    try {
      var versionUrl = new URL('build_version.js', document.baseURI);
      versionUrl.searchParams.set('version-check', String(Date.now()));
      var response = await fetch(versionUrl.toString(), { cache: 'no-store' });
      if (!response.ok) return;

      var freshVersion = extractDeploymentVersion(await response.text());
      if (!freshVersion || freshVersion === asGrintaWebVersion) return;

      var targetUrl = new URL(window.location.href);
      if (targetUrl.searchParams.get(deploymentMarker) === freshVersion) {
        return;
      }
      targetUrl.searchParams.set(deploymentMarker, freshVersion);
      window.location.replace(targetUrl.toString());
    } catch (_) {
      // Une vérification de fraîcheur ne doit jamais bloquer le démarrage.
    } finally {
      deploymentCheckInFlight = false;
    }
  }

  clearCurrentDeploymentMarker();
  checkDeploymentVersion();
  setInterval(checkDeploymentVersion, deploymentCheckIntervalMs);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') checkDeploymentVersion();
  });

  window.asGrintaUpdate = {
    _worker: null,
    _pending: false,
    _status: null,

    show: function (worker) {
      if (!worker) return;
      this._worker = worker;
      this._pending = true;
      this._showStatus();

      // Au démarrage, ou pendant que l'app est en arrière-plan, la nouvelle
      // version prend immédiatement le contrôle. Si l'utilisateur est déjà
      // actif dans Flutter, on attend qu'il quitte l'app afin de ne pas couper
      // une saisie ou une mutation en cours.
      if (!flutterFirstFrameSeen || document.visibilityState !== 'visible') {
        this.activate();
      }
    },

    _showStatus: function () {
      if (this._status || document.getElementById('as-grinta-update-status')) {
        return;
      }

      var status = document.createElement('div');
      status.id = 'as-grinta-update-status';
      status.textContent = 'Mise à jour d’AS Grinta…';
      status.setAttribute('aria-live', 'polite');
      status.setAttribute('role', 'status');
      status.setAttribute('style', [
        'position:fixed',
        'left:50%',
        'bottom:calc(env(safe-area-inset-bottom, 0px) + 16px)',
        'transform:translateX(-50%)',
        'z-index:2147483647',
        'max-width:calc(100% - 32px)',
        'background:rgba(4,18,36,.92)',
        'color:#fff',
        'font:600 13px/1.35 -apple-system,BlinkMacSystemFont,system-ui,sans-serif',
        'padding:9px 13px',
        'border-radius:999px',
        'box-shadow:0 4px 16px rgba(0,0,0,.24)',
        'text-align:center',
        'pointer-events:none'
      ].join(';'));

      document.body.appendChild(status);
      this._status = status;
    },

    activate: function () {
      if (!this._pending || !this._worker) return;
      var worker = this._worker;
      this._worker = null;
      this._pending = false;
      worker.postMessage({ type: 'SKIP_WAITING' });
    }
  };

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') {
      window.asGrintaUpdate.activate();
    }
  });
  window.addEventListener('pagehide', function () {
    window.asGrintaUpdate.activate();
  });

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register(
      'sw.js?v=' + encodeURIComponent(asGrintaWebVersion),
      { updateViaCache: 'none' }
    ).then(function (registration) {
      if (!registration) return;

      function considerWorker(worker) {
        if (!worker || !navigator.serviceWorker.controller) return;
        window.asGrintaUpdate.show(worker);
      }

      considerWorker(registration.waiting);
      registration.addEventListener('updatefound', function () {
        var incoming = registration.installing;
        if (!incoming) return;
        incoming.addEventListener('statechange', function () {
          if (incoming.state === 'installed') considerWorker(incoming);
        });
      });

      registration.update();
      setInterval(function () { registration.update(); }, 300000);
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') registration.update();
      });
    }).catch(function () {});

    var refreshing = false;
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (refreshing) return;
      refreshing = true;
      window.location.reload();
    });
  }

  window.asGrintaPush = {
    support: function () {
      return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
    },
    permission: function () {
      return 'Notification' in window ? Notification.permission : 'unsupported';
    },
    subscribe: async function (vapidKey) {
      if (!window.asGrintaPush.support()) return '';
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') return '';
      const registration = await navigator.serviceWorker.ready;
      const padding = '='.repeat((4 - (vapidKey.length % 4)) % 4);
      const base64 = (vapidKey + padding).replace(/-/g, '+').replace(/_/g, '/');
      const raw = atob(base64);
      const key = Uint8Array.from(Array.from(raw, function (c) { return c.charCodeAt(0); }));
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: key,
      });
      return JSON.stringify(subscription.toJSON());
    },
    current: async function () {
      if (!window.asGrintaPush.support()) return '';
      const registration = await navigator.serviceWorker.getRegistration();
      if (!registration) return '';
      const subscription = await registration.pushManager.getSubscription();
      return subscription ? JSON.stringify(subscription.toJSON()) : '';
    },
    unsubscribe: async function () {
      if (!window.asGrintaPush.support()) return '';
      const registration = await navigator.serviceWorker.getRegistration();
      if (!registration) return '';
      const subscription = await registration.pushManager.getSubscription();
      if (!subscription) return '';
      const json = JSON.stringify(subscription.toJSON());
      await subscription.unsubscribe();
      return json;
    },
  };

  // Sélecteur dédié aux images de badges. On écoute uniquement l'événement
  // "change" du vrai input HTML : sur Safari/iOS en PWA, le chemin générique
  // d'image_picker peut interpréter le retour du sélecteur comme une annulation
  // avant que le fichier choisi ne soit remonté à Flutter.
  window.asGrintaBadgeImage = {
    pick: function () {
      return new Promise(function (resolve) {
        var input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/*';
        input.style.position = 'fixed';
        input.style.left = '-10000px';
        input.style.top = '-10000px';
        input.setAttribute('aria-hidden', 'true');
        document.body.appendChild(input);

        var finished = false;
        function finish(value) {
          if (finished) return;
          finished = true;
          input.remove();
          resolve(value || '');
        }

        input.addEventListener('change', function () {
          var file = input.files && input.files.length ? input.files[0] : null;
          if (!file) {
            finish('');
            return;
          }

          var reader = new FileReader();
          reader.addEventListener('load', function () {
            finish(typeof reader.result === 'string' ? reader.result : '');
          }, { once: true });
          reader.addEventListener('error', function () { finish(''); }, { once: true });
          reader.readAsDataURL(file);
        }, { once: true });

        input.click();
      });
    },
  };

  // Écran de démarrage HTML : il occupe l'attente avant que Flutter n'affiche
  // sa première image. Sans lui, le premier chargement laisse une page vide.
  var splashStalledTimer = null;
  var splashDismissed = false;

  function dismissSplash() {
    if (splashDismissed) return;
    splashDismissed = true;
    if (splashStalledTimer) {
      clearTimeout(splashStalledTimer);
      splashStalledTimer = null;
    }
    var splash = document.getElementById('asg-splash');
    if (!splash) return;
    splash.classList.add('asg-splash-out');
    setTimeout(function () {
      if (splash.parentNode) splash.parentNode.removeChild(splash);
    }, 400);
  }

  function showSplashStalled() {
    splashStalledTimer = null;
    var inner = document.querySelector('#asg-splash .asg-splash-inner');
    if (splashDismissed || !inner || document.querySelector('.asg-stalled')) return;

    var block = document.createElement('div');
    block.className = 'asg-stalled';
    block.setAttribute('role', 'alert');

    var text = document.createElement('p');
    text.style.margin = '0';
    text.textContent = 'Le chargement prend plus de temps que d’habitude.';

    var retry = document.createElement('button');
    retry.type = 'button';
    retry.textContent = 'Recharger';
    retry.addEventListener('click', function () {
      window.location.reload();
    });

    block.appendChild(text);
    block.appendChild(retry);
    inner.appendChild(block);
  }

  window.addEventListener('flutter-first-frame', function () {
    flutterFirstFrameSeen = true;
    dismissSplash();
  });
  splashStalledTimer = setTimeout(showSplashStalled, 15000);

  var bootstrap = document.createElement('script');
  bootstrap.src = 'flutter_bootstrap.js?v=' + encodeURIComponent(asGrintaWebVersion);
  bootstrap.async = true;
  document.body.appendChild(bootstrap);
})();
