import 'dart:io';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('date de coup d’envoi', () {
    test('refuse une date passée et accepte une date à venir', () {
      final now = DateTime.utc(2026, 8, 13, 12);

      expect(
        pastKickoffError(now.subtract(const Duration(minutes: 1)), now: now),
        isNotNull,
      );
      expect(pastKickoffError(now, now: now), isNotNull);
      expect(
        pastKickoffError(now.add(const Duration(minutes: 1)), now: now),
        isNull,
      );
      expect(pastKickoffError(null, now: now), isNull);
    });
  });

  group('AppFormats', () {
    test('accorde l’ordinal féminin', () {
      expect(AppFormats.ordinalFeminine(1), '1ʳᵉ');
      expect(AppFormats.ordinalFeminine(2), '2ᵉ');
      expect(AppFormats.ordinalFeminine(40), '40ᵉ');
    });

    test('n’écrit le pluriel qu’à partir de deux', () {
      expect(AppFormats.counted(0, 'but'), '0 but');
      expect(AppFormats.counted(1, 'but'), '1 but');
      expect(AppFormats.counted(2, 'but'), '2 buts');
      expect(AppFormats.counted(1, 'match', 'matchs'), '1 match');
      expect(AppFormats.counted(8, 'match', 'matchs'), '8 matchs');
    });
  });

  group('AuthState', () {
    test('un enregistrement n’est pas un chargement de session', () {
      const saving = AuthState(isLoading: false, isSaving: true);

      // Le routeur n'observe qu'isLoading : un enregistrement de profil ne
      // doit pas renvoyer l'utilisateur sur /auth/loading.
      expect(saving.isLoading, isFalse);
      expect(saving.isBusy, isTrue);
    });

    test('isBusy couvre les deux états', () {
      expect(const AuthState(isLoading: true).isBusy, isTrue);
      expect(
        const AuthState(isLoading: false, isSaving: false).isBusy,
        isFalse,
      );
    });
  });

  group('humanizeError', () {
    test(
      'traduit les deux messages métier qui tombaient dans le générique',
      () {
        expect(
          humanizeError('No published composition to start from'),
          contains('Publie'),
        );
        expect(
          humanizeError('Player is not waiting for an availability response'),
          contains('disponibilité'),
        );
      },
    );

    test('signale un conflit de concurrence sur le code 40001', () {
      final message = humanizeError(
        const PostgrestException(
          message: 'Un autre administrateur a modifié cette composition.',
          code: '40001',
        ),
      );

      expect(message, contains('Recharge'));
      expect(
        message,
        isNot('Une erreur est survenue. Réessaie dans un instant.'),
      );
    });

    test('laisse passer un message serveur déjà rédigé en français', () {
      expect(
        humanizeError(
          'Un autre administrateur a modifié cette composition. '
          'Recharge l’écran avant d’enregistrer.',
        ),
        isNot('Une erreur est survenue. Réessaie dans un instant.'),
      );
    });
  });

  group('AppLogger', () {
    tearDown(() => AppLogger.sink = null);

    test('transmet l’incident au collecteur sans le message d’erreur', () {
      AppIncident? captured;
      AppLogger.sink = (incident) => captured = incident;

      const secret = 'user@example.com password=super-secret';
      final reference = AppLogger.error('auth sign-in', StateError(secret));

      expect(captured, isNotNull);
      expect(captured!.reference, reference);
      expect(captured!.operation, 'auth_sign-in');
      expect(captured!.errorType, 'StateError');
      expect(captured!.appVersion, isNotEmpty);
    });

    test('un collecteur qui échoue ne fait pas échouer la journalisation', () {
      AppLogger.sink = (_) => throw StateError('collecteur indisponible');

      expect(
        () => AppLogger.error('bootstrap.supabase', Exception('boom')),
        returnsNormally,
      );
    });
  });

  group('contrats de gestion des erreurs', () {
    test('le fallback des cotes automatiques reste observable', () {
      final source = File('lib/features/matches/data/matches_repository.dart')
          .readAsStringSync();

      expect(
        source,
        contains("AppLogger.error('matches.preview_odds', error, stackTrace)"),
      );
    });

    test('la modification du profil garde une seule source de vérité', () {
      final source = File('lib/features/auth/data/auth_repository.dart')
          .readAsStringSync();
      final start = source.indexOf('Future<AuthProfile> updateProfile');
      final end = source.indexOf('Future<AuthProfile> uploadProfilePhoto');

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);
      expect(method, contains(".from('profiles')"));
      expect(method, isNot(contains('_client.auth.updateUser')));
    });
  });
}
