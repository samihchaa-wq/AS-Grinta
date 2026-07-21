import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('is completely hidden when the feature flag is disabled', (
    tester,
  ) async {
    final repository = _FakeAvailabilityRepository();
    await tester.pumpWidget(_harness(repository, enabled: false));
    await tester.pumpAndSettle();

    expect(find.text('Ta disponibilité'), findsNothing);
    expect(repository.fetchCount, 0);
  });

  testWidgets('records Present and refreshes the shared server state', (
    tester,
  ) async {
    final repository = _FakeAvailabilityRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.text('Ta disponibilité'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Présent'));
    await tester.pumpAndSettle();

    expect(repository.lastStatus, MatchAvailabilityStatus.available);
    expect(find.text('Présent enregistré.'), findsOneWidget);
  });

  testWidgets('records Absent with an optional private reason', (tester) async {
    final repository = _FakeAvailabilityRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Absent'));
    await tester.pumpAndSettle();
    expect(find.text('Signaler ton absence'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField),
      'Déplacement professionnel',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Confirmer mon absence'),
    );
    await tester.pumpAndSettle();

    expect(repository.lastStatus, MatchAvailabilityStatus.absent);
    expect(repository.lastComment, 'Déplacement professionnel');
  });
}

Widget _harness(MatchAvailabilityRepository repository, {bool enabled = true}) {
  return ProviderScope(
    overrides: [
      sportsManagementEnabledProvider.overrideWithValue(enabled),
      matchAvailabilityRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: Scaffold(body: MatchAvailabilitySelector(matchId: 'match-1')),
    ),
  );
}

class _FakeAvailabilityRepository implements MatchAvailabilityRepository {
  MatchAvailabilityStatus? lastStatus;
  String? lastComment;
  int fetchCount = 0;

  MatchAvailability _value({
    MatchAvailabilityStatus status = MatchAvailabilityStatus.noResponse,
    String? privateComment,
  }) {
    return MatchAvailability(
      matchId: 'match-1',
      participantId: 'participant-1',
      seasonPlayerId: 'player-1',
      isEligible: true,
      status: status,
      privateComment: privateComment,
      updatedAt: DateTime.utc(2026, 7, 20, 12),
      availabilityState: 'open',
      opensAt: DateTime.utc(2026, 7, 20, 8),
      kickoffAt: DateTime.utc(2026, 7, 26, 8),
      canRespond: true,
      compositionState: 'none',
    );
  }

  @override
  Future<MatchAvailability> fetchMyAvailability(String matchId) async {
    fetchCount += 1;
    return _value(
      status: lastStatus ?? MatchAvailabilityStatus.noResponse,
      privateComment: lastComment,
    );
  }

  @override
  Future<MatchAvailability> setMyAvailability({
    required String matchId,
    required MatchAvailabilityStatus status,
    String? privateComment,
  }) async {
    lastStatus = status;
    lastComment =
        privateComment?.trim().isEmpty == true ? null : privateComment?.trim();
    return _value(status: status, privateComment: lastComment);
  }
}
