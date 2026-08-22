import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/data/wrapped_music.dart';
import 'package:flutter/services.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload({
  int matchesPlayed = 12,
  num? winPct = 58.33,
  int? winPctRank = 2,
  int? winPctPool = 9,
  num? avgResponseHours = 5,
  int? avgResponseRank = 3,
  int? avgResponsePool = 9,
  String? topPosition = 'Milieu',
}) {
  return {
    'season_name': '2026-2027',
    'roster_size': 14,
    'matches_played': matchesPlayed,
    'matches_played_rank': 4,
    'wins': 7,
    'draws': 2,
    'losses': 3,
    'win_pct': winPct,
    'win_pct_rank': winPctRank,
    'win_pct_pool': winPctPool,
    'avg_response_hours': avgResponseHours,
    'avg_response_rank': avgResponseRank,
    'avg_response_pool': avgResponsePool,
    'goals': 5,
    'goals_rank': 1,
    'motm': 0,
    'motm_rank': 8,
    'clean_matches': 6,
    'clean_matches_rank': 2,
    'versatility': 3,
    'versatility_rank': 1,
    'top_position': topPosition,
    'position_shares': [
      {'position': 'Milieu', 'share': 70},
      {'position': 'Attaquant', 'share': 30},
    ],
  };
}

SeasonWrappedStat _stat(SeasonWrapped wrapped, String label) =>
    wrapped.stats.firstWhere((stat) => stat.label == label);

void main() {
  // Le lecteur avale silencieusement une piste absente : sans ce test, un
  // fichier renomme couperait la musique sans que personne le remarque.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la piste du bilan est bien embarquee', () async {
    final data = await rootBundle.load('assets/${WrappedMusic.assetPath}');

    expect(data.lengthInBytes, greaterThan(0));
    // Au-dela de deux megaoctets, l'ouverture du bilan traine sur un reseau
    // lent : la piste doit rester courte et compressee.
    expect(data.lengthInBytes, lessThan(2 * 1024 * 1024));
  });
  test('la répartition des postes est lue et ordonnée', () {
    final wrapped = SeasonWrapped.fromJson(_payload());

    expect(wrapped.positionShares, hasLength(2));
    expect(wrapped.positionShares.first.position, 'Milieu');
    expect(wrapped.positionShares.first.share, 70);
    expect(wrapped.positionShares.last.share, 30);
  });

  test('un joueur jamais titularisé n’a aucune répartition', () {
    final json = _payload()..remove('position_shares');

    expect(SeasonWrapped.fromJson(json).positionShares, isEmpty);
  });

  test('les neuf critères tiennent en trois feuilles', () {
    final wrapped = SeasonWrapped.fromJson(_payload());

    expect(wrapped.sheets, hasLength(3));
    expect(
      wrapped.sheets.map((sheet) => sheet.title),
      ['Ma présence', 'Mon apport', 'Mes résultats'],
    );

    // Les neuf critères, et eux seuls, se répartissent dans les feuilles.
    final criteres = [for (final f in wrapped.sheets) ...f.stats];
    expect(criteres, hasLength(9));
    // Aucun critère ne se perd ni ne se répète entre deux feuilles.
    expect(criteres.map((stat) => stat.label).toSet(), hasLength(9));

    // Le récapitulatif y ajoute les badges, qui ne sont pas un critère et ne
    // figurent donc dans aucune feuille à partager.
    expect(wrapped.stats, hasLength(10));
    expect(wrapped.stats.last.label, 'Badges décrochés');
    expect(wrapped.stats.last.rank, isNull);
  });

  test('un critère classé porte le rang et la taille du classement', () {
    final wrapped = SeasonWrapped.fromJson(_payload());
    final matches = _stat(wrapped, 'Matchs joués');

    expect(matches.value, '12');
    expect(matches.rank, 4);
    expect(matches.isRanked, isTrue);
  });

  test('le poste et le bilan V/N/D ne sont jamais classés', () {
    final wrapped = SeasonWrapped.fromJson(_payload());

    expect(_stat(wrapped, 'Poste le plus joué').isRanked, isFalse);
    expect(_stat(wrapped, 'Poste le plus joué').value, 'Milieu');
    expect(_stat(wrapped, 'Victoires, nuls, défaites').isRanked, isFalse);
    expect(
        _stat(wrapped, 'Victoires, nuls, défaites').value, '7 V · 2 N · 3 D');
  });

  test(
    'sous le seuil, le pourcentage reste affiché mais perd son rang',
    () {
      final wrapped = SeasonWrapped.fromJson(
        _payload(
          matchesPlayed: 3,
          winPct: 100,
          winPctRank: null,
          winPctPool: null,
        ),
      );
      final winPct = _stat(wrapped, 'Pourcentage de victoire');

      expect(winPct.value, '100 %');
      expect(winPct.isRanked, isFalse);
      expect(winPct.note, contains('moins de huit matchs'));
    },
  );

  test('un joueur qui n’a jamais répondu n’affiche pas de délai', () {
    final wrapped = SeasonWrapped.fromJson(
      _payload(
        avgResponseHours: null,
        avgResponseRank: null,
        avgResponsePool: null,
      ),
    );
    final response = _stat(wrapped, 'Réactivité aux disponibilités');

    expect(response.value, 'Aucune réponse');
    expect(response.isRanked, isFalse);
    expect(response.note, isNull);
  });

  test('un joueur jamais aligné au coup d’envoi le voit écrit', () {
    final wrapped = SeasonWrapped.fromJson(_payload(topPosition: null));

    expect(
      _stat(wrapped, 'Poste le plus joué').value,
      'Jamais aligné au coup d’envoi',
    );
  });

  test('le délai de réponse s’écrit en heures et minutes', () {
    String delayFor(num hours) => _stat(
          SeasonWrapped.fromJson(_payload(avgResponseHours: hours)),
          'Réactivité aux disponibilités',
        ).value;

    // Sous l'heure, la minute suffit.
    expect(delayFor(0.5), '30 min');
    expect(delayFor(0.7), '42 min');
    // Une heure ronde ne s'encombre pas d'un « 00 ».
    expect(delayFor(6), '6 h');
    expect(delayFor(6.5), '6 h 30');
    // Les minutes s'écrivent sur deux chiffres.
    expect(delayFor(6.08), '6 h 05');
    // Au-delà de la journée, on reste en heures plutôt qu'en jours.
    expect(delayFor(30.5), '30 h 30');
    expect(delayFor(72), '72 h');
    // Une réponse quasi immédiate ne doit pas produire « 0 h ».
    expect(delayFor(0), '0 min');
    // Le report de 60 minutes ne doit jamais donner « 6 h 60 ».
    expect(delayFor(6.999), '7 h');
  });

  test('la polyvalence s’accorde au singulier', () {
    final json = _payload()..['versatility'] = 1;

    expect(_stat(SeasonWrapped.fromJson(json), 'Polyvalence').value, '1 poste');
  });

  test('le rang s’écrit en ordinal français, sans effectif', () {
    expect(wrappedOrdinal(1), '1er');
    expect(wrappedOrdinal(2), '2e');
    expect(wrappedOrdinal(11), '11e');
  });

  test('un état sans bilan disponible ne propose pas de saison', () {
    final state = SeasonWrappedState.fromJson({'available': false});

    expect(state.available, isFalse);
    expect(state.seasonName, isNull);
  });
}
