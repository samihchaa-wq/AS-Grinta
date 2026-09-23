import 'dart:typed_data';

import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_admin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBadgeAdminRepository implements BadgeAdminRepository {
  _FakeBadgeAdminRepository(this.holders);

  final Set<String> holders;
  final List<(String, String)> awarded = [];

  @override
  Future<Set<String>> fetchAwardees(String badgeCode) async => {...holders};

  @override
  Future<void> awardBadge(String code, String profileId) async {
    awarded.add((code, profileId));
  }

  @override
  Future<List<AdminPerson>> fetchActiveProfiles() => throw UnimplementedError();

  @override
  Future<void> createCustomBadge({
    required String name,
    required Uint8List imageBytes,
    String description = '',
  }) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> downloadBadgeImage(String imageUrl) =>
      throw UnimplementedError();

  @override
  Future<void> replaceBadgeImage({
    required String badgeCode,
    required Uint8List bytes,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadBadgeImage(Uint8List bytes, String fileExt) =>
      throw UnimplementedError();
}

const _clutch = BadgeDef(
  code: 'custom_clutch_1',
  name: 'Clutch',
  description: 'Marquer le but de la victoire dans les dernières minutes.',
  emoji: '🏅',
  imageUrl: null,
  color: kCustomBadgeColorHex,
  family: 'joueur',
  kind: 'custom',
  category: 'faits_de_jeu',
  metric: null,
  threshold: null,
  sortOrder: 1,
);

const _people = [
  AdminPerson(id: 'aki', name: 'Aki'),
  AdminPerson(id: 'flo', name: 'Flo'),
  AdminPerson(id: 'milan', name: 'Milan'),
];

Future<void> _openAwardSheet(
  WidgetTester tester,
  _FakeBadgeAdminRepository repository,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        badgeCatalogProvider.overrideWith((ref) async => const [_clutch]),
        adminPeopleProvider.overrideWith((ref) async => _people),
        badgeAdminRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: BadgeAdminPage()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Clutch'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Décerner ce badge'));
  await tester.pumpAndSettle();
}

Finder _awardButtonOf(String name) => find.descendant(
      of: find.widgetWithText(ListTile, name),
      matching: find.widgetWithText(FilledButton, 'Décerner'),
    );

void main() {
  testWidgets(
      'seules les personnes sans le badge sont proposées, sans case à cocher',
      (tester) async {
    final repository = _FakeBadgeAdminRepository({'milan'});
    await _openAwardSheet(tester, repository);

    expect(find.byType(Checkbox), findsNothing);
    expect(find.widgetWithText(ListTile, 'Aki'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Flo'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Milan'), findsNothing);
    expect(find.text('Déjà décerné à 1 personne.'), findsOneWidget);
  });

  testWidgets('une attribution confirmée retire la personne de la liste',
      (tester) async {
    final repository = _FakeBadgeAdminRepository({'milan'});
    await _openAwardSheet(tester, repository);

    await tester.tap(_awardButtonOf('Aki'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ne pourra plus lui être retiré'), findsOne);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Décerner'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.awarded, [('custom_clutch_1', 'aki')]);
    expect(find.widgetWithText(ListTile, 'Aki'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Flo'), findsOneWidget);
    expect(find.text('Déjà décerné à 2 personnes.'), findsOneWidget);
  });

  testWidgets('annuler la confirmation ne décerne rien', (tester) async {
    final repository = _FakeBadgeAdminRepository({});
    await _openAwardSheet(tester, repository);

    await tester.tap(_awardButtonOf('Flo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(repository.awarded, isEmpty);
    expect(find.widgetWithText(ListTile, 'Flo'), findsOneWidget);
    expect(find.text('Encore décerné à personne.'), findsOneWidget);
  });

  testWidgets('quand tout le monde a le badge, la liste le dit',
      (tester) async {
    final repository = _FakeBadgeAdminRepository({'aki', 'flo', 'milan'});
    await _openAwardSheet(tester, repository);

    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Tout le monde a déjà ce badge.'), findsOneWidget);
  });
}
