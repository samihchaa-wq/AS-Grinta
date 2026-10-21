import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
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
    final actions = adminActions;
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
    final fixture = match.isInternal
        ? const CalendarCenteredTitle('Match entre nous')
        // Scores colorés selon le résultat d'AS Grinta : vert victoire,
        // orange nul, rouge défaite.
        : CalendarScoreline(
            homeName: homeName,
            awayName: awayName,
            grintaIsHome: match.isHome,
            homeScore: homeScore,
            awayScore: awayScore,
            finished: match.isFinished,
          );

    final content = CalendarCardActionsOverlay(
      actions: actions,
      child: CalendarCardSections(
        header: CalendarDateLine(
          kickoffAt: match.kickoffAt,
          label: match.isInternal ? null : match.calendarTypeLabel,
          endInset: actions != null ? CalendarCardActionsOverlay.dateInset : 0,
        ),
        bodyBottomPadding:
            match.isCancelled ? CalendarCardSpacing.cancelledBodyBottom : null,
        body: match.isCancelled
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fixture,
                  const SizedBox(height: CalendarCardSpacing.cancelledLabelGap),
                  const CalendarCancelledLabel(),
                ],
              )
            : fixture,
        footer: address != null && address.isNotEmpty
            ? CalendarAddressLine(address)
            : null,
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
      // informative, et un match annulé n'a plus rien à ouvrir : pas de
      // navigation ni d'indication visuelle cliquable.
      child: isFinishedInternal || match.isCancelled
          ? content
          : InkWell(
              onTap: () => context.push('/matches/${match.id}'),
              child: content,
            ),
    );
  }
}
