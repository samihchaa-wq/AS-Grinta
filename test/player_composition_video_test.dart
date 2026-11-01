import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/player_composition_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Vidéo de la compo côté joueur :
/// - depuis la notification, elle se lance à chaque fois ;
/// - par l'onglet Compo, seulement à la première visite après publication ;
/// - « Aperçu de la vidéo » la relance quand on veut.
void main() {
  setUp(() => debugPresentationBackground = _plainBackground);
  tearDown(() => debugPresentationBackground = null);

  testWidgets('onglet Compo : vidéo à la première visite, pas à la suivante',
      (tester) async {
    final store = _MemoryStore();
    await _pump(tester, store: store);
    expect(find.byType(CompositionPresentationPage), findsOneWidget);
    expect(find.text('Aperçu : personne n’a été prévenu.'), findsNothing);

    await _close(tester);
    await _pump(tester, store: store);
    expect(find.byType(CompositionPresentationPage), findsNothing);
    expect(find.text('Compo publiée'), findsOneWidget);

    await tester.tap(find.text('Aperçu de la vidéo'));
    await _settle(tester);
    expect(find.byType(CompositionPresentationPage), findsOneWidget);
  });

  testWidgets('compo modifiée après la visite : pas de nouvelle vidéo',
      (tester) async {
    final store = _MemoryStore()..seen.add('match-1');
    await _pump(tester, store: store, version: 2);
    expect(find.byType(CompositionPresentationPage), findsNothing);
    expect(find.text('Aperçu de la vidéo'), findsOneWidget);
  });

  testWidgets('depuis la notification : vidéo même déjà vue', (tester) async {
    final store = _MemoryStore()..seen.add('match-1');
    final router = await _pump(tester, store: store, fromNotification: true);
    expect(find.byType(CompositionPresentationPage), findsOneWidget);
    // L'adresse perd sa marque : revenir sur la page ne la relance pas.
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['from'],
      isNull,
    );
  });

  testWidgets('publiée depuis ce téléphone : jamais d’elle-même',
      (tester) async {
    final store = _MemoryStore()..published.add('match-1');
    await _pump(tester, store: store, fromNotification: true);
    expect(find.byType(CompositionPresentationPage), findsNothing);
    expect(find.text('Aperçu de la vidéo'), findsOneWidget);
  });

  test('seules les notifications de compo portent la marque', () {
    expect(
      markCompositionRouteFromNotification(
        '/matches/m1/lineup?section=composition',
      ),
      '/matches/m1/lineup?section=composition&from=notification',
    );
    expect(
      markCompositionRouteFromNotification(
          '/matches/m1/lineup?section=effectif'),
      '/matches/m1/lineup?section=effectif',
    );
    expect(markCompositionRouteFromNotification('/matches/m1/vote'),
        '/matches/m1/vote');
  });
}

class _MemoryStore extends CompositionVideoSeenStore {
  final Set<String> seen = {};
  final Set<String> published = {};

  @override
  Future<bool> hasSeen(String matchId) async => seen.contains(matchId);

  @override
  Future<void> markSeen(String matchId) async => seen.add(matchId);

  @override
  Future<bool> publishedHere(String matchId) async =>
      published.contains(matchId);

  @override
  Future<void> markPublishedHere(String matchId) async =>
      published.add(matchId);
}

Widget _plainBackground(BuildContext context, PresentationCue cue) {
  WidgetsBinding.instance.addPostFrameCallback((_) => cue.onReady());
  return const ColoredBox(color: Colors.black);
}

MatchCompositionEntry _entry(String name, MatchCompositionZone zone) =>
    MatchCompositionEntry(
      participantId: name,
      seasonPlayerId: name,
      displayName: name,
      isGoalkeeper: name == 'Samih',
      zone: zone,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'selected',
      x: .5,
      y: name == 'Samih' ? .9 : .5,
    );

Future<GoRouter> _pump(
  WidgetTester tester, {
  required _MemoryStore store,
  int version = 1,
  bool fromNotification = false,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final composition = MatchComposition(
    matchId: 'match-1',
    formationCode: null,
    status: 'published',
    version: version,
    hasUnpublishedChanges: false,
    squadSizeExceptionApproved: false,
    entries: [
      _entry('Samih', MatchCompositionZone.field),
      _entry('Hakim', MatchCompositionZone.field),
      _entry('Flo', MatchCompositionZone.bench),
    ],
  );
  final router = GoRouter(
    initialLocation: fromNotification
        ? '/matches/match-1/lineup?section=composition&from=notification'
        : '/matches/match-1/lineup?section=composition',
    routes: [
      GoRoute(
        path: '/matches/:id/lineup',
        builder: (context, state) => Scaffold(
          body: PlayerCompositionTab(
            matchId: 'match-1',
            fromNotification: state.uri.queryParameters['from'] ==
                compositionOpenedFromNotification,
            lineup: const Text('Compo publiée'),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        compositionVideoSeenStoreProvider.overrideWithValue(store),
        publishedMatchCompositionProvider('match-1').overrideWith(
          (ref) async => composition,
        ),
        upcomingMatchFixtureProvider('match-1').overrideWith(
          (ref) async => null,
        ),
        matchAvailabilityBoardProvider('match-1').overrideWith(
          (ref) async => null,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.text('Passer'));
  await tester.pump();
  await tester.tap(find.byTooltip('Fermer'));
  await _settle(tester);
  expect(find.byType(CompositionPresentationPage), findsNothing);
}
