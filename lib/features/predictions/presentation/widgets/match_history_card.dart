import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Version réutilisable de la carte « Dernier match » pour chaque rencontre
/// passée de l'historique.
class MatchHistoryCard extends ConsumerWidget {
  const MatchHistoryCard({
    required this.match,
    this.adminActions,
    super.key,
  });

  final MatchModel match;
  final Widget? adminActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vote = ref.watch(sportMotmVoteProvider(match.id)).valueOrNull;
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final homeScore =
        match.isHome ? match.grintaScore ?? 0 : match.opponentScore ?? 0;
    final awayScore =
        match.isHome ? match.opponentScore ?? 0 : match.grintaScore ?? 0;

    return Card(
      color: const Color(0xFF20242C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF626A78), width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push('/matches/${match.id}'),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MatchDateHeader(
                    kickoffAt: match.kickoffAt,
                    secondary: AppTheme.textSecondary,
                    child: Row(
                      children: [
                        Expanded(
                          child: MatchFixture(
                            homeName: homeName,
                            awayName: awayName,
                            grintaIsHome: match.isHome,
                            homeScore: homeScore,
                            awayScore: awayScore,
                            finished: true,
                            nameStyle: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (adminActions != null) ...[
                          const SizedBox(width: 6),
                          adminActions!,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Voir la fiche du match',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFFCAB5FF),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (vote != null && vote.isOpen && vote.isEligibleVoter) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFF3A414D),
            ),
            InkWell(
              onTap: () => context.push('/matches/${match.id}/vote'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_vote_outlined,
                      color: Color(0xFFCAB5FF),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vote.hasVoted
                                ? 'Ton vote HDM est enregistré'
                                : 'Voter pour l’homme du match',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            vote.hasVoted
                                ? 'Appuie pour consulter le scrutin.'
                                : 'Choisis un joueur depuis la composition.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFCAB5FF),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
