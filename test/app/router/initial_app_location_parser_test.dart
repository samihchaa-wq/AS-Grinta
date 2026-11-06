import 'package:as_grinta/app/router/initial_app_location_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialLocationFromBrowserHash', () {
    test('keeps a regular Flutter hash route', () {
      expect(
        initialLocationFromBrowserHash('#/matches/123?tab=details'),
        '/matches/123?tab=details',
      );
    });

    test('keeps scanner-safe recovery hash route', () {
      expect(
        initialLocationFromBrowserHash(
          '#/auth/new-password?recovery=1&token_hash=abc123',
        ),
        '/auth/new-password?recovery=1&token_hash=abc123',
      );
    });

    test('routes a successful legacy recovery fragment', () {
      expect(
        initialLocationFromBrowserHash('#type=recovery&expires_in=3600'),
        passwordRecoveryLocation,
      );
    });

    test('does not treat a failed recovery fragment as successful', () {
      expect(
        initialLocationFromBrowserHash(
          '#type=recovery&error=access_denied&error_code=otp_expired',
        ),
        '/matches',
      );
    });

    test('defaults to matches when the hash is unrelated', () {
      expect(initialLocationFromBrowserHash('#foo=bar'), '/matches');
      expect(initialLocationFromBrowserHash(''), '/matches');
    });
  });

  group('initialLocationFromBrowser', () {
    InitialBrowserLocation resolve({
      String hash = '',
      required String pathname,
      String search = '',
    }) {
      return initialLocationFromBrowser(
        hash: hash,
        pathname: pathname,
        search: search,
        basePath: '/AS-Grinta/',
      );
    }

    test('une route sous # garde la priorité, sans réécriture', () {
      final resolved = resolve(
        hash: '#/matches/42/vote',
        pathname: '/AS-Grinta/matches/99/lineup',
      );
      expect(resolved.location, '/matches/42/vote');
      expect(resolved.hashUrl, isNull);
    });

    test('le lien d’inscription en forme chemin ouvre l’inscription', () {
      final resolved = resolve(pathname: '/AS-Grinta/auth/register');
      expect(resolved.location, '/auth/register');
      expect(resolved.hashUrl, '/AS-Grinta/#/auth/register');
    });

    test('une ancienne notification de vote ouvre le vote', () {
      final resolved = resolve(pathname: '/AS-Grinta/matches/m1/vote');
      expect(resolved.location, '/matches/m1/vote');
      expect(resolved.hashUrl, '/AS-Grinta/#/matches/m1/vote');
    });

    test('la requête est conservée, sans le marqueur de mise à jour', () {
      final resolved = resolve(
        pathname: '/AS-Grinta/matches/m1/lineup',
        search: '?section=effectif&_asg_release=0.3.3%2B97',
      );
      expect(resolved.location, '/matches/m1/lineup?section=effectif');
      expect(
        resolved.hashUrl,
        '/AS-Grinta/#/matches/m1/lineup?section=effectif',
      );
    });

    test('un # vide est traité comme une adresse sans route', () {
      final resolved = resolve(
        hash: '#',
        pathname: '/AS-Grinta/admin/administration',
      );
      expect(resolved.location, '/admin/administration');
      expect(resolved.hashUrl, '/AS-Grinta/#/admin/administration');
    });

    test('la racine de l’application reste sur le calendrier', () {
      for (final pathname in [
        '/AS-Grinta/',
        '/AS-Grinta/index.html',
        '/AS-Grinta/404.html',
      ]) {
        final resolved = resolve(pathname: pathname, search: '?code=abc');
        expect(resolved.location, '/matches', reason: pathname);
        expect(resolved.hashUrl, isNull, reason: pathname);
      }
    });

    test('une adresse hors de l’application n’est pas interprétée', () {
      final resolved = resolve(pathname: '/autre/matches/m1');
      expect(resolved.location, '/matches');
      expect(resolved.hashUrl, isNull);
    });

    test('un double slash ne produit jamais une adresse externe', () {
      final resolved = resolve(pathname: '/AS-Grinta//evil.example/x');
      expect(resolved.location, '/evil.example/x');
      expect(resolved.hashUrl, '/AS-Grinta/#/evil.example/x');
    });

    test('le fragment de récupération de mot de passe reste prioritaire', () {
      final resolved = resolve(
        hash: '#type=recovery&expires_in=3600',
        pathname: '/AS-Grinta/',
      );
      expect(resolved.location, passwordRecoveryLocation);
      expect(resolved.hashUrl, isNull);
    });
  });
}
