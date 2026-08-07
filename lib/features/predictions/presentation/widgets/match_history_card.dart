import 'package:as_grinta/core/theme/app_theme.dart';
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
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore = match.isHome ? match.grintaScore : match.opponentScore;
    final awayScore = match.isHome ? match.opponentScore : match.grintaScore;

    return Card(
      color: const Color(0xFF20242C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF626A78), width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 12, 14),
          child: MatchDateHeader(
            kickoffAt: match.kickoffAt,
            secondary: AppTheme.textSecondary,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: MatchFixture(
                    homeName: homeName,
                    awayName: awayName,
                    grintaIsHome: match.isHome,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    finished: match.isFinished,
                    // Même style que _UpcomingMatchCard pour que les
                    // rangées passées et à venir du calendrier aient
                    // exactement la même échelle typographique.
                    nameStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 16,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (actions != null) ...[
                  const SizedBox(width: 2),
                  SizedBox(width: 38, child: actions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
