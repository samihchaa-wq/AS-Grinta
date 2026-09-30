import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_admin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _commonBadge = BadgeDef(
  code: 'goals_all_time__1',
  name: 'Buteur',
  description: 'Badge commun',
  emoji: '⚽',
  imageUrl: null,
  color: '#123456',
  family: 'joueur',
  kind: 'tier',
  category: 'all_time',
  metric: 'goals_all_time',
  threshold: 1,
  sortOrder: 1,
);

const _roleBadge = BadgeDef(
  code: 'role_goalkeeper',
  name: 'Gardien',
  description: 'Badge de rôle visible',
  emoji: '🧤',
  imageUrl: null,
  color: '#123456',
  family: 'joueur',
  kind: 'custom',
  category: 'all_time',
  metric: null,
  threshold: null,
  sortOrder: 2,
);

const _mysteryBadge = BadgeDef(
  code: 'custom_clutch_1',
  name: 'Clutch',
  description: 'Badge mystère',
  emoji: '🏅',
  imageUrl: null,
  color: '#F97316',
  family: 'joueur',
  kind: 'custom',
  category: 'faits_de_jeu',
  metric: null,
  threshold: null,
  sortOrder: 3,
);

const _secretBadge = BadgeDef(
  code: 'secret_test',
  name: 'Secret',
  description: 'Badge secret',
  emoji: '❓',
  imageUrl: null,
  color: '#F97316',
  family: 'joueur',
  kind: 'tier',
  category: 'faits_de_jeu',
  metric: 'secret_metric',
  threshold: 1,
  sortOrder: 4,
  secret: true,
);

void main() {
  testWidgets('le menu badges est séparé en trois sections', (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          badgeCatalogProvider.overrideWith(
            (ref) async => const [
              _commonBadge,
              _roleBadge,
              _mysteryBadge,
              _secretBadge,
            ],
          ),
        ],
        child: const MaterialApp(home: BadgeAdminPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Badges communs'), findsOneWidget);
    expect(find.text('Badges mystères'), findsOneWidget);
    expect(find.text('Création de badge'), findsOneWidget);

    expect(find.text('Buteur'), findsOneWidget);
    expect(find.text('Gardien'), findsOneWidget);
    expect(find.text('Clutch'), findsNothing);
    expect(find.text('Secret'), findsNothing);

    await tester.tap(find.text('Badges mystères'));
    await tester.pumpAndSettle();

    expect(find.text('Buteur'), findsNothing);
    expect(find.text('Gardien'), findsNothing);
    expect(find.text('Clutch'), findsOneWidget);
    expect(find.text('Secret'), findsOneWidget);

    await tester.tap(find.text('Création de badge'));
    await tester.pumpAndSettle();

    expect(find.text('Créer un badge'), findsOneWidget);
    expect(find.text('Nom du badge'), findsOneWidget);
  });
}
