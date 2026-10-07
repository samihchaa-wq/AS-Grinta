import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/match_detail_header_card.dart';
import 'package:as_grinta/core/widgets/match_sheet_top_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _bannerKey = ValueKey<String>('banner');

Widget _sheet() => Scaffold(
      body: ListView(
        children: const [
          MatchSheetTopRow(
            header: SizedBox(key: _bannerKey, height: 90),
          ),
        ],
      ),
    );

void main() {
  testWidgets(
    'la fiche place la flèche à gauche du bandeau, sans barre ni écusson',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/matches',
        routes: [
          GoRoute(
            path: '/matches',
            builder: (_, __) => Scaffold(
              appBar: GrintaAppBar(title: const Text('Calendrier')),
              body: const SizedBox(key: ValueKey<String>('calendar')),
            ),
          ),
          GoRoute(path: '/fiche', builder: (_, __) => _sheet()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.push('/fiche');
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(grintaClubHomeBadgeKey), findsNothing);
      final back = find.byType(BackButton);
      expect(back, findsOneWidget);

      final backRect = tester.getRect(back);
      final bannerRect = tester.getRect(find.byKey(_bannerKey));
      expect(bannerRect.left, greaterThanOrEqualTo(backRect.right));
      // Flèche centrée verticalement sur le bandeau, tout en haut de l'écran.
      expect(backRect.center.dy, closeTo(bannerRect.center.dy, 0.5));
      expect(bannerRect.top, lessThan(10));

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/matches');
    },
  );

  testWidgets('sans écran précédent, la flèche ramène au calendrier', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/fiche',
      routes: [
        GoRoute(
          path: '/matches',
          builder: (_, __) => const SizedBox(key: ValueKey<String>('calendar')),
        ),
        GoRoute(path: '/fiche', builder: (_, __) => _sheet()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/matches');
    expect(find.byKey(const ValueKey<String>('calendar')), findsOneWidget);
  });

  testWidgets(
    'la flèche se colle au bord gauche et reste cliquable jusqu’au bord',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/fiche',
        routes: [
          GoRoute(
            path: '/matches',
            builder: (_, __) => const SizedBox(),
          ),
          GoRoute(
            path: '/fiche',
            builder: (_, __) => Scaffold(
              body: MatchSheetListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: const [
                  MatchSheetTopRow(
                    header: SizedBox(key: _bannerKey, height: 90),
                  ),
                  SizedBox(key: ValueKey<String>('content'), height: 40),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final icon = tester.getRect(
        find.descendant(
          of: find.byType(BackButton),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.left, MatchSheetBackButton.edgeInset);
      // Le reste de la fiche garde sa marge.
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('content'))).left,
        16,
      );

      // Un appui sur la pointe de la flèche, près du bord, est bien pris.
      await tester.tapAt(Offset(icon.left + 2, icon.center.dy));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/matches');
    },
  );

  testWidgets(
    'le bandeau des fiches ne coupe jamais un texte par « … »',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: MatchDetailHeaderCard(
                homeName:
                    'Association Sportive Rouffiac Tolosan Football Club Loisir '
                    'Vétérans du Dimanche Matin',
                awayName: 'AS Grinta',
                grintaIsHome: false,
                kickoffAt: DateTime(2026, 11, 2, 20, 45),
                typeLabel: 'Championnat · J12',
                address: 'Complexe sportif municipal Jean Bouin - 12 avenue '
                    'des Sports - Bâtiment B - 31130 - Balma',
                compact: true,
              ),
            ),
          ),
        ),
      );

      final texts = tester.widgetList<Text>(find.byType(Text));
      for (final text in texts) {
        expect(text.overflow, isNot(TextOverflow.ellipsis),
            reason: '« ${text.data} » ne doit pas être coupé');
        expect(text.maxLines, isNull, reason: '« ${text.data} »');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('noms et écusson ont la même taille sur toutes les fiches', (
    tester,
  ) async {
    Future<CalendarScoreline> scorelineOf(MatchDetailHeaderCard card) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox(width: 330, child: card))),
      );
      return tester.widget<CalendarScoreline>(find.byType(CalendarScoreline));
    }

    final kickoff = DateTime(2026, 10, 12, 20, 45);
    final past = await scorelineOf(
      MatchDetailHeaderCard(
        homeName: 'AS Grinta',
        awayName: 'Positive Vibration',
        grintaIsHome: true,
        homeScore: 2,
        awayScore: 1,
        finished: true,
        kickoffAt: kickoff,
        compact: true,
      ),
    );
    final upcoming = await scorelineOf(
      MatchDetailHeaderCard(
        homeName: 'AS Grinta',
        awayName: 'Foot Ça-Me-Dit',
        grintaIsHome: true,
        kickoffAt: kickoff,
        compact: true,
      ),
    );

    for (final scoreline in [past, upcoming]) {
      expect(scoreline.nameSize, MatchDetailHeaderCard.compactNameSize);
      expect(scoreline.crestSize, MatchDetailHeaderCard.compactCrestSize);
    }
    expect(
      MatchDetailHeaderCard.compactNameSize,
      lessThan(CalendarTeamName.regularSize),
    );
    expect(
      MatchDetailHeaderCard.compactCrestSize,
      lessThan(CalendarScoreline.regularCrestSize),
    );
  });
}
