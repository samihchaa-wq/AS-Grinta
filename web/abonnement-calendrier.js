// Page vers laquelle calendar-feed redirige un navigateur : le lien du flux
// arrive dans le fragment (#feed=…), jamais envoyé à l'hébergeur. Seul un
// flux calendar-feed Supabase est accepté, pour ne pas servir de relais vers
// une autre adresse.
(function () {
  var FEED_RE = /^https:\/\/[a-z0-9]+\.supabase\.co\/functions\/v1\/calendar-feed\?token=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  var feed = new URLSearchParams(window.location.hash.slice(1)).get('feed') || '';

  if (!FEED_RE.test(feed)) {
    document.getElementById('invalid').hidden = false;
    return;
  }

  document.getElementById('content').hidden = false;
  document.getElementById('apple').href = feed.replace(/^https:/, 'webcal:');
  document.getElementById('feed').textContent = feed;

  var copy = document.getElementById('copy');
  copy.addEventListener('click', function () {
    var done = function () { copy.textContent = 'Lien copié ✓'; };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(feed).then(done, function () {});
    }
  });
})();
