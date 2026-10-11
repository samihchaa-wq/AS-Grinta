import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exécute `web/sw.js` dans Node, avec un faux navigateur, et rejoue des
/// notifications reçues. Ce test vérifie le chiffre réellement posé sur
/// l'icône, pas le texte du service worker.
const _harness = r'''
const fs = require('fs');
const vm = require('vm');

const scope = 'https://samihchaa-wq.github.io/AS-Grinta/';
const stores = new Map();
function store(name) {
  if (!stores.has(name)) stores.set(name, new Map());
  const entries = stores.get(name);
  return {
    match: async (key) => entries.has(key) ? new Response(entries.get(key)) : undefined,
    put: async (key, response) => { entries.set(key, await response.text()); },
    delete: async (key) => entries.delete(key),
    addAll: async () => {},
  };
}
const badges = [];
let windows = [];
const listeners = {};
const sandbox = {
  URL,
  Promise,
  Response,
  console,
  caches: {
    open: async (name) => store(name),
    keys: async () => [...stores.keys()],
    delete: async (name) => stores.delete(name),
  },
  fetch: async () => { throw new Error('offline'); },
  self: {
    location: { href: scope + 'sw.js?v=test', origin: 'https://samihchaa-wq.github.io' },
    addEventListener: (type, listener) => { listeners[type] = listener; },
    registration: { scope, showNotification: async () => {} },
    navigator: { setAppBadge: async (count) => { badges.push(count); } },
    clients: {
      matchAll: async () => windows,
      openWindow: async () => null,
      claim: async () => {},
    },
    skipWaiting: () => {},
  },
};
sandbox.self.self = sandbox.self;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync('web/sw.js', 'utf8'), sandbox);

function push(title) {
  let pending = Promise.resolve();
  listeners.push({
    data: { json: () => ({ title, body: '' }) },
    waitUntil: (promise) => { pending = promise; },
  });
  return pending;
}

(async () => {
  // Trois notifications arrivées en même temps, application fermée.
  await Promise.all([push('a'), push('b'), push('c')]);
  const afterThree = badges.slice();

  // Application ouverte et visible : la notification ne compte pas.
  windows = [{ url: scope, visibilityState: 'visible' }];
  await push('d');
  const whileVisible = badges.slice();

  // Mise à jour de l'application : le compteur survit au ménage des caches.
  windows = [];
  let activation = Promise.resolve();
  listeners.activate({ waitUntil: (promise) => { activation = promise; } });
  await activation;
  await push('e');
  const afterUpdate = badges.slice();

  // Ouverture de l'application : app_shell.js efface le compteur.
  await (await sandbox.caches.open('as-grinta-badge'))
    .delete(new URL('asg-badge-count', scope).href);
  await push('f');
  const afterOpen = badges.slice();

  process.stdout.write(JSON.stringify({ afterThree, whileVisible, afterUpdate, afterOpen }));
})().catch((error) => { console.error(error); process.exit(1); });
''';

void main() {
  test(
    'la pastille compte les notifications reçues depuis la dernière ouverture',
    () async {
      final result = await Process.run('node', ['-e', _harness]);
      expect(result.exitCode, 0, reason: '${result.stderr}');

      final output =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;

      expect(output['afterThree'], [1, 2, 3]);
      expect(output['whileVisible'], [1, 2, 3]);
      expect(output['afterUpdate'], [1, 2, 3, 4]);
      expect(output['afterOpen'], [1, 2, 3, 4, 1]);
    },
  );

  test('ouvrir l’application remet la pastille à zéro', () {
    final shell = File('web/app_shell.js').readAsStringSync();
    final worker = File('web/sw.js').readAsStringSync();

    // Même cache et même clé des deux côtés.
    expect(worker, contains("const BADGE_CACHE = 'as-grinta-badge';"));
    expect(worker, contains("const BADGE_KEY = 'asg-badge-count';"));
    expect(shell, contains("caches.open('as-grinta-badge')"));
    expect(shell, contains("new URL('asg-badge-count', registration.scope)"));
    expect(shell, contains('navigator.clearAppBadge()'));
  });
}
