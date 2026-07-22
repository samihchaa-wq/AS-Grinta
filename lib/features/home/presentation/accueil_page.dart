import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/home/presentation/home_last_match_card.dart';
import 'package:as_grinta/features/sports_management/data/sport_motm_vote_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccueilPage extends ConsumerWidget {
  const AccueilPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const Text('Accueil'),
        actions: grintaHomeActions(context),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(homeDashboardProvider)
            ..invalidate(myLastPronoProvider)
            ..invalidate(myArmoireProvider)
            ..invalidate(sportMotmVoteProvider);
          await Future.wait([
            ref.read(homeDashboardProvider.future),
            ref.read(myLastPronoProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: const [
            _NextMatchBlock(),
            SizedBox(height: 18),
            HomeLastMatchCard(),
            SizedBox(height: 18),
            _RecentBadgesBlock(),
          ],
        ),
      ),
    );
  }
}

class _BlockHeader extends StatelessWidget {
  const _BlockHeader(this.icon, this.title, {this.onSeeAll, this.seeAllLabel});

  final IconData icon;
  final String title;
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(seeAllLabel ?? 'Voir tout'),
            ),
        ],
      ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

class _NextMatchBlock extends ConsumerWidget {
  const _NextMatchBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeDashboardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockHeader(Icons.event_rounded, 'Prochain match'),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) => const _EmptyCard('Impossible de charger le match.'),
          data: (data) {
            final match = data.nextMatch;
            if (match == null) {
              return const _EmptyCard('Aucun match à venir pour le moment.');
            }
            return _NextMatchCard(
              match: match,
              predicted: data.nextMatchPredicted,
              prediction: data.nextMatchPrediction,
            );
          },
        ),
      ],
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({
    required this.match,
    required this.predicted,
    required this.prediction,
  });

  final HomeMatch match;
  final bool predicted;
  final HomePrediction? prediction;

  @override
  Widget build(BuildContext context) {
    final homeName = match.isHome ? 'AS Grinta' : match.opponent;
    final awayName = match.isHome ? match.opponent : 'AS Grinta';
    final closeAt = match.kickoffAt?.subtract(const Duration(minutes: 5));
    final open = !match.predictionsClosed &&
        closeAt != null &&
        DateTime.now().isBefore(closeAt);
    final predictionScore = prediction == null
        ? null
        : match.isHome
            ? '${prediction!.grintaScore} – ${prediction!.opponentScore}'
            : '${prediction!.opponentScore} – ${prediction!.grintaScore}';

    return Card(
      color: const Color(0xFF25164F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF9B6CFF), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$homeName  vs  $awayName',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFFD7C8FF)),
                ],
              ),
              if (match.kickoffAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  AppFormats.dateTime(match.kickoffAt!),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD7C8FF),
                      ),
                ),
              ],
              MatchAvailabilitySelector(
                matchId: match.id,
                embeddedOnDark: true,
                topSpacing: 14,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF160B36),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3F2A73)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.sports_score_outlined, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Ton prono',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          predicted ? Icons.check_circle : Icons.edit_note,
                          size: 18,
                          color: predicted
                              ? const Color(0xFF52D08A)
                              : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            predicted && predictionScore != null
                                ? '$predictionScore'
                                    '${prediction!.useX2 ? ' · ×2' : ''}'
                                : open
                                    ? 'Pas encore rempli'
                                    : 'Pronostics fermés',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: predicted
                                  ? const Color(0xFF52D08A)
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (open)
                          FilledButton(
                            onPressed: () =>
                                context.push('/matches/${match.id}/prediction'),
                            child: Text(predicted ? 'Modifier' : 'Remplir'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentBadgesBlock extends ConsumerWidget {
  const _RecentBadgesBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myArmoireProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockHeader(
          Icons.emoji_events_outlined,
          'Badges récents',
          seeAllLabel: 'Armoire',
          onSeeAll: () => context.push('/armoire'),
        ),
        async.when(
          loading: () => const _MiniLoader(),
          error: (_, __) =>
              const _EmptyCard('Impossible de charger tes badges.'),
          data: (armoire) {
            final recent = armoire.recent.take(4).toList();
            if (recent.isEmpty) {
              return const _EmptyCard(
                'Aucun badge pour l’instant. À toi de jouer !',
              );
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final badge in recent) _BadgeChip(badge: badge)
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});

  final ArmoireBadge badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        children: [
          BadgeEmblem(
            emoji: badge.def.emoji,
            imageUrl: badge.def.imageUrl,
            color: badge.def.color,
            baremeLabel: baremeLabelFor(badge.def.metric, badge.def.threshold),
            showStar: badge.def.hasStar,
            starCount: badge.stars,
            starsMultiplyBareme: isCareerBadgeCategory(badge.def.category),
            size: 66,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: Text(
              badge.def.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
