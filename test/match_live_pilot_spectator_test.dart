import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pilot.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_tab.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le pilote n'est plus simulé par un état local : le faux dépôt reproduit la
/// réponse du serveur (personne / ce téléphone / un autre téléphone).
void main() {
  group('Live : pilote et spectateur', () {
    testWidgets('un joueur voit directement le live, sans la barre', (
      tester,
    ) async {
      await _pump(tester, state: 'running', coach: false);

      expect(find.text('Spectateur'), findsNothing);
      expect(find.text('Piloter'), findsNothing);
      expect(find.text('Faits de match'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
    });

    testWidgets('un coach arrive en spectateur, prend puis libère la place', (
      tester,
    ) async {
      final container = await _pump(tester, state: 'running');
      LivePilot pilot() => container.read(livePilotProvider('match-1'));

      expect(find.text('Spectateur'), findsOneWidget);
      expect(find.text('Faits de match'), findsOneWidget);
      expect(find.text('Reset'), findsNothing);
      expect(pilot(), LivePilot.nobody);

      await tester.tap(find.text('Piloter'));
      await _settle(tester);
      expect(find.text('Reset'), findsOneWidget);
      expect(pilot(), LivePilot.me);

      await tester.tap(find.text('Spectateur'));
      await _settle(tester);
      expect(pilot(), LivePilot.nobody);
      expect(find.text('Faits de match'), findsOneWidget);
    });

    testWidgets('un autre téléphone bloque le pilotage puis peut céder la main',
        (
      tester,
    ) async {
      final container = await _pump(
        tester,
        state: 'running',
        otherPilot: true,
      );

      await tester.tap(find.text('Piloter'));
      await _settle(tester);

      expect(
        find.text('Quelqu’un d’autre pilote déjà le Live'),
        findsOneWidget,
      );
      expect(container.read(livePilotProvider('match-1')), LivePilot.other);
      expect(find.text('Reset'), findsNothing);

      await tester.tap(find.text('Prendre la main'));
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Prendre la main'),
        ),
      );
      await _settle(tester);

      expect(container.read(livePilotProvider('match-1')), LivePilot.me);
      expect(find.text('Reset'), findsOneWidget);
    });

    testWidgets(
      'avant le coup d’envoi : spectateur voit la composition, pilote prépare',
      (tester) async {
        await _pump(tester, state: 'not_started');

        expect(find.text('Le match n’a pas encore démarré'), findsOneWidget);
        expect(find.text('Démarrer le match'), findsNothing);

        await tester.tap(find.text('Piloter'));
        await _settle(tester);
        expect(find.text('Démarrer le match'), findsOneWidget);
      },
    );
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String state,
  bool coach = true,
  bool otherPilot = false,
}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final repository = _StubRepository(
    state: state,
    otherPilot: otherPilot,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchLiveRepositoryProvider.overrideWithValue(repository),
        isMatchCoachOrAdminProvider.overrideWith((ref, matchId) async => coach),
        upcomingMatchFixtureProvider.overrideWith(
          (ref, matchId) async => null,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MatchLiveTab(matchId: 'match-1')),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MatchLiveTab)),
  );
  await _settle(tester);
  return container;
}

MatchLiveStateBundle _bundle(
  String state, {
  bool pilotActive = false,
  bool pilotIsMe = false,
}) {
  return MatchLiveStateBundle.fromRpc({
    'match_id': 'match-1',
    'session_exists': true,
    'state': state,
    'planned_duration_minutes': 90,
    'half': 1,
    'elapsed_seconds': 600,
    'score_as_grinta': 0,
    'score_adverse': 0,
    'exported': false,
    'lineup_revision': 3,
    'pilot_active': pilotActive,
    'pilot_is_me': pilotIsMe,
    'events': const [],
    'substitute_counts': const <String, int>{'bench-0': 1},
    'lineup': {
      'match_id': 'match-1',
      'formation_code': '4-2-1-3',
      'status': 'published',
      'version': 1,
      'has_unpublished_changes': false,
      'squad_size_exception_approved': false,
      'entries': [
        for (var index = 0; index < 2; index += 1)
          {
            'participant_id': 'field-$index',
            'season_player_id': 'sp-field-$index',
            'display_name': 'Titulaire $index',
            'is_goalkeeper': index == 0,
            'zone': 'field',
            'x': .5,
            'y': index == 0 ? .9 : .5,
            'sort_order': index,
            'availability_status': 'available',
            'convocation_status': 'convoked',
            'selection_status': 'starter',
          },
        {
          'participant_id': 'bench-0',
          'season_player_id': 'sp-bench-0',
          'display_name': 'Remplaçant',
          'is_goalkeeper': false,
          'zone': 'bench',
          'sort_order': 0,
          'availability_status': 'available',
          'convocation_status': 'convoked',
          'selection_status': 'substitute',
        },
      ],
    },
  });
}

class _StubRepository implements MatchLiveRepository {
  _StubRepository({required this.state, required bool otherPilot})
      : _pilotActive = otherPilot,
        _pilotIsMe = false;

  final String state;
  bool _pilotActive;
  bool _pilotIsMe;

  MatchLiveStateBundle get _current => _bundle(
        state,
        pilotActive: _pilotActive,
        pilotIsMe: _pilotIsMe,
      );

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) async => _current;

  @override
  Future<MatchLiveStateBundle> claimPilot({
    required String matchId,
    int? plannedDurationMinutes,
  }) async {
    if (!_pilotActive) {
      _pilotActive = true;
      _pilotIsMe = true;
    }
    return _current;
  }

  @override
  Future<MatchLiveStateBundle> takeOverPilot({required String matchId}) async {
    _pilotActive = true;
    _pilotIsMe = true;
    return _current;
  }

  @override
  Future<MatchLiveStateBundle> heartbeatPilot({required String matchId}) async {
    return _current;
  }

  @override
  Future<MatchLiveStateBundle> releasePilot({required String matchId}) async {
    if (_pilotIsMe) {
      _pilotActive = false;
      _pilotIsMe = false;
    }
    return _current;
  }

  @override
  Stream<void> watchChanges(String matchId) => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchTimeline) {
      return Future<MatchLiveTimeline?>.value(null);
    }
    if (invocation.memberName == #fetchAddPlayerOptions) {
      return Future<MatchLiveAddPlayerOptions>.value(
        MatchLiveAddPlayerOptions.fromRpc(const <String, dynamic>{}),
      );
    }
    return Future<MatchLiveStateBundle>.value(_current);
  }
}
