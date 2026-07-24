import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/domain/sport_motm_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SportMotmVotePage extends ConsumerStatefulWidget {
  const SportMotmVotePage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<SportMotmVotePage> createState() => _SportMotmVotePageState();
}

class _SportMotmVotePageState extends ConsumerState<SportMotmVotePage> {
  String? _selectedCandidateId;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _cast(SportMotmVote vote) async {
    final candidateId = _selectedCandidateId;
    if (candidateId == null) return;
    await _castCandidateId(vote, candidateId);
  }

  Future<void> _castCandidateId(SportMotmVote vote, String candidateId) async {
    if (_isSubmitting) return;
    final candidate = vote.candidates
        .where((item) => item.participantId == candidateId)
        .firstOrNull;
    if (candidate == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer ton vote ?'),
        content: Text(
          'Tu votes pour ${candidate.displayName}. Ce choix est secret et '
          'définitif : il ne pourra plus être modifié.',
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
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(sportMotmVoteRepositoryProvider).castVote(
            matchId: widget.matchId,
            candidateParticipantId: candidateId,
          );
      ref.invalidate(sportMotmVoteProvider(widget.matchId));
      if (mounted) {
        setState(() => _selectedCandidateId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vote enregistré définitivement.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voteAsync = ref.watch(sportMotmVoteProvider(widget.matchId));

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Homme du match')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sportMotmVoteProvider(widget.matchId));
          await ref.read(sportMotmVoteProvider(widget.matchId).future);
        },
        child: voteAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(humanizeError(error)),
                ),
              ),
            ],
          ),
          data: (vote) {
            if (vote == null) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Le résultat et les présences doivent être validés '
                        'avant l’ouverture du vote.',
                      ),
                    ),
                  ),
                ],
              );
            }
            return _buildVote(context, vote);
          },
        ),
      ),
    );
  }

  Widget _buildVote(BuildContext context, SportMotmVote vote) {
    final choosable =
        vote.candidates.where((item) => item.canChoose).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _VoteHeader(vote: vote),
        const SizedBox(height: 16),
        if (vote.isOpen) ...[
          if (vote.hasVoted)
            const _MessageCard(
              icon: Icons.lock_outline,
              title: 'Vote enregistré',
              message:
                  'Ton choix est secret et irréversible. Les résultats seront '
                  'révélés uniquement après la clôture.',
            )
          else if (!vote.isEligibleVoter)
            const _MessageCard(
              icon: Icons.visibility_outlined,
              title: 'Consultation uniquement',
              message:
                  'Seuls les joueurs permanents réellement présents peuvent '
                  'voter. Les invités peuvent être élus, mais ne votent pas.',
            )
          else if (choosable.isEmpty)
            const _MessageCard(
              icon: Icons.block_outlined,
              title: 'Aucun vote possible',
              message: 'Aucun autre participant éligible ne peut être choisi.',
            )
          else ...[
            Text(
              'Choisis l’Homme du match',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Coche un joueur parmi les présents. '
              'Un seul choix, définitif et secret.',
            ),
            const SizedBox(height: 12),
            for (final candidate in choosable)
              Card(
                child: ListTile(
                  enabled: !_isSubmitting,
                  onTap: _isSubmitting
                      ? null
                      : () => setState(
                            () =>
                                _selectedCandidateId = candidate.participantId,
                          ),
                  leading: Icon(
                    _selectedCandidateId == candidate.participantId
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: _selectedCandidateId == candidate.participantId
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(candidate.displayName),
                  subtitle: candidate.isGuest
                      ? const Text('Invité · candidat uniquement')
                      : null,
                  trailing: _CandidateExploit(candidate: candidate),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _selectedCandidateId == null || _isSubmitting
                  ? null
                  : () => _cast(vote),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.how_to_vote_outlined),
              label: const Text('Valider définitivement mon vote'),
            ),
          ],
        ] else if (vote.isClosed) ...[
          _Results(vote: vote),
        ] else if (vote.state == SportMotmVoteState.cancelled) ...[
          const _MessageCard(
            icon: Icons.cancel_outlined,
            title: 'Scrutin annulé',
            message:
                'Aucun Homme du match collectif n’est attribué pour le moment.',
          ),
        ] else ...[
          const _MessageCard(
            icon: Icons.schedule_outlined,
            title: 'Scrutin bientôt ouvert',
            message: 'Le vote s’ouvre 1 h 45 après le coup d’envoi '
                '(ou dès la validation du résultat).',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class MatchMotmVoteCard extends ConsumerWidget {
  const MatchMotmVoteCard({
    super.key,
    required this.matchId,
    this.bottomSpacing = 0,
  });

  final String matchId;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVote = ref.watch(sportMotmVoteProvider(matchId));
    return asyncVote.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (vote) {
        if (vote == null) return const SizedBox.shrink();
        // Ceux qui n'étaient pas au match ne voient rien pendant le scrutin :
        // uniquement le résultat une fois clos.
        if (vote.isOpen && !vote.isEligibleVoter) {
          return const SizedBox.shrink();
        }
        final (icon, title, subtitle) = switch (vote.state) {
          SportMotmVoteState.open when vote.hasVoted => (
              Icons.lock_outline,
              'Vote HDM enregistré',
              'Résultats révélés après la clôture.',
            ),
          SportMotmVoteState.open => (
              Icons.how_to_vote_outlined,
              'Vote Homme du match ouvert',
              vote.canVote
                  ? 'Ton vote est attendu avant la clôture.'
                  : 'Consulte le scrutin en cours.',
            ),
          SportMotmVoteState.closed => (
              Icons.emoji_events_outlined,
              vote.winners.length > 1 ? 'Co-Hommes du match' : 'Homme du match',
              vote.winners.isEmpty
                  ? 'Aucun vote exprimé.'
                  : vote.winners
                      .map((winner) => winner.displayName)
                      .join(' · '),
            ),
          SportMotmVoteState.cancelled => (
              Icons.cancel_outlined,
              'Vote HDM annulé',
              'Aucun résultat collectif.',
            ),
          _ => (
              Icons.schedule_outlined,
              'Vote HDM en préparation',
              'Le scrutin sera disponible prochainement.',
            ),
        };
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/matches/$matchId/vote'),
            ),
          ),
        );
      },
    );
  }
}

class _VoteHeader extends StatelessWidget {
  const _VoteHeader({required this.vote});

  final SportMotmVote vote;

  @override
  Widget build(BuildContext context) {
    final status = switch (vote.state) {
      SportMotmVoteState.open => 'Vote ouvert',
      SportMotmVoteState.closed => 'Résultats définitifs',
      SportMotmVoteState.cancelled => 'Scrutin annulé',
      _ => 'En préparation',
    };
    final date = switch (vote.state) {
      SportMotmVoteState.open when vote.closesAt != null =>
        'Clôture ${AppFormats.dateTime(vote.closesAt!.toLocal())}',
      SportMotmVoteState.closed when vote.closedAt != null =>
        'Clôturé ${AppFormats.dateTime(vote.closedAt!.toLocal())}',
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text('👑', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 8),
            Text(
              vote.matchTitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(status),
            if (date != null) ...[
              const SizedBox(height: 4),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.vote});

  final SportMotmVote vote;

  @override
  Widget build(BuildContext context) {
    final winners = vote.winners;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                Text(
                  winners.isEmpty
                      ? 'Aucun vote exprimé'
                      : winners.length == 1
                          ? winners.first.displayName
                          : winners
                              .map((winner) => winner.displayName)
                              .join(' · '),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text('${vote.totalVotes ?? 0} vote(s) exprimé(s)'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Résultats', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final candidate
            in vote.candidates.where((c) => (c.votesCount ?? 0) > 0))
          Card(
            child: ListTile(
              leading: Text(
                candidate.isWinner
                    ? '👑'
                    : candidate.isGoalkeeper
                        ? '🧤'
                        : '⚽',
                style: const TextStyle(fontSize: 22),
              ),
              title: Text(candidate.displayName),
              trailing: Text(
                '${candidate.votesCount ?? 0}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
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

/// Exploit du joueur affiché dans la liste de vote : buts pour les joueurs de
/// champ, clean sheet ou non pour le gardien.
class _CandidateExploit extends StatelessWidget {
  const _CandidateExploit({required this.candidate});

  final SportMotmCandidate candidate;

  @override
  Widget build(BuildContext context) {
    if (candidate.isGoalkeeper) {
      final cleanSheet = candidate.cleanSheet;
      if (cleanSheet == null) return const SizedBox.shrink();
      return Text(
        cleanSheet ? 'Clean sheet' : 'A encaissé',
        style: TextStyle(
          color: cleanSheet ? const Color(0xFF52D08A) : Colors.white54,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      );
    }
    final goals = candidate.goals;
    return Text(
      goals <= 1 ? '$goals but' : '$goals buts',
      style: TextStyle(
        color: goals > 0 ? const Color(0xFFCAB5FF) : Colors.white54,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    );
  }
}
