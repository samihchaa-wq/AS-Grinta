import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:flutter/material.dart';

/// En-tête d'une fiche de match terminé — même gabarit qu'il s'agisse d'un
/// match du système Live ou d'un match archivé importé, pour que les deux
/// types de fiches se ressemblent trait pour trait. Seule la valeur de
/// [dateLabel] varie selon ce que la source de données sait réellement dire
/// (heure de coup d'envoi exacte pour un match Live, date seule pour une
/// archive) : la mise en page reste strictement identique.
class MatchDetailHeaderCard extends StatelessWidget {
  const MatchDetailHeaderCard({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    required this.homeScore,
    required this.awayScore,
    required this.dateLabel,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final int homeScore;
  final int awayScore;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MatchFixture(
              homeName: homeName,
              awayName: awayName,
              grintaIsHome: grintaIsHome,
              homeScore: homeScore,
              awayScore: awayScore,
              finished: true,
              nameStyle: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(dateLabel),
          ],
        ),
      ),
    );
  }
}
