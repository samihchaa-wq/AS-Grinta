import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
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
            message: 'Impossible de charger le dernier match.',
          ),
          data: (data) {
            final match = data.lastMatch;
            if (match == null) {
              return const _MessageCard(message: 'Aucun match terminé.');
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
      error: (error, _) => _MessageCard(message: humanizeError(error)),
      data: (details) {
        final homeName = match.isHome ? 'AS Grinta' : match.opponent;
        final awayName = match.isHome ? match.opponent : 'AS Grinta';
        final homeScore = match.isHome
            ? match.grintaScore ?? 0
            : match.opponentScore ?? 0;
        final awayScore = match.isHome
            ? match.opponentScore ?? 0
            : match.grintaScore ?? 0;
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0xFF20242C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF626A78), width: 1.3),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
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
            ),
            if (vote != null && vote.isOpen) ...[
              const SizedBox(height: 10),
              HomeMotmInlineVote(matchId: match.id, vote: vote),
            ],
          ],
        );
      },
    );
  }

  String _hdmLabel(MatchDetailsData details, SportMotmVote? vote) {
    if (vote != null && vote.isClosed) {
      final winners = vote.winners
          .map((candidate) => candidate.displayName)
          .join(' · ');
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

class HomeMotmInlineVote extends ConsumerStatefulWidget {
  const HomeMotmInlineVote({
    super.key,
    required this.matchId,
    required this.vote,
  });

  final String matchId;
  final SportMotmVote vote;

  @override
  ConsumerState<HomeMotmInlineVote> createState() =>
      _HomeMotmInlineVoteState();
}

class _HomeMotmInlineVoteState extends ConsumerState<HomeMotmInlineVote> {
  String? _selected;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final vote = widget.vote;
    if (vote.hasVoted) {
      return const _MessageCard(
        icon: Icons.lock_outline,
        title: 'Vote HDM enregistré',
        message: 'Ton choix est définitif. Les résultats seront révélés ensuite.',
      );
    }
    if (!vote.isEligibleVoter || !vote.canVote) {
      return const _MessageCard(
        icon: Icons.visibility_outlined,
        title: 'Vote HDM ouvert',
        message: 'Tu peux consulter le scrutin depuis la fiche du match.',
      );
    }

    final candidates = vote.candidates
        .where((candidate) => candidate.canChoose)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vote Homme du match',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text('Choisis un joueur ayant participé au match.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in candidates)
                  ChoiceChip(
                    avatar: const CircleAvatar(
                      child: Icon(Icons.person_outline, size: 17),
                    ),
                    label: Text(candidate.displayName),
                    selected: _selected == candidate.participantId,
                    onSelected: _saving
                        ? null
                        : (_) => setState(
                              () => _selected = candidate.participantId,
                            ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _selected == null || _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.how_to_vote_outlined),
              label: const Text('Valider définitivement mon vote'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final candidateId = _selected;
    if (candidateId == null || _saving) return;
    final candidate = widget.vote.candidates
        .where((item) => item.participantId == candidateId)
        .firstOrNull;
    if (candidate == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer ton vote ?'),
        content: Text(
          'Tu votes pour ${candidate.displayName}. Ce choix ne pourra plus être modifié.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sportMotmVoteRepositoryProvider).castVote(
            matchId: widget.matchId,
            candidateParticipantId: candidateId,
          );
      ref.invalidate(sportMotmVoteProvider(widget.matchId));
      if (mounted) {
        setState(() => _selected = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vote HDM enregistré.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    required this.message,
    this.icon,
    this.title,
  });

  final String message;
  final IconData? icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
