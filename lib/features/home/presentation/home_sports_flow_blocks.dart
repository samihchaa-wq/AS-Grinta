import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/match_lineup_page.dart';
import 'package:as_grinta/features/sports_management/presentation/sport_motm_vote_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeSportsFlowBlocks extends ConsumerWidget {
  const HomeSportsFlowBlocks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return const SizedBox.shrink();
    }

    final dashboardAsync = ref.watch(homeDashboardProvider);
    return dashboardAsync.maybeWhen(
      data: (dashboard) {
        final children = <Widget>[];
        final now = DateTime.now();
        final nextMatch = dashboard.nextMatch;

        if (nextMatch != null &&
            nextMatch.kickoffAt != null &&
            now.isBefore(nextMatch.kickoffAt!)) {
          final lineupAsync = ref.watch(
            publishedMatchCompositionProvider(nextMatch.id),
          );
          final composition = lineupAsync.maybeWhen(
            data: (value) => value,
            orElse: () => null,
          );
          if (composition != null) {
            children
              ..add(const _HomeSportHeader('📋', 'Composition d’équipe'))
              ..add(
                PublishedLineupCard(
                  matchId: nextMatch.id,
                  showAvailabilityFlow: false,
                  bottomSpacing: 18,
                ),
              );
          }
        }

        final lastMatch = dashboard.lastMatch;
        if (lastMatch != null) {
          final voteAsync = ref.watch(sportMotmVoteProvider(lastMatch.id));
          final vote = voteAsync.maybeWhen(
            data: (value) => value,
            orElse: () => null,
          );
          if (vote != null && vote.isOpen && vote.isEligibleVoter) {
            children
              ..add(
                const _HomeSportHeader('🗳️', 'Voter pour l’homme du match'),
              )
              ..add(
                MatchMotmVoteCard(matchId: lastMatch.id, bottomSpacing: 18),
              );
          }
        }

        return children.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _HomeSportHeader extends StatelessWidget {
  const _HomeSportHeader(this.emoji, this.title);

  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
