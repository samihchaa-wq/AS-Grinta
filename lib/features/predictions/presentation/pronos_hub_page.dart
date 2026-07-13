import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/colorful_season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _PronosSection { matches, season, general }

class PronosHubPage extends ConsumerStatefulWidget {
  const PronosHubPage({super.key});

  @override
  ConsumerState<PronosHubPage> createState() => _PronosHubPageState();
}

class _PronosHubPageState extends ConsumerState<PronosHubPage> {
  _PronosSection _section = _PronosSection.matches;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pronos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<_PronosSection>(
              segments: const [
                ButtonSegment(
                  value: _PronosSection.matches,
                  icon: Icon(Icons.sports_soccer_outlined),
                  label: Text('Matchs'),
                ),
                ButtonSegment(
                  value: _PronosSection.season,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('Saison'),
                ),
                ButtonSegment(
                  value: _PronosSection.general,
                  icon: Icon(Icons.emoji_events_outlined),
                  label: Text('Général'),
                ),
              ],
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _section = selection.first);
              },
            ),
          ),
          Expanded(
            child: switch (_section) {
              _PronosSection.matches => const _MatchesSection(),
              _PronosSection.season =>
                const ColorfulSeasonPredictionsPage(embedded: true),
              _PronosSection.general => const _GeneralSection(),
            },
          ),
        ],
      ),
    );
  }
}

class _MatchesSection extends ConsumerStatefulWidget {
  const _MatchesSection();

  @override
  ConsumerState<_MatchesSection> createState() => _MatchesSectionState();
}

class _MatchesSectionState extends ConsumerState<_MatchesSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(predictionsControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(homeDashboardProvider);
    final leaderboard = ref.watch(leaderboardProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(homeDashboardProvider);
        ref.invalidate(leaderboardProvider);
        await Future.wait([
          ref.read(predictionsControllerProvider.notifier).load(),
          ref.read(homeDashboardProvider.future),
          ref.read(leaderboardProvider.future),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          Text(
            'Prochain prono',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          dashboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le prochain prono est indisponible.',
            ),
            data: (data) => _UpcomingPredictionCard(
              participantCount: data.predictionParticipantCount,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Classement matchs',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          leaderboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le classement matchs est indisponible.',
            ),
            data: (entries) => _LeaderboardCard(
              entries: entries,
              points: (entry) => entry.matchPoints * 100,
              showMatchStats: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leaderboardProvider);
        await ref.read(leaderboardProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          Text(
            'Classement général',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text('Classement combiné des matchs et de la saison.'),
          const SizedBox(height: 14),
          leaderboard.when(
            loading: () => const _LoadingCard(),
            error: (_, __) => const _MessageCard(
              message: 'Le classement général est indisponible.',
            ),
            data: (entries) => _LeaderboardCard(
              entries: entries,
              points: (entry) => entry.totalPoints.roundToDouble(),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingPredictionCard extends ConsumerWidget {
  const _UpcomingPredictionCard({required this.participantCount});

  final int participantCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(predictionsControllerProvider);
    if (state.isLoading) return const _LoadingCard();
    if (state.items.isEmpty) {
      return const _MessageCard(message: 'Aucun match à pronostiquer.');
    }

    final item = state.items.first;
    final isSaving = state.savingMatchId == item.matchId;
    final controller = ref.read(predictionsControllerProvider.notifier);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppTheme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ton pronostic',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      item.isClosed
                          ? 'Pronostics fermés'
                          : 'Modifiable jusqu’à 5 minutes avant le coup d’envoi',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  item.isClosed
                      ? 'Fermés'
                      : item.isFilled
                          ? 'Enregistré'
                          : 'À saisir',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _OddTile(label: '1', value: AppFormats.odds(item.oddsWin)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OddTile(label: 'N', value: AppFormats.odds(item.oddsDraw)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OddTile(label: '2', value: AppFormats.odds(item.oddsLoss)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.group_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '$participantCount participant${participantCount > 1 ? 's' : ''}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ScoreColumn(
                  label: 'AS Grinta',
                  value: item.scoreGrinta,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: true,
                    delta: 1,
                  ),
                ),
              ),
              Text('–', style: Theme.of(context).textTheme.headlineMedium),
              Expanded(
                child: _ScoreColumn(
                  label: item.opponentName,
                  value: item.scoreOpponent,
                  enabled: item.canEdit && !isSaving,
                  onMinus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: -1,
                  ),
                  onPlus: () => controller.changeScore(
                    matchId: item.matchId,
                    grinta: false,
                    delta: 1,
                  ),
                ),
              ),
            ],
          ),
          if (!item.isClosed) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: item.useX2
                    ? const Color(0xFF6A32C7).withValues(alpha: .22)
                    : Colors.white.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: item.useX2
                      ? const Color(0xFF9B6CFF)
                      : Colors.white.withValues(alpha: .10),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.useX2 ? '×2 activé' : 'Activer le ×2',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text('${item.x2Available} en réserve'),
                      ],
                    ),
                  ),
                  Switch(
                    value: item.useX2,
                    onChanged: (!item.useX2 && item.x2Available <= 0) || isSaving
                        ? null
                        : (_) => controller.toggleX2(item.matchId),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !item.canEdit || isSaving
                    ? null
                    : () async {
                        await controller.save(item.matchId);
                        ref.invalidate(homeDashboardProvider);
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entries,
    required this.points,
    this.showMatchStats = false,
  });

  final List<LeaderboardEntry> entries;
  final double Function(LeaderboardEntry) points;
  final bool showMatchStats;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]
      ..sort((a, b) {
        final byPoints = points(b).compareTo(points(a));
        return byPoints != 0 ? byPoints : a.name.compareTo(b.name);
      });

    if (sorted.isEmpty) {
      return const _MessageCard(message: 'Aucun point pour le moment.');
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < sorted.length; index++) ...[
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  index < 3 ? ['🥇', '🥈', '🥉'][index] : '${index + 1}',
                ),
              ),
              title: Text(
                sorted[index].name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: showMatchStats
                  ? Text(
                      '${sorted[index].matchBons} bons paris · '
                      '${sorted[index].matchExacts} exacts',
                    )
                  : Text(
                      'Matchs ${(sorted[index].matchPoints * 100).round()} · '
                      'Saison ${sorted[index].seasonPoints.round()}',
                    ),
              trailing: Text(
                '${points(sorted[index]).round()} pts',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (index != sorted.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: enabled && value > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            IconButton(
              onPressed: enabled ? onPlus : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class _OddTile extends StatelessWidget {
  const _OddTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outline),
      ),
      child: child,
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message),
      ),
    );
  }
}
