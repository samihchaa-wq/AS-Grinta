import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exécute `web/sw.js` dans Node, avec un faux navigateur, et rejoue des
/// clics sur des notifications. Ce test vérifie le comportement réel du
/// service worker, pas son texte.
const _harness = r'''
const fs = require('fs');
const vm = require('vm');

const scope = 'https://samihchaa-wq.github.io/AS-Grinta/';
const calls = [];
let windows = [];
// Version en ligne que renvoie build_version.js (null : hors ligne).
let deployed = null;
const listeners = {};
const sandbox = {
  URL,
  URLSearchParams,
  Promise,
  setTimeout,
  console,
  caches: { open: async () => ({}), keys: async () => [] },
  fetch: async (url) => {
    if (deployed && String(url).includes('build_version.js')) {
      return {
        ok: true,
        text: async () => `globalScope.AS_GRINTA_WEB_VERSION = '${deployed}';`,
      };
    }
    throw new Error('offline');
  },
  self: {
    location: { href: scope + 'sw.js?v=test', origin: 'https://samihchaa-wq.github.io' },
    addEventListener: (type, listener) => { listeners[type] = listener; },
    registration: { scope, showNotification: async () => {} },
    clients: {
      matchAll: async () => windows,
      openWindow: async (url) => { calls.push(['openWindow', url]); return null; },
      claim: async () => {},
    },
    skipWaiting: () => {},
  },
};
sandbox.self.self = sandbox.self;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync('web/sw.js', 'utf8'), sandbox);

async function click(url) {
  let pending = Promise.resolve();
  listeners.notificationclick({
    notification: { close: () => {}, data: { url } },
    waitUntil: (promise) => { pending = promise; },
  });
  await pending;
}

(async () => {
  const cases = [
    'matches/m1/vote',
    'matches/m1/lineup?section=effectif',
    'admin/administration',
    '.',
    '#/matches/m1',
    '/matches/m1/vote',
    '/AS-Grinta/matches/m1/vote',
    'https://evil.example/x',
    '//evil.example/x',
    'javascript:alert(1)',
    null,
  ];
  const targets = {};
  for (const value of cases) {
    targets[String(value)] = sandbox.notificationTargetUrl(value, scope);
  }

  windows = [];
  await click('matches/m1/vote');
  const withoutWindow = calls.splice(0);

  windows = [{
    url: scope + '#/matches',
    focus: async () => { calls.push(['focus']); },
    navigate: async (url) => { calls.push(['navigate', url]); },
  }];
  await click('admin/administration');
  const withWindow = calls.splice(0);

  windows = [];
  await click('matches/m1/lineup?section=composition');
  await click('matches/m1/lineup?section=effectif');
  const composition = calls.splice(0);

  // Appli ouverte sur une ancienne version : la page s'ouvre tout de suite,
  // puis se recharge sur la version en ligne.
  const openWindow = {
    url: scope + '#/matches',
    focus: async () => { calls.push(['focus']); },
    navigate: async (url) => { calls.push(['navigate', url]); },
  };
  windows = [openWindow];
  deployed = 'newer';
  await click('matches/m1/lineup?section=composition');
  const outdated = calls.splice(0);
  // Déjà à jour : pas de rechargement.
  deployed = 'test';
  await click('matches/m1/vote');
  const upToDate = calls.splice(0);
  deployed = null;

  process.stdout.write(JSON.stringify({
    targets, withoutWindow, withWindow, composition, outdated, upToDate,
  }));
})().catch((error) => { console.error(error); process.exit(1); });
''';

void main() {
  test(
    'un clic sur une notification ouvre la bonne page de l’application',
    () async {
      final result = await Process.run('node', ['-e', _harness]);
      expect(result.exitCode, 0, reason: '${result.stderr}');

      final output =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final targets = output['targets'] as Map<String, dynamic>;
      const home = 'https://samihchaa-wq.github.io/AS-Grinta/';

      expect(targets['matches/m1/vote'], '$home#/matches/m1/vote');
      expect(
        targets['matches/m1/lineup?section=effectif'],
        '$home#/matches/m1/lineup?section=effectif',
      );
      expect(targets['admin/administration'], '$home#/admin/administration');
      expect(targets['.'], home);
      expect(targets['#/matches/m1'], '$home#/matches/m1');
      expect(targets['/matches/m1/vote'], '$home#/matches/m1/vote');
      expect(targets['/AS-Grinta/matches/m1/vote'], '$home#/matches/m1/vote');
      expect(targets['https://evil.example/x'], home);
      expect(targets['//evil.example/x'], home);
      expect(targets['javascript:alert(1)'], home);
      expect(targets['null'], home);

      expect(output['withoutWindow'], [
        ['openWindow', '$home#/matches/m1/vote'],
      ]);
      // Une compo ouverte depuis sa notification lance sa vidéo ; les autres
      // pages restent inchangées.
      expect(output['composition'], [
        [
          'openWindow',
          '$home#/matches/m1/lineup?section=composition&from=notification',
        ],
        ['openWindow', '$home#/matches/m1/lineup?section=effectif'],
      ]);
      expect(output['outdated'], [
        [
          'navigate',
          '$home#/matches/m1/lineup?section=composition&from=notification',
        ],
        ['focus'],
        [
          'navigate',
          '$home?_asg_release=newer'
              '#/matches/m1/lineup?section=composition&from=notification',
        ],
      ]);
      expect(output['upToDate'], [
        ['navigate', '$home#/matches/m1/vote'],
        ['focus'],
      ]);
      expect(output['withWindow'], [
        ['navigate', '$home#/admin/administration'],
        ['focus'],
      ]);
    },
  );
}
