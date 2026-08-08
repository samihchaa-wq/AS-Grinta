import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Carte de rencontre en lecture seule pour un match de l'historique importé.
/// Un tap ouvre la fiche archivée (composition, buteurs, HDM) quand elle
/// existe ; ces rencontres n'ont ni pronostics ni vote HDM en base.
class HistoricalMatchCard extends StatelessWidget {
  const HistoricalMatchCard({required this.match, super.key});

  final HistoricalMatchResult match;

  @override
  Widget build(BuildContext context) {
    final isHome = match.isHome;
    final homeName = isHome ? 'AS Grinta' : match.opponentName;
    final awayName = isHome ? match.opponentName : 'AS Grinta';
    final homeScore = isHome ? match.grintaScore : match.opponentScore;
    final awayScore = isHome ? match.opponentScore : match.grintaScore;
    final nameStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontSize: 16,
      height: 1.1,
      fontWeight: FontWeight.w800,
    );

    return Card(
      color: CalendarCardPalette.finishedSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
          color: CalendarCardPalette.finishedBorder,
          width: 1.3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/history/${match.id}', extra: match),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: MatchDateHeader(
            kickoffAt: match.date,
            foreground: AppTheme.textPrimary,
            showTime: false,
            child: MatchFixture(
              homeName: homeName,
              awayName: awayName,
              grintaIsHome: isHome,
              homeScore: homeScore,
              awayScore: awayScore,
              finished: true,
              nameStyle: nameStyle,
              scoreFontSize: 20,
              textAlign: TextAlign.start,
            ),
          ),
        ),
      ),
    );
  }
}
