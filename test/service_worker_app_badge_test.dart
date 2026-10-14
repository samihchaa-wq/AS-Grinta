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
const messages = [];
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
    navigator: {
      setAppBadge: async (count) => { badges.push(count); },
      clearAppBadge: async () => { badges.push('effacée'); },
    },
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

function push(data) {
  let pending = Promise.resolve();
  listeners.push({
    data: { json: () => data },
    waitUntil: (promise) => { pending = promise; },
  });
  return pending;
}

(async () => {
  // Le serveur donne le nombre de non-lues : l'icône affiche ce nombre.
  await push({ title: 'a', body: '', tag: 't1', app_badge: 4 });
  await push({ title: 'b', body: '', tag: 't2', app_badge: 5 });
  const fromServer = badges.slice();

  // Application ouverte et visible : le nombre s'applique quand même, et la
  // fenêtre est prévenue pour mettre sa cloche à jour.
  windows = [
    { url: scope, visibilityState: 'visible', postMessage: (m) => messages.push(m) },
    { url: scope, visibilityState: 'hidden' },
  ];
  await push({ title: 'c', body: '', tag: 't3', app_badge: 6 });
  const whileVisible = badges.slice();

  // Sans nombre (essai, ancien serveur) ou nombre invalide : rien ne bouge.
  windows = [];
  await push({ title: 'd', body: '' });
  await push({ title: 'e', body: '', app_badge: '7' });
  await push({ title: 'f', body: '', app_badge: -1 });
  await push({ title: 'g', body: '', app_badge: 2.5 });
  const withoutCount = badges.slice();

  // Zéro efface la pastille.
  await push({ title: 'h', body: '', app_badge: 0 });
  const zero = badges.slice();

  // Mise à jour : l'ancien compteur propre à l'appareil est supprimé.
  await sandbox.caches.open('as-grinta-badge');
  let activation = Promise.resolve();
  listeners.activate({ waitUntil: (promise) => { activation = promise; } });
  await activation;
  const cachesAfterUpdate = [...stores.keys()];

  process.stdout.write(JSON.stringify({
    fromServer, whileVisible, withoutCount, zero, messages, cachesAfterUpdate,
  }));
})().catch((error) => { console.error(error); process.exit(1); });
''';

void main() {
  test(
      'la pastille de l’icône affiche le nombre de non-lues donné par le serveur',
      () async {
    final result = await Process.run('node', ['-e', _harness]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final output = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    expect(output['fromServer'], [4, 5]);
    expect(output['whileVisible'], [4, 5, 6]);
    expect(output['withoutCount'], [4, 5, 6]);
    expect(output['zero'], [4, 5, 6, 'effacée']);
    expect(output['messages'], [
      {'type': 'ASG_PUSH_RECEIVED', 'tag': 't3'},
    ]);
    expect(output['cachesAfterUpdate'], isNot(contains('as-grinta-badge')));
  });

  test('l’application pose elle-même la pastille et écoute les réceptions', () {
    final shell = File('web/app_shell.js').readAsStringSync();
    final worker = File('web/sw.js').readAsStringSync();

    // Ouvrir l'application n'efface plus la pastille : elle garde le nombre
    // de non-lues tant que le joueur ne les a pas lues.
    expect(shell, isNot(contains('clearAppIconBadge')));
    expect(shell, isNot(contains("caches.open('as-grinta-badge')")));
    expect(worker, isNot(contains('BADGE_CACHE')));

    expect(shell, contains('setBadge: async function (count)'));
    expect(shell, contains('onReceived: function (callback)'));
    expect(shell, contains("event.data.type !== 'ASG_PUSH_RECEIVED'"));
    expect(worker, contains("type: 'ASG_PUSH_RECEIVED'"));
    expect(worker, contains('applyServerBadge(data.app_badge)'));
  });
}
