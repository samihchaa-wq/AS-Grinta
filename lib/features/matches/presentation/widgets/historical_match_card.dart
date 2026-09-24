import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
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
    final cleanAddress = match.address?.trim();
    final surface = CalendarCardPalette.matchSurface(
      match.matchType,
      unknownAsFinished: true,
    );
    final border = CalendarCardPalette.matchBorder(
      match.matchType,
      unknownAsFinished: true,
    );

    return Card(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border, width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/history/${match.id}', extra: match),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            12,
            CalendarCardSpacing.vertical,
            12,
            CalendarCardSpacing.vertical,
          ),
          child: MatchDateHeader(
            gap: CalendarCardSpacing.line,
            kickoffAt: match.date,
            foreground: AppTheme.textPrimary,
            secondary: AppTheme.textPrimary,
            dividerColor: border,
            showTime: match.hasTime,
            label: match.calendarTypeLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CalendarScoreline(
                  homeName: homeName,
                  awayName: awayName,
                  grintaIsHome: isHome,
                  homeScore: homeScore,
                  awayScore: awayScore,
                  finished: true,
                ),
                if (cleanAddress != null && cleanAddress.isNotEmpty) ...[
                  const SizedBox(height: CalendarCardSpacing.line),
                  InkWell(
                    onTap: () => showMatchAddressSheet(context, cleanAddress),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              cleanAddress,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 17,
                            color: border,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
