import 'package:as_grinta/core/utils/match_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// Balayage exhaustif des règles temporelles d'un match.
///
/// Les tests de `match_window_test.dart` vérifient une poignée de dates
/// choisies à la main. Ici on balaie chaque jour sur plusieurs années, ce qui
/// couvre les quatre bascules d'heure d'été, les passages de mois et d'année,
/// les années bissextiles, et les fins de mois courts (28/29/30/31).
///
/// L'implémentation de référence utilisée ici est volontairement écrite
/// autrement que celle de `match_window.dart` : elle part de l'instant absolu
/// et cherche quel décalage rend l'heure civile cohérente, au lieu de déduire
/// le décalage de la date civile. Les deux fonctions privées du fichier de
/// production (`_parisOffsetAt`, appliquée au coup d'envoi, et
/// `_parisOffsetForLocalNoon`, appliquée au midi J-6) doivent rester d'accord
/// entre elles ; c'est exactement ce que ce croisement met à l'épreuve.

/// Dernier dimanche du mois, calculé indépendamment du code de production.
int _lastSunday(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  for (var day = lastDay; day > 0; day--) {
    if (DateTime.utc(year, month, day).weekday == DateTime.sunday) return day;
  }
  throw StateError('mois sans dimanche');
}

/// Décalage Europe/Paris à un instant absolu donné.
Duration _offsetAt(DateTime utc) {
  final start = DateTime.utc(
      utc.year, DateTime.march, _lastSunday(utc.year, DateTime.march), 1);
  final end = DateTime.utc(
      utc.year, DateTime.october, _lastSunday(utc.year, DateTime.october), 1);
  final summer = !utc.isBefore(start) && utc.isBefore(end);
  return Duration(hours: summer ? 2 : 1);
}

/// Heure civile parisienne correspondant à un instant absolu.
DateTime _parisLocal(DateTime utc) => utc.toUtc().add(_offsetAt(utc.toUtc()));

/// Instant absolu d'un midi civil parisien, trouvé par recherche du décalage
/// cohérent plutôt que par déduction depuis la date. Midi n'étant jamais dans
/// l'heure sautée ni dans l'heure doublée, la solution est unique.
DateTime _parisNoonUtc(int year, int month, int day) {
  final candidates = <DateTime>[
    DateTime.utc(year, month, day, 12).subtract(const Duration(hours: 1)),
    DateTime.utc(year, month, day, 12).subtract(const Duration(hours: 2)),
  ];
  final valid = candidates
      .where((c) => _parisLocal(c) == DateTime.utc(year, month, day, 12))
      .toList();
  expect(
    valid,
    hasLength(1),
    reason: 'midi Paris du $day/$month/$year doit avoir une solution unique',
  );
  return valid.single;
}

void main() {
  group('espace d’états temporel exhaustif', () {
    test(
      'l’ouverture J-6 tombe toujours exactement à midi Paris, chaque jour de 2025 à 2028',
      () {
        // Heures de coup d'envoi couvrant la journée, dont les extrêmes qui
        // risquent de faire basculer la date civile parisienne.
        const kickoffHoursUtc = [0, 1, 6, 10, 13, 17, 18, 19, 21, 22, 23];
        var checked = 0;

        for (var year = 2025; year <= 2028; year++) {
          for (var month = 1; month <= 12; month++) {
            final daysInMonth = DateTime.utc(year, month + 1, 0).day;
            for (var day = 1; day <= daysInMonth; day++) {
              for (final hour in kickoffHoursUtc) {
                for (final minute in const [0, 30, 45]) {
                  final kickoffUtc =
                      DateTime.utc(year, month, day, hour, minute);
                  final openAt = matchFeaturesOpenAt(kickoffUtc);

                  // 1. L'ouverture doit être un midi civil parisien.
                  final openLocal = _parisLocal(openAt);
                  expect(
                    openLocal.hour,
                    12,
                    reason: 'coup d’envoi $kickoffUtc → ouverture $openAt '
                        '(heure Paris ${openLocal.hour}h${openLocal.minute})',
                  );
                  expect(openLocal.minute, 0,
                      reason: 'coup d’envoi $kickoffUtc');
                  expect(openLocal.second, 0,
                      reason: 'coup d’envoi $kickoffUtc');

                  // 2. Ce midi doit être exactement six jours civils parisiens
                  // avant le jour civil parisien du coup d’envoi.
                  final kickoffLocal = _parisLocal(kickoffUtc);
                  final expectedDate = DateTime.utc(
                    kickoffLocal.year,
                    kickoffLocal.month,
                    kickoffLocal.day,
                  ).subtract(const Duration(days: kMatchOpensDaysBefore));
                  expect(
                    DateTime.utc(
                        openLocal.year, openLocal.month, openLocal.day),
                    expectedDate,
                    reason: 'coup d’envoi $kickoffUtc (Paris $kickoffLocal) : '
                        'ouverture attendue le $expectedDate',
                  );

                  // 3. Croisement avec l’implémentation de référence.
                  expect(
                    openAt,
                    _parisNoonUtc(
                      expectedDate.year,
                      expectedDate.month,
                      expectedDate.day,
                    ),
                    reason: 'coup d’envoi $kickoffUtc',
                  );

                  checked++;
                }
              }
            }
          }
        }

        expect(checked, greaterThan(48000));
        // ignore: avoid_print
        print('STATE_SPACE match_features_open cases=$checked status=passed');
      },
    );

    test(
      'la phase d’affichage ne recule jamais quand le temps avance',
      () {
        // Un match par saison, dont deux collés aux bascules d’heure d’été.
        final kickoffs = <DateTime>[
          DateTime.utc(2026, 1, 17, 14, 30),
          DateTime.utc(2026, 3, 28, 19, 30), // veille de la bascule de mars
          DateTime.utc(2026, 3, 29, 19, 30), // jour de la bascule de mars
          DateTime.utc(2026, 6, 20, 18),
          DateTime.utc(2026, 10, 24, 18), // veille de la bascule d’octobre
          DateTime.utc(2026, 10, 25, 18), // jour de la bascule d’octobre
          DateTime.utc(2026, 12, 31, 20),
          DateTime.utc(2028, 2, 29, 20), // année bissextile
        ];
        const durations = [50, 60, 90];
        const liveStates = <String?>[
          null,
          'idle',
          'running',
          'paused',
          'halftime',
          'finished',
        ];
        const order = {
          MatchDisplayPhase.upcoming: 0,
          MatchDisplayPhase.next: 1,
          MatchDisplayPhase.live: 2,
          MatchDisplayPhase.awaitingValidation: 3,
        };
        var checked = 0;

        for (final kickoff in kickoffs) {
          for (final duration in durations) {
            for (final liveState in liveStates) {
              // À liveState constant, la phase doit être monotone croissante
              // de J-8 à T+5h, échantillonnée toutes les dix minutes.
              var previous = -1;
              for (var offset = -8 * 24 * 60; offset <= 5 * 60; offset += 10) {
                final now = kickoff.add(Duration(minutes: offset));
                final phase = matchDisplayPhase(
                  kickoffAt: kickoff,
                  status: 'a_venir',
                  plannedDurationMinutes: duration,
                  liveState: liveState,
                  now: now,
                );
                final rank = order[phase];
                expect(
                  rank,
                  isNotNull,
                  reason: 'phase inattendue $phase pour un match à venir',
                );
                expect(
                  rank! >= previous,
                  isTrue,
                  reason: 'retour en arrière : $kickoff (durée $duration, '
                      'live $liveState) à T${offset}min → $phase',
                );
                previous = rank;
                checked++;
              }
            }
          }
        }

        // ignore: avoid_print
        print('STATE_SPACE match_phase_monotonic cases=$checked status=passed');
      },
    );

    test(
      'les gardes d’écran restent cohérents avec la phase affichée',
      () {
        final kickoffs = <DateTime>[
          DateTime.utc(2026, 3, 29, 19, 30),
          DateTime.utc(2026, 7, 11, 18),
          DateTime.utc(2026, 10, 25, 18),
          DateTime.utc(2027, 1, 9, 15),
        ];
        var checked = 0;

        for (final kickoff in kickoffs) {
          for (var offset = -8 * 24 * 60; offset <= 5 * 60; offset += 5) {
            final now = kickoff.add(Duration(minutes: offset));
            final phase = matchDisplayPhase(
              kickoffAt: kickoff,
              status: 'a_venir',
              plannedDurationMinutes: 90,
              now: now,
            );

            // « À venir » et seulement « à venir » signifie fiche non ouverte.
            expect(
              isMatchTooFarAway(kickoff, now: now),
              phase == MatchDisplayPhase.upcoming,
              reason: 'fiche vs phase à T${offset}min de $kickoff',
            );

            // Le Live et la fermeture du prono partagent la même frontière,
            // et cette frontière est aussi celle du verrou d’édition admin.
            final liveTooEarly = isMatchLiveTooEarly(kickoff, now: now);
            expect(
              isMatchPredictionClosed(kickoff, now: now),
              !liveTooEarly,
              reason: 'prono vs Live à T${offset}min de $kickoff',
            );
            expect(
              isMatchAdminEditLocked(kickoff, now: now),
              !liveTooEarly,
              reason: 'verrou admin vs Live à T${offset}min de $kickoff',
            );

            // Tant que le Live est trop tôt, la phase ne peut pas être « live ».
            if (liveTooEarly) {
              expect(
                phase,
                isNot(MatchDisplayPhase.live),
                reason: 'phase live avant T-15 pour $kickoff',
              );
            }

            checked++;
          }
        }

        // ignore: avoid_print
        print(
            'STATE_SPACE match_guard_consistency cases=$checked status=passed');
      },
    );

    test(
      'un statut serveur terminal l’emporte sur toutes les temporalités',
      () {
        final kickoff = DateTime.utc(2026, 5, 16, 18);
        var checked = 0;

        for (final status in const ['annule', 'termine', 'archive']) {
          for (final liveState in const <String?>[
            null,
            'running',
            'paused',
            'halftime',
            'finished',
          ]) {
            for (var offset = -10 * 24 * 60;
                offset <= 10 * 24 * 60;
                offset += 60) {
              final phase = matchDisplayPhase(
                kickoffAt: kickoff,
                status: status,
                plannedDurationMinutes: 90,
                liveState: liveState,
                now: kickoff.add(Duration(minutes: offset)),
              );
              expect(
                phase,
                status == 'annule'
                    ? MatchDisplayPhase.cancelled
                    : MatchDisplayPhase.past,
                reason:
                    'statut $status ignoré à T${offset}min (live $liveState)',
              );
              checked++;
            }
          }
        }

        // ignore: avoid_print
        print('STATE_SPACE match_terminal_status cases=$checked status=passed');
      },
    );
  });
}
