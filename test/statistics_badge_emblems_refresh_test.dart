import 'package:as_grinta/core/sync/shared_data_sync.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:as_grinta/features/badges/presentation/armoire_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les badges affichés à côté des prénoms (classements, statistiques) sont lus
/// par `statisticsBadgeEmblemsProvider`. Ce test vérifie qu'ils sont bien
/// relus quand un joueur change le badge qu'il arbore, et lors de la
/// synchronisation des données partagées.
void main() {
  test('la synchronisation des données partagées relit ces badges', () async {
    var loads = 0;
    final container = ProviderContainer(
      overrides: [
        statisticsBadgeEmblemsProvider.overrideWith((ref) async {
          loads += 1;
          return const <String, List<StatisticsBadgeEmblemData>>{};
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(statisticsBadgeEmblemsProvider, (_, __) {});
    await container.read(statisticsBadgeEmblemsProvider.future);
    expect(loads, 1);

    container
        .read(sharedDataRefreshCoordinatorProvider)
        .invalidateForSessionChange();
    await container.read(statisticsBadgeEmblemsProvider.future);

    expect(loads, 2);
  });

  testWidgets('arborer un badge dans l’armoire relit ces badges',
      (tester) async {
    var loads = 0;
    final repository = _FakeFeaturedBadgesRepository();
    final container = ProviderContainer(
      overrides: [
        statisticsBadgeEmblemsProvider.overrideWith((ref) async {
          loads += 1;
          return const <String, List<StatisticsBadgeEmblemData>>{};
        }),
        featuredBadgesRepositoryProvider.overrideWithValue(repository),
        myArmoireProvider.overrideWith(
          (ref) async => const Armoire(
            validated: [
              ArmoireBadge(def: _badge, state: BadgeState.validated),
            ],
            inProgress: [],
            locked: [],
          ),
        ),
        myFeaturedCodesProvider.overrideWith((ref) async => <String>{}),
        isAdminViewProvider.overrideWithValue(false),
      ],
    );
    container.listen(statisticsBadgeEmblemsProvider, (_, __) {});
    await container.read(statisticsBadgeEmblemsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ArmoirePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arborer ce badge'));
    await tester.pumpAndSettle();

    expect(repository.calls, [('buteur_or', true)]);
    expect(loads, 2);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}

const _badge = BadgeDef(
  code: 'buteur_or',
  name: 'Buteur or',
  description: 'Dix buts en une saison.',
  emoji: '⚽',
  imageUrl: null,
  color: null,
  family: 'joueur',
  kind: 'tier',
  category: 'saison',
  metric: null,
  threshold: 10,
  sortOrder: 1,
);

class _FakeFeaturedBadgesRepository implements FeaturedBadgesRepository {
  final calls = <(String, bool)>[];

  @override
  Future<void> setFeatured(String badgeCode, bool featured) async {
    calls.add((badgeCode, featured));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
