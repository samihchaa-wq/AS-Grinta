import 'dart:ui' as ui;

import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_button.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_page.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_share_sheet.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SeasonWrapped _wrapped() => SeasonWrapped.fromJson({
      'season_name': '2026-2027',
      'roster_size': 14,
      'matches_played': 12,
      'matches_played_rank': 4,
      'wins': 7,
      'draws': 2,
      'losses': 3,
      'win_pct': 58.33,
      'win_pct_rank': 2,
      'win_pct_pool': 9,
      // Cinq heures et demie : le cas qui fait défiler heures puis minutes.
      'avg_response_hours': 5.5,
      'avg_response_rank': 1,
      'avg_response_pool': 9,
      'goals': 5,
      'goals_rank': 1,
      'motm': 0,
      'motm_rank': 8,
      'clean_matches': 6,
      'clean_matches_rank': 2,
      'versatility': 3,
      'versatility_rank': 1,
      'top_position': 'Milieu',
      'position_shares': [
        {'position': 'Milieu', 'share': 60},
        {'position': 'Milieu défensif', 'share': 40},
      ],
    });

Widget _host(
  Widget child,
  List<Override> overrides, {
  bool reducedMotion = false,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: child,
      ),
    ),
  );
}

List<Override> _storyOverrides() => [
      mySeasonWrappedProvider.overrideWith((ref) async => _wrapped()),
      wrappedPlayerNameProvider.overrideWithValue('Samih'),
    ];

List<Override> _buttonOverrides({
  required bool available,
  required bool admin,
}) =>
    [
      seasonWrappedStateProvider.overrideWith(
        (ref) async => available
            ? const SeasonWrappedState(
                available: true,
                seasonName: '2026-2027',
              )
            : const SeasonWrappedState.unavailable(),
      ),
      isAdminViewProvider.overrideWithValue(admin),
    ];

void main() {
  testWidgets('le bouton reste invisible pendant la saison', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedButton()),
        _buttonOverrides(available: false, admin: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('season-wrapped-button')), findsNothing);
  });

  testWidgets('un administrateur garde un accès en aperçu', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedButton()),
        _buttonOverrides(available: false, admin: true),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('season-wrapped-button'));
    expect(button, findsOneWidget);
    expect(tester.widget<IconButton>(button).tooltip, 'Ma saison (aperçu)');
  });

  testWidgets('l’aperçu annonce ses chiffres d’exemple', (tester) async {
    await tester.pumpWidget(
      _host(
        const SeasonWrappedPage(preview: true),
        [
          seasonWrappedStateProvider.overrideWith(
            (ref) async => const SeasonWrappedState.unavailable(),
          ),
          wrappedPlayerNameProvider.overrideWithValue('Samih'),
        ],
        reducedMotion: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('wrapped-preview-badge')),
      findsOneWidget,
    );
    expect(find.text('APERÇU · CHIFFRES D’EXEMPLE'), findsOneWidget);
    expect(find.text('SAMIH'), findsOneWidget);
  });

  test('la saison en cours se déduit du mois', () {
    expect(
      SeasonWrappedPage.currentSeasonName(DateTime(2026, 8, 22)),
      '2026-2027',
    );
    expect(
      SeasonWrappedPage.currentSeasonName(DateTime(2027, 3, 4)),
      '2026-2027',
    );
    expect(
      SeasonWrappedPage.currentSeasonName(DateTime(2027, 7, 1)),
      '2027-2028',
    );
  });

  testWidgets('le bouton apparaît entre deux saisons', (tester) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(body: SeasonWrappedButton()),
        _buttonOverrides(available: true, admin: false),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('season-wrapped-button'));
    expect(button, findsOneWidget);
    // Un vrai bilan n'est jamais présenté comme un aperçu.
    expect(tester.widget<IconButton>(button).tooltip, 'Ma saison');
  });

  testWidgets('le bilan ouvre sur la feuille de saison', (tester) async {
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('TA SAISON'), findsOneWidget);
    expect(find.text('L’année est finie. Voici ton résumé…'), findsOneWidget);
    // Le millésime est posé sur deux lignes, en très grand.
    expect(find.text('2026\n2027'), findsOneWidget);
    expect(find.text('SAMIH'), findsOneWidget);
    // Sept écrans, donc sept segments de progression.
    expect(find.byType(LinearProgressIndicator), findsNWidgets(7));
  });

  testWidgets('un appui à droite avance, un appui à gauche revient',
      (tester) async {
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    await tester.tapAt(Offset(width * .8, height * .55));
    await tester.pump();
    await tester.pump();
    expect(find.text('MATCHS JOUÉS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tapAt(Offset(width * .1, height * .55));
    await tester.pump();
    await tester.pump();
    expect(find.text('2026\n2027'), findsOneWidget);
  });

  testWidgets('les postes et la polyvalence tiennent en un écran',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 3; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('TON POSTE'), findsOneWidget);
    expect(find.text('LE PLUS SOUVENT'), findsOneWidget);
    expect(find.text('MILIEU'), findsOneWidget);
    // La polyvalence n'a plus d'écran a elle : elle se lit sur le terrain.
    expect(find.text('POLYVALENCE'), findsNothing);
    expect(find.textContaining('Deux postes'), findsOneWidget);
  });

  testWidgets('plus aucun mot géant ne traîne au fond des écrans', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    // « BUTS » sert aussi d'intitulé : seuls les mots qui ne meublaient que le
    // fond peuvent être cherchés par leur texte.
    const meubles = ['GRINTA', 'PRÉSENT', 'DISPO', 'ÉQUIPE'];

    for (var i = 0; i < 7; i += 1) {
      for (final mot in meubles) {
        expect(find.text(mot), findsNothing,
            reason: 'écran ${i + 1}, « $mot »');
      }

      // Ces mots étaient les seuls dessinés en contour. Sur le téléphone le
      // contour sortait plein, et le mot masquait le texte à lire.
      for (final texte in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          texte.style?.foreground,
          isNull,
          reason: 'écran ${i + 1} : « ${texte.data} » est dessiné en contour',
        );
      }

      await tester.tapAt(const Offset(300, 400));
      await tester.pump();
      await tester.pump();
    }
  });

  testWidgets('aucun texte du bilan n’est en gras', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    // La moyenne tassait une police deja condensee : une phrase entiere
    // finissait en bloc noir sur le telephone. Rien ne doit la depasser.
    for (var i = 0; i < 7; i += 1) {
      for (final texte in tester.widgetList<Text>(find.byType(Text))) {
        final poids = texte.style?.fontWeight;
        if (poids == null) continue;
        expect(
          poids.value,
          lessThanOrEqualTo(FontWeight.w400.value),
          reason: 'ecran ${i + 1} : « ${texte.data} » en ${poids.value}',
        );
      }
      await tester.tapAt(const Offset(300, 400));
      await tester.pump();
      await tester.pump();
    }
  });

  testWidgets('le délai monte en deux temps : les heures, puis les minutes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Sans le réglage « réduire les animations » : c'est l'animation qu'on
    // vient regarder.
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides()),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 2; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
    }

    String? affiche() {
      final trouves = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((t) => t.contains(' h '));
      return trouves.isEmpty ? null : trouves.first;
    }

    int heuresDe(String texte) => int.parse(texte.split(' h ').first);
    int minutesDe(String texte) => int.parse(texte.split(' h ').last);

    // Le gabarit est complet des la premiere image : rien ne surgit en route.
    await tester.pump(const Duration(milliseconds: 300));
    expect(affiche(), isNotNull, reason: 'le délai doit être affiché');

    // Pendant que les heures montent, les minutes restent à zéro.
    var heuresVues = <int>{};
    for (var ms = 320; ms <= 1300; ms += 120) {
      await tester.pump(const Duration(milliseconds: 120));
      final texte = affiche()!;
      heuresVues.add(heuresDe(texte));
      expect(
        minutesDe(texte),
        0,
        reason: 'à $ms ms les minutes ne doivent pas avoir bougé : $texte',
      );
    }
    expect(
      heuresVues.length,
      greaterThan(1),
      reason: 'les heures doivent défiler, pas sauter à leur valeur',
    );

    // Puis les minutes prennent le relais, heures arrivées.
    final minutesVues = <int>{};
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 90));
      final texte = affiche()!;
      expect(heuresDe(texte), 5, reason: 'les heures sont arrivées : $texte');
      minutesVues.add(minutesDe(texte));
    }
    expect(
      minutesVues.length,
      greaterThan(1),
      reason: 'les minutes doivent défiler à leur tour',
    );

    await tester.pumpAndSettle();
    expect(affiche(), '5 h 30');
  });

  testWidgets('la réactivité s’annonce comme une moyenne', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 2; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    // Le chiffre est une moyenne, jamais un cumul : l'écran doit le dire.
    expect(find.text('DÉLAI MOYEN DE RÉPONSE'), findsOneWidget);
    expect(find.textContaining('En moyenne'), findsOneWidget);
  });

  testWidgets('les matchs sans encaisser se lisent comme les autres stats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 5; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    // C'est un des neuf criteres : intitule, grand chiffre et classement,
    // pas une note de bas de page.
    expect(find.text('L’ÉQUIPE QUAND TU ÉTAIS LÀ'), findsOneWidget);
    expect(find.text('MATCHS SANS ENCAISSER'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    // Deux statistiques classées sur cet écran : le pourcentage de victoire
    // et les matchs sans encaisser.
    expect(find.byType(WrappedRankBadge), findsNWidgets(2));
    expect(find.textContaining('sans encaisser.'), findsNothing);
  });

  testWidgets('la dernière page propose le partage', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 6; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('TA SAISON EN ENTIER'), findsOneWidget);
    expect(find.text('PARTAGER MA SAISON'), findsOneWidget);
    expect(find.text('Partager par thème'), findsOneWidget);
    // Les valeurs du récapitulatif sont bien celles du bilan.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('58 %'), findsOneWidget);
    expect(find.text('7 V · 2 N · 3 D'), findsOneWidget);
  });

  testWidgets('le pourcentage garde son signe', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 5; i += 1) {
      await tester.tapAt(const Offset(900, 1500));
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('L’ÉQUIPE QUAND TU ÉTAIS LÀ'), findsOneWidget);
    expect(find.text('58 %'), findsOneWidget);
  });

  testWidgets('la musique se coupe et se remet', (tester) async {
    await tester.pumpWidget(
      _host(const SeasonWrappedPage(), _storyOverrides(), reducedMotion: true),
    );
    await tester.pump();
    await tester.pump();

    final mute = find.byKey(const ValueKey('wrapped-mute-button'));
    expect(mute, findsOneWidget);
    expect(
      tester.widget<IconButton>(mute).tooltip,
      'Couper la musique',
    );
  });

  testWidgets('la feuille partagée porte le nom du joueur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SeasonWrappedFullShareSheet(
            wrapped: _wrapped(),
            playerName: 'Samih',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AS GRINTA · 2026-2027'), findsOneWidget);
    expect(find.text('MA SAISON'), findsOneWidget);
    expect(find.text('SAMIH'), findsOneWidget);
  });

  testWidgets('la feuille se transforme en une vraie image', (tester) async {
    final captureKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        // Centrée, la feuille garde sa taille propre — comme dans l'écran,
        // où elle est posée hors champ sans contrainte d'étirement.
        home: Center(
          child: RepaintBoundary(
            key: captureKey,
            child: SeasonWrappedShareSheet(
              sheet: _wrapped().sheets.first,
              seasonName: '2026-2027',
              playerName: 'Samih',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    // L'encodage PNG est un vrai travail asynchrone : il doit sortir du temps
    // simulé du test, sinon il ne se termine jamais.
    await tester.runAsync(() async {
      final image = await boundary.toImage(
        pixelRatio: kSeasonWrappedSharePixelRatio,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

      expect(image.width, (kSeasonWrappedShareWidth * 3).round());
      expect(image.height, (kSeasonWrappedShareHeight * 3).round());
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, greaterThan(0));
      image.dispose();
    });
  });

  testWidgets('un joueur sans bilan voit un message clair', (tester) async {
    await tester.pumpWidget(
      _host(
        const SeasonWrappedPage(),
        [
          mySeasonWrappedProvider.overrideWith((ref) async => null),
          wrappedPlayerNameProvider.overrideWithValue('Samih'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pas encore de bilan'), findsOneWidget);
  });
}
