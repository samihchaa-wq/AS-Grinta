import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/sports_management/data/internal_match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/internal_match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/internal_team_composition_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _matchId = 'internal-composition-unassign';

void main() {
  testWidgets(
    'un joueur assigné peut être remis dans Non affectés puis sauvegardé',
    (tester) async {
      final repository = _FakeInternalMatchCompositionRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            internalMatchCompositionRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: InternalTeamCompositionView(
                  matchId: _matchId,
                  editable: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Non affectés (1)'), findsOneWidget);

      await tester.tap(find.text('Alex'));
      await tester.pump();

      final unassignedTarget =
          find.byKey(const Key('internal-unassigned-assignment-target'));
      expect(unassignedTarget, findsOneWidget);

      final targetRect = tester.getRect(unassignedTarget);
      await tester.tapAt(targetRect.topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.text('Non affectés (2)'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Enregistrer la composition'),
      );
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      final alex = repository.savedEntries.singleWhere(
        (entry) => entry.participantId == 'p1',
      );
      expect(alex.teamNo, isNull);
    },
  );
}

class _FakeInternalMatchCompositionRepository
    extends InternalMatchCompositionRepository {
  _FakeInternalMatchCompositionRepository()
      : super(
          SupabaseClient(
            'https://example.supabase.co',
            'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  var saveCalls = 0;
  var savedEntries = <InternalCompositionEntry>[];

  InternalMatchComposition current = const InternalMatchComposition(
    matchId: _matchId,
    team1Name: 'Orange mécanique',
    team2Name: 'Bleu nuit',
    team1JerseyId: 'orange',
    team2JerseyId: 'blue',
    entries: [
      InternalCompositionEntry(
        participantId: 'p1',
        displayName: 'Alex',
        isGuest: false,
        isGoalkeeper: false,
        teamNo: 1,
      ),
      InternalCompositionEntry(
        participantId: 'p2',
        displayName: 'Bruno',
        isGuest: false,
        isGoalkeeper: false,
        teamNo: 2,
      ),
      InternalCompositionEntry(
        participantId: 'p3',
        displayName: 'Charlie',
        isGuest: true,
        isGoalkeeper: false,
      ),
    ],
  );

  @override
  Future<InternalMatchComposition?> fetch(String matchId) async => current;

  @override
  Future<InternalMatchComposition> save({
    required String matchId,
    required String team1Name,
    required String team2Name,
    required List<InternalCompositionEntry> entries,
    String team1JerseyId = 'orange',
    String team2JerseyId = 'blue',
  }) async {
    saveCalls += 1;
    savedEntries = List.of(entries);
    current = InternalMatchComposition(
      matchId: matchId,
      team1Name: team1Name,
      team2Name: team2Name,
      team1JerseyId: team1JerseyId,
      team2JerseyId: team2JerseyId,
      entries: List.of(entries),
    );
    return current;
  }
}
