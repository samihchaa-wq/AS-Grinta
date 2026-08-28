import 'dart:async';

import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pre_kickoff_page.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tableau Blanc : préparation du coup d’envoi', () {
    testWidgets(
      'le dispositif se change avant le coup d’envoi',
      (tester) async {
        await _pump(tester, bundle: _bundle(fieldPlayers: 1));

        expect(find.text('Dispositif'), findsOneWidget);
        expect(
          find.byType(DropdownButtonFormField<String>),
          findsOneWidget,
          reason: 'sans ce menu, un mauvais dispositif ne se corrige qu’une '
              'fois le match lancé',
        );
      },
    );

    testWidgets(
      'un terrain vide explique comment placer les titulaires',
      (tester) async {
        await _pump(tester, bundle: _bundle(fieldPlayers: 0));

        expect(
          find.textContaining('Aucun titulaire n’est encore placé'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un spectateur ne voit ni dispositif ni bouton de démarrage',
      (tester) async {
        await _pump(
          tester,
          bundle: _bundle(fieldPlayers: 1),
          canEdit: false,
        );

        expect(find.text('Dispositif'), findsNothing);
        expect(find.text('Démarrer le match'), findsNothing);
      },
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required MatchLiveStateBundle bundle,
  bool canEdit = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchLiveRepositoryProvider.overrideWithValue(
          _StubMatchLiveRepository(bundle),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MatchLivePreKickoffPage(
              matchId: 'match-1',
              bundle: bundle,
              canEdit: canEdit,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

MatchLiveStateBundle _bundle({required int fieldPlayers}) {
  return MatchLiveStateBundle.fromRpc({
    'match_id': 'match-1',
    'session_exists': true,
    'state': 'not_started',
    'planned_duration_minutes': 90,
    'half': 1,
    'elapsed_seconds': 0,
    'score_as_grinta': 0,
    'score_adverse': 0,
    'exported': false,
    'lineup_revision': 3,
    'events': const [],
    'substitute_counts': const <String, int>{},
    'lineup': {
      'match_id': 'match-1',
      'formation_code': '4-2-1-3',
      'status': 'draft',
      'version': 0,
      'has_unpublished_changes': true,
      'squad_size_exception_approved': false,
      'entries': [
        for (var index = 0; index < fieldPlayers; index += 1)
          {
            'participant_id': 'field-$index',
            'season_player_id': 'sp-field-$index',
            'display_name': 'Titulaire $index',
            'is_goalkeeper': index == 0,
            'zone': 'field',
            'x': .5,
            'y': .85,
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

/// Les écrans testés ici ne déclenchent aucun appel réseau au premier rendu :
/// ce dépôt renvoie toujours le même état et sert uniquement à satisfaire le
/// contrôleur Riverpod.
class _StubMatchLiveRepository implements MatchLiveRepository {
  _StubMatchLiveRepository(this._bundle);

  final MatchLiveStateBundle _bundle;

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) async => _bundle;

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
    if (invocation.memberName == #deleteExportedTimeline) {
      return Future<int>.value(0);
    }
    if (invocation.memberName == #publishRecap) {
      return Future<SportMatchFinalization>.error(
        UnimplementedError('publishRecap'),
      );
    }
    return Future<MatchLiveStateBundle>.value(_bundle);
  }
}
