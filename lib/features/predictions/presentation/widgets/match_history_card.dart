import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Version réutilisable de la carte « Dernier match » pour chaque rencontre
/// passée de l'historique.
class MatchHistoryCard extends ConsumerWidget {
  const MatchHistoryCard({required this.match, this.adminActions, super.key});

  final MatchModel match;
  final Widget? adminActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = match.isFinished || match.isCancelled ? null : adminActions;
    final isFinishedInternal = match.isInternal && match.isFinished;
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? match.grintaScore : match.opponentScore;
    final awayScore = match.isHome ? match.opponentScore : match.grintaScore;
    final address = match.address?.trim();
    final surface = match.isCancelled
        ? CalendarCardPalette.cancelledSurface
        : CalendarCardPalette.matchSurface(match.matchType);
    final border = match.isCancelled
        ? CalendarCardPalette.cancelledBorder
        : CalendarCardPalette.matchBorder(match.matchType);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 12, 14),
      child: MatchDateHeader(
        kickoffAt: match.kickoffAt,
        foreground: AppTheme.textPrimary,
        secondary: AppTheme.textPrimary,
        dividerColor: border,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (match.isInternal)
                    Text(
                      'Match entre nous',
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 16,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                    )
                  else
                    MatchFixture(
                      homeName: homeName,
                      awayName: awayName,
                      grintaIsHome: match.isHome,
                      homeScore: homeScore,
                      awayScore: awayScore,
                      finished: match.isFinished,
                      // Les scores conservent le code résultat du composant :
                      // vert victoire, orange nul, rouge défaite.
                      nameStyle:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontSize: 16,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                      textAlign: TextAlign.start,
                    ),
                  if (!match.isInternal) ...[
                    const SizedBox(height: 7),
                    Text(
                      match.calendarTypeLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: border,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                  if (address != null && address.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place_outlined, size: 16, color: border),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            textAlign: TextAlign.start,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (actions != null) ...[
              const SizedBox(width: 2),
              SizedBox(width: 38, child: actions),
            ],
          ],
        ),
      ),
    );

    return Card(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border, width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      // Une fois terminé, un « Match entre nous » devient une archive purement
      // informative : pas de navigation ni d'indication visuelle cliquable.
      child: isFinishedInternal
          ? content
          : InkWell(
              onTap: () => context.push('/matches/${match.id}'),
              child: content,
            ),
    );
  }
}
