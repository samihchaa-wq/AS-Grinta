import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exécute `web/sw.js` dans Node, avec un faux navigateur : chaque
/// notification réellement affichée doit laisser un accusé que
/// l'application transmettra au serveur. Sans lui, un envoi accepté par
/// Apple ou Google passe pour reçu même quand rien ne s'est affiché.
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

let failDisplay = false;
sandbox.self.registration.showNotification = async () => {
  if (failDisplay) throw new Error('affichage refusé');
};

function push(tag) {
  let pending = Promise.resolve();
  listeners.push({
    data: { json: () => ({ title: 'Disponibilité', body: '', tag }) },
    waitUntil: (promise) => { pending = promise.catch(() => {}); },
  });
  return pending;
}

async function receipts() {
  const stored = await (await sandbox.caches.open('as-grinta-push-receipts'))
    .match(new URL('asg-push-receipts', scope).href);
  return stored ? JSON.parse(await stored.text()).map((r) => r.tag) : [];
}

(async () => {
  // Deux notifications arrivées ensemble : deux accusés, aucun écrasé.
  await Promise.all([push('sport-a-availability-open'), push('custom-1')]);
  const afterTwo = await receipts();

  // Notification que le téléphone n'a pas pu afficher : aucun accusé.
  failDisplay = true;
  await push('jamais-affichee');
  failDisplay = false;
  const afterFailure = await receipts();

  // Mise à jour de l'application : les accusés pas encore transmis restent.
  let activation = Promise.resolve();
  listeners.activate({ waitUntil: (promise) => { activation = promise; } });
  await activation;
  await push(undefined);
  const afterUpdate = await receipts();

  // Pas plus de 50 accusés en attente.
  for (let i = 0; i < 60; i += 1) await push('flot-' + i);
  const capped = await receipts();

  process.stdout.write(JSON.stringify({
    afterTwo, afterFailure, afterUpdate,
    cappedLength: capped.length, cappedLast: capped[capped.length - 1],
  }));
})().catch((error) => { console.error(error); process.exit(1); });
''';

void main() {
  test('chaque notification affichée laisse un accusé', () async {
    final result = await Process.run('node', ['-e', _harness]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final output = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    expect(output['afterTwo'], ['sport-a-availability-open', 'custom-1']);
    expect(output['afterFailure'], ['sport-a-availability-open', 'custom-1']);
    expect(
      output['afterUpdate'],
      ['sport-a-availability-open', 'custom-1', 'sans-tag'],
    );
    expect(output['cappedLength'], 50);
    expect(output['cappedLast'], 'flot-59');
  });

  test('l’application lit et oublie les accusés du même cache', () {
    final shell = File('web/app_shell.js').readAsStringSync();
    final worker = File('web/sw.js').readAsStringSync();

    expect(
      worker,
      contains("const RECEIPTS_CACHE = 'as-grinta-push-receipts';"),
    );
    expect(worker, contains("const RECEIPTS_KEY = 'asg-push-receipts';"));
    expect(shell, contains("caches.open('as-grinta-push-receipts')"));
    expect(shell, contains("new URL('asg-push-receipts', registration.scope)"));
  });
}
