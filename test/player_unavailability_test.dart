import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:as_grinta/features/unavailability/data/player_unavailability_repository.dart';
import 'package:as_grinta/features/unavailability/domain/player_unavailability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerUnavailability.fromRpc', () {
    test('lit une période complète renvoyée par le serveur', () {
      final period = PlayerUnavailability.fromRpc(<String, dynamic>{
        'id': 'period-1',
        'starts_on': '2026-10-12',
        'ends_on': '2026-10-25',
        'reason': ' Vacances en famille ',
        'created_at': '2026-09-15T10:30:00+00:00',
        'is_past': false,
        'is_current': true,
        'profile_id': 'profile-1',
        'display_name': 'Sami',
      });

      expect(period.id, 'period-1');
      expect(period.reason, 'Vacances en famille');
      expect(period.startsOn, DateTime(2026, 10, 12));
      expect(period.endsOn, DateTime(2026, 10, 25));
      expect(period.isCurrent, isTrue);
      expect(period.isPast, isFalse);
      expect(period.isUpcoming, isFalse);
      expect(period.displayName, 'Sami');
    });

    test('refuse une période sans raison', () {
      expect(
        () => PlayerUnavailability.fromRpc(<String, dynamic>{
          'id': 'period-1',
          'starts_on': '2026-10-12',
          'ends_on': '2026-10-25',
          'reason': '   ',
          'created_at': '2026-09-15T10:30:00+00:00',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('une liste vide reste une liste vide', () {
      expect(PlayerUnavailability.listFromRpc(<Object?>[]), isEmpty);
      expect(PlayerUnavailability.listFromRpc(null), isEmpty);
    });
  });

  group('encodeUnavailabilityDate', () {
    test('envoie une date pleine, jamais un horodatage', () {
      // Un horodatage ferait glisser la période d'un jour selon le fuseau du
      // navigateur : le serveur ne doit recevoir que le jour calendaire.
      expect(encodeUnavailabilityDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(
        encodeUnavailabilityDate(DateTime(2026, 12, 31, 23, 59)),
        '2026-12-31',
      );
    });
  });

  group('formatUnavailabilityPeriod', () {
    final today = DateTime(2026, 9, 15);

    test('une seule journée se dit « le 12 octobre »', () {
      expect(
        formatUnavailabilityPeriod(
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 12),
          today: today,
        ),
        'le 12 octobre',
      );
    });

    test('plusieurs jours se disent « du … au … »', () {
      expect(
        formatUnavailabilityPeriod(
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 25),
          today: today,
        ),
        'du 12 octobre au 25 octobre',
      );
    });

    test('une autre année est précisée', () {
      expect(
        formatUnavailabilityDay(DateTime(2027, 2, 3), today: today),
        '3 février 2027',
      );
    });
  });

  testWidgets(
    'la fiche match explique l’indisponibilité au lieu de masquer le bloc',
    (tester) async {
      final repository = _UnavailableAvailabilityRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sportsManagementEnabledProvider.overrideWithValue(true),
            matchAvailabilityRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MatchAvailabilitySelector(matchId: 'match-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Tu es déclaré indisponible'), findsOneWidget);
      expect(find.text('Vacances en famille'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Présent'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Absent'), findsNothing);
    },
  );
}

class _UnavailableAvailabilityRepository
    implements MatchAvailabilityRepository {
  @override
  Future<MatchAvailability> fetchMyAvailability(String matchId) async {
    return MatchAvailability(
      matchId: 'match-1',
      participantId: 'participant-1',
      seasonPlayerId: 'player-1',
      isEligible: true,
      status: MatchAvailabilityStatus.absent,
      privateComment: 'Vacances en famille',
      updatedAt: DateTime.utc(2026, 10, 10, 12),
      availabilityState: 'open',
      opensAt: DateTime.utc(2026, 10, 14, 10),
      kickoffAt: DateTime.utc(2026, 10, 20, 18),
      canRespond: false,
      compositionState: 'none',
      unavailabilityReason: 'Vacances en famille',
      unavailabilityStartsOn: DateTime(2026, 10, 12),
      unavailabilityEndsOn: DateTime(2026, 10, 25),
    );
  }

  @override
  Future<MatchAvailability> setMyAvailability({
    required String matchId,
    required MatchAvailabilityStatus status,
    String? privateComment,
  }) async {
    throw StateError('Aucune réponse ne doit partir pendant une période.');
  }
}
