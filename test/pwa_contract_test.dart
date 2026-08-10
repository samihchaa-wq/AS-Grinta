import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contrat PWA', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final index = File('web/index.html').readAsStringSync();
    final shell = File('web/app_shell.js').readAsStringSync();
    final worker = File('web/sw.js').readAsStringSync();
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final versionScript = File('web/build_version.js').readAsStringSync();

    test('la version web correspond à la version de l’application', () {
      final appVersion = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      final webVersion = RegExp(
        r"AS_GRINTA_WEB_VERSION\s*=\s*'([^']+)'",
      ).firstMatch(versionScript)?.group(1);

      expect(appVersion, isNotNull);
      expect(webVersion, appVersion);
    });

    test('index et service worker partagent la même source de version', () {
      expect(index, contains('<script src="build_version.js"></script>'));
      expect(shell, contains('window.AS_GRINTA_WEB_VERSION'));
      expect(index, isNot(matches(RegExp(r'\?v=\d+'))));
      expect(worker, contains("importScripts('build_version.js')"));
      expect(worker, contains('AS_GRINTA_WEB_VERSION'));
    });

    test('le bootstrap applicatif est externe et compatible avec la CSP', () {
      expect(index, contains('<script src="app_shell.js" defer></script>'));
      expect(index, contains('Content-Security-Policy'));
      expect(index, contains("object-src 'none'"));
      expect(
        index,
        contains(
          "connect-src 'self' https://ovzijmqrnsgcmryinkfa.supabase.co",
        ),
      );
      expect(index, isNot(contains('<script>')));
    });

    test('un seul service worker est enregistré', () {
      expect(bootstrap, contains('_flutter.loader.load();'));
      expect(bootstrap, isNot(contains('serviceWorkerSettings')));
      expect(shell, contains("'sw.js?v='"));
    });

    test('le socle minimal et la navigation sont prévus hors ligne', () {
      expect(worker, contains('const APP_SHELL'));
      expect(worker, contains("'index.html'"));
      expect(worker, contains("'app_shell.js'"));
      expect(worker, contains("'flutter_bootstrap.js'"));
      expect(worker, contains("request.mode === 'navigate'"));
    });

    test(
      'les ressources statiques ne bloquent plus systématiquement sur le réseau',
      () {
        expect(worker, contains('staleWhileRevalidate'));
        expect(worker, contains('if (cached)'));
        expect(worker, contains('event.waitUntil(refresh)'));
        expect(worker, contains('mustStayFresh'));
      },
    );

    test(
      'la mise à jour se déclenche automatiquement, sans action requise',
      () {
        expect(shell, contains("aria-live', 'polite'"));
        expect(
          shell,
          contains("worker.postMessage({ type: 'SKIP_WAITING' })"),
        );
        expect(shell, isNot(contains("document.createElement('button')")));
      },
    );
  });
}
