import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/calendar_history_repository.dart';
import 'package:flutter/material.dart';

/// Carte de rencontre en lecture seule pour un match de l'historique importé
/// (pas de navigation vers une fiche match : ces rencontres n'ont ni
/// composition, ni pronostics, ni vote HDM en base).
class HistoricalMatchCard extends StatelessWidget {
  const HistoricalMatchCard({required this.match, super.key});

  final HistoricalMatchResult match;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF20242C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF626A78), width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 12, 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 52,
                child: _HistoricalDateColumn(date: match.date),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: AppTheme.textSecondary.withValues(alpha: .25),
              ),
              Expanded(
                child: MatchFixture(
                  homeName: match.isHome ? 'AS Grinta' : match.opponentName,
                  awayName: match.isHome ? match.opponentName : 'AS Grinta',
                  grintaIsHome: match.isHome,
                  homeScore:
                      match.isHome ? match.grintaScore : match.opponentScore,
                  awayScore:
                      match.isHome ? match.opponentScore : match.grintaScore,
                  finished: true,
                  nameStyle: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 17, height: 1.1),
                  scoreFontSize: 20,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoricalDateColumn extends StatelessWidget {
  const _HistoricalDateColumn({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final main = Theme.of(context).textTheme.bodyMedium?.color;
    const soft = AppTheme.textSecondary;

    Widget line(String text, {bool bold = false}) => Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bold ? main : soft,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            fontSize: 14,
            height: 1.15,
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line(AppFormats.weekdayShort(date)),
        line(AppFormats.dayNumber(date), bold: true),
        line(AppFormats.monthShort(date)),
        line('${date.year}'),
      ],
    );
  }
}
