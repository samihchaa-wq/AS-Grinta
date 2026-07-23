import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeLastMatchCard extends ConsumerWidget {
  const HomeLastMatchCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(homeDashboardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        dashboard.when(
          loading: () => const _LoadingCard(),
          error: (_, __) => const _MessageCard(
            title: 'Chargement impossible',
            icon: Icons.wifi_off_rounded,
            message: 'Tire pour rafraîchir.',
            tone: GrintaEmptyTone.alert,
          ),
          data: (data) {
            final match = data.lastMatch;
            if (match == null) {
              return const _MessageCard(
                title: 'Aucun match joué',
                message:
                    'Le résultat et la compo s\'afficheront après le premier '
                    'match de la saison.',
              );
            }
            return _LastMatchContent(match: match);
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 20),
          const SizedBox(width: 8),
          Text(
            'Dernier match',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _LastMatchContent extends ConsumerWidget {
  const _LastMatchContent({required this.match});

  final HomeMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(matchDetailsProvider(match.id));
    final voteAsync = ref.watch(sportMotmVoteProvider(match.id));
    final lastProno = ref.watch(myLastPronoProvider).valueOrNull;

    return detailsAsync.when(
      loading: () => const _LoadingCard(),
      error: (error, _) => _MessageCard(
        title: 'Détails indisponibles',
        icon: Icons.wifi_off_rounded,
        message: humanizeError(error),
        tone: GrintaEmptyTone.alert,
      ),
      data: (details) {
        final homeName = match.isHome ? 'AS Grinta' : match.opponent;
        final awayName = match.isHome ? match.opponent : 'AS Grinta';
        final homeScore =
            match.isHome ? match.grintaScore ?? 0 : match.opponentScore ?? 0;
        final awayScore =
            match.isHome ? match.opponentScore ?? 0 : match.grintaScore ?? 0;
        final scorers = details.playerStats
            .where((player) => player.goals > 0)
            .map(
              (player) => player.goals == 1
                  ? player.name
                  : '${player.name} ×${player.goals}',
            )
            .join(' · ');
        final vote = voteAsync.valueOrNull;
        final hdm = _hdmLabel(details, vote);
        final prono = lastProno?.matchId == match.id ? lastProno : null;
        final predictionPoints = prono == null
            ? 'Aucun prono'
            : AppFormats.counted(
                (prono.points * 100).round(),
                'point',
              );

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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$homeName  $homeScore – $awayScore  $awayName',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (match.kickoffAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          AppFormats.dateTime(match.kickoffAt!),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _InfoLine(
                        icon: Icons.stacked_bar_chart_rounded,
                        label: 'Buteur(s)',
                        value: scorers.isEmpty ? 'Aucun' : scorers,
                      ),
                      const SizedBox(height: 10),
                      _InfoLine(
                        icon: Icons.emoji_events_outlined,
                        label: 'HDM',
                        value: hdm,
                      ),
                      const SizedBox(height: 10),
                      _InfoLine(
                        icon: Icons.sports_score_outlined,
                        label: 'Ton score prono',
                        value: predictionPoints,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Voir la fiche du match',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vote.hasVoted
                                    ? 'Consulte le scrutin depuis la compo.'
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
      },
    );
  }

  String _hdmLabel(MatchDetailsData details, SportMotmVote? vote) {
    if (vote != null && vote.isClosed) {
      final winners =
          vote.winners.map((candidate) => candidate.displayName).join(' · ');
      return winners.isEmpty ? 'Aucun' : winners;
    }
    final recorded = details.startingLineup
        .where((player) => player.isManOfTheMatch)
        .map((player) => player.name)
        .join(' · ');
    if (recorded.isNotEmpty) return recorded;
    if (vote != null && vote.isOpen) return 'Vote ouvert';
    return 'Non désigné';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppTheme.textSecondary),
        const SizedBox(width: 9),
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    this.icon = Icons.sports_soccer_rounded,
    this.message,
    this.tone = GrintaEmptyTone.neutral,
  });

  final String title;
  final IconData icon;
  final String? message;
  final GrintaEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: GrintaEmptyState(
        icon: icon,
        title: title,
        message: message,
        tone: tone,
        compact: true,
      ),
    );
  }
}
