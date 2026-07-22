import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('is hidden and performs no RPC when the flag is disabled', (
    tester,
  ) async {
    final repository = _FakeCompositionRepository();
    await tester.pumpWidget(_harness(repository, enabled: false));
    await tester.pumpAndSettle();

    expect(find.text('Composition publiée'), findsNothing);
    expect(repository.publishedFetchCount, 0);
  });

  testWidgets('shows the latest published composition', (tester) async {
    final repository = _FakeCompositionRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.text('Composition publiée'), findsOneWidget);
    expect(find.textContaining('4-3-3'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Remplaçants (1)'), findsOneWidget);
    expect(repository.publishedFetchCount, 1);
  });
}

Widget _harness(MatchCompositionRepository repository, {bool enabled = true}) {
  return ProviderScope(
    overrides: [
      sportsManagementEnabledProvider.overrideWithValue(enabled),
      matchCompositionRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PublishedLineupCard(matchId: 'match-1')),
    ),
  );
}

class _FakeCompositionRepository implements MatchCompositionRepository {
  int publishedFetchCount = 0;

  MatchComposition get _published => const MatchComposition(
        matchId: 'match-1',
        formationCode: '4-3-3',
        status: 'published',
        version: 1,
        hasUnpublishedChanges: false,
        squadSizeExceptionApproved: false,
        entries: [
          MatchCompositionEntry(
            participantId: 'participant-1',
            seasonPlayerId: 'player-1',
            displayName: 'Alex Gardien',
            isGoalkeeper: true,
            zone: MatchCompositionZone.field,
            x: 0.5,
            y: 0.9,
            sortOrder: 0,
            availabilityStatus: 'available',
            convocationStatus: 'convoked',
            selectionStatus: 'starter',
          ),
          MatchCompositionEntry(
            participantId: 'participant-2',
            seasonPlayerId: 'player-2',
            displayName: 'Sam Banc',
            isGoalkeeper: false,
            zone: MatchCompositionZone.bench,
            sortOrder: 0,
            availabilityStatus: 'available',
            convocationStatus: 'convoked',
            selectionStatus: 'substitute',
          ),
        ],
      );

  @override
  Future<MatchComposition?> fetchPublishedComposition(String matchId) async {
    publishedFetchCount += 1;
    return _published;
  }

  @override
  Future<MatchComposition?> fetchAdminComposition(String matchId) async {
    return _published;
  }

  @override
  Future<Set<String>> fetchGoalkeeperSeasonPlayerIds(
    List<String> seasonPlayerIds,
  ) async {
    return const {'player-1'};
  }

  @override
  Future<MatchComposition> publishComposition({
    required String matchId,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    return _published;
  }

  @override
  Future<MatchComposition> saveComposition({
    required MatchComposition composition,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    return composition;
  }
}
