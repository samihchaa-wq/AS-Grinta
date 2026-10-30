// Test de la vidéo du stade sur un téléphone, avec exactement les réglages de
// l'appli (vidéo muette, lue dans la page, téléchargée d'un bloc, version
// légère pour les téléphones qui ne lisent pas la grande sans à-coups).
// Rien n'est envoyé : la personne fait une capture d'écran du résultat.
(function () {
  'use strict';
  var BIG = 'assets/assets/composition/stade.mp4';
  var LIGHT = 'assets/assets/composition/stade-720.mp4';
  var video = document.getElementById('video');
  var verdict = document.getElementById('verdict');
  var results = document.getElementById('results');
  var details = document.getElementById('details');
  var tap = document.getElementById('tap');
  var t0 = performance.now();
  var lines = [];
  var objectUrl = null;

  function seconds() {
    return ((performance.now() - t0) / 1000).toFixed(1) + ' s';
  }

  function note(text) {
    lines.push(seconds() + ' ' + text);
    renderDetails();
  }

  function result(ok, text) {
    var li = document.createElement('li');
    li.textContent = (ok ? '✅ ' : '❌ ') + text;
    results.appendChild(li);
  }

  function setVerdict(kind, text) {
    verdict.className = 'verdict ' + kind;
    verdict.textContent = text;
  }

  function inAppBrowser() {
    var ua = navigator.userAgent || '';
    if (/FBAN|FBAV|Instagram/i.test(ua)) return 'Facebook / Instagram';
    if (/WhatsApp/i.test(ua)) return 'WhatsApp';
    if (/Snapchat/i.test(ua)) return 'Snapchat';
    if (/; wv\)/.test(ua)) return 'navigateur intégré (Android)';
    return null;
  }

  function renderDetails() {
    var standalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
      window.navigator.standalone === true;
    var info = [
      'Téléphone : ' + navigator.userAgent,
      'Ouvert comme appli installée : ' + (standalone ? 'oui' : 'non'),
      'Navigateur intégré : ' + (inAppBrowser() || 'non'),
      'Service worker actif : ' + (navigator.serviceWorker && navigator.serviceWorker.controller ? 'oui' : 'non'),
      'Version du site : ' + (window.AS_GRINTA_WEB_VERSION || 'inconnue'),
      '',
    ].concat(lines);
    details.textContent = info.join('\n');
  }

  function decodingInfo(codec, width, height, bitrate) {
    if (!navigator.mediaCapabilities || !navigator.mediaCapabilities.decodingInfo) {
      return Promise.resolve(null);
    }
    return navigator.mediaCapabilities.decodingInfo({
      type: 'file',
      video: { contentType: 'video/mp4; codecs="' + codec + '"', width: width, height: height, bitrate: bitrate, framerate: 30 },
    }).catch(function () { return null; });
  }

  function describe(info) {
    if (!info) return 'inconnu';
    return (info.supported ? 'lisible' : 'illisible') + (info.smooth ? ', fluide' : ', pas fluide');
  }

  // La lecture démarre-t-elle vraiment (le temps de la vidéo avance) ?
  function playAndCheck(label) {
    return new Promise(function (resolve) {
      var start = video.currentTime;
      var done = false;
      function finish(ok, reason) {
        if (done) return;
        done = true;
        note(label + ' : ' + (ok ? 'la vidéo avance' : reason));
        resolve({ ok: ok, reason: reason });
      }
      var promise;
      try {
        promise = video.play();
      } catch (error) {
        finish(false, 'lecture impossible (' + error + ')');
        return;
      }
      if (promise && promise.catch) {
        promise.catch(function (error) {
          finish(false, 'lecture refusée par le téléphone (' + (error && error.name || error) + ')');
        });
      }
      setTimeout(function () {
        if (video.error) finish(false, 'vidéo illisible (erreur ' + video.error.code + ')');
        else if (!video.paused && video.currentTime > start + 0.5) finish(true);
        else finish(false, 'la vidéo ne démarre pas (état ' + video.readyState + ')');
      }, 2500);
    });
  }

  function load(url) {
    return fetch(url).then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.blob();
    }).then(function (blob) {
      objectUrl = URL.createObjectURL(blob);
      note('vidéo téléchargée (' + (blob.size / 1e6).toFixed(1) + ' Mo)');
      return objectUrl;
    });
  }

  function run() {
    renderDetails();
    Promise.all([
      decodingInfo('avc1.640032', 1080, 2338, 2300000),
      decodingInfo('avc1.640028', 720, 1558, 950000),
    ]).then(function (infos) {
      note('grande version : ' + describe(infos[0]));
      note('version légère : ' + describe(infos[1]));
      var big = infos[0] && infos[0].supported && infos[0].smooth;
      var url = big ? BIG : LIGHT;
      note('version choisie : ' + (big ? '1080 px' : '720 px'));
      return load(url);
    }).then(function (source) {
      video.src = source;
      video.load();
      return playAndCheck('sans appui');
    }).then(function (auto) {
      result(auto.ok, 'Démarrage automatique' + (auto.ok ? '' : ' : ' + auto.reason));
      if (auto.ok) {
        setVerdict('ok', '✅ Ton téléphone lit la vidéo animée.');
        return;
      }
      setVerdict('wait', 'Un 2ᵉ test est nécessaire : touche le bouton jaune.');
      tap.hidden = false;
      tap.addEventListener('click', function () {
        tap.hidden = true;
        video.currentTime = 0;
        playAndCheck('après un appui').then(function (touch) {
          result(touch.ok, 'Après un appui' + (touch.ok ? '' : ' : ' + touch.reason));
          if (touch.ok) {
            setVerdict('wait', '⚠️ La vidéo ne démarre qu’après un appui (mode économie d’énergie ?). L’aperçu marchera ; une vidéo lancée toute seule montrera l’image fixe du stade.');
          } else {
            setVerdict('ko', '❌ Ton téléphone ne lit pas la vidéo : il verra l’image fixe du stade.');
          }
        });
      }, { once: true });
    }).catch(function (error) {
      note('échec : ' + error);
      result(false, 'Téléchargement de la vidéo impossible');
      setVerdict('ko', '❌ La vidéo n’a pas pu être téléchargée (connexion ?). Réessaie avec du réseau.');
    });
  }

  run();
})();
