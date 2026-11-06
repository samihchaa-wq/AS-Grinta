import 'package:as_grinta/features/sports_management/domain/admin_match_selection.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:flutter_test/flutter_test.dart';

AdminSportMatch _match(String id, DateTime kickoffAt) {
  return AdminSportMatch(
    id: id,
    opponentName: 'Adversaire $id',
    kickoffAt: kickoffAt,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 11, 12);

  group('defaultAdminMatchId', () {
    test('ouvre le prochain match à jouer, pas le plus lointain', () {
      // L'ordre est celui du serveur : coup d'envoi décroissant.
      final matches = [
        _match('lointain', now.add(const Duration(days: 28))),
        _match('prochain', now.add(const Duration(days: 3))),
        _match('joue', now.subtract(const Duration(days: 4))),
      ];

      expect(defaultAdminMatchId(matches, now: now), 'prochain');
    });

    test('ne dépend pas de l’ordre de la liste reçue', () {
      final matches = [
        _match('joue', now.subtract(const Duration(days: 4))),
        _match('prochain', now.add(const Duration(days: 3))),
        _match('lointain', now.add(const Duration(days: 28))),
      ];

      expect(defaultAdminMatchId(matches, now: now), 'prochain');
    });

    test('retombe sur le dernier match joué quand aucun n’est à venir', () {
      final matches = [
        _match('ancien', now.subtract(const Duration(days: 30))),
        _match('recent', now.subtract(const Duration(days: 2))),
      ];

      expect(defaultAdminMatchId(matches, now: now), 'recent');
    });

    test('un match qui commence maintenant reste le prochain', () {
      final matches = [
        _match('maintenant', now),
        _match('joue', now.subtract(const Duration(days: 1))),
      ];

      expect(defaultAdminMatchId(matches, now: now), 'maintenant');
    });

    test('rend null sans aucun match', () {
      expect(defaultAdminMatchId(const [], now: now), isNull);
    });
  });
}
