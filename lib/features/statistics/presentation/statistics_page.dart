import 'package:as_grinta/features/statistics/data/statistics_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticsAsync = ref.watch(careerStatisticsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(careerStatisticsProvider);
          await ref.read(careerStatisticsProvider.future);
        },
        child: statisticsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(careerStatisticsProvider),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (all) {
            if (all.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Aucune statistique disponible.'),
                    ),
                  ),
                ],
              );
            }

            // Top 5 catégories
            final byGoals = [...all]
              ..sort((a, b) => b.goals.compareTo(a.goals));
            final top5Goals =
                byGoals.where((p) => p.goals > 0).take(5).toList();

            final byAssists = [...all]
              ..sort((a, b) => b.assists.compareTo(a.assists));
            final top5Assists =
                byAssists.where((p) => p.assists > 0).take(5).toList();

            final byMotm = [...all]
              ..sort((a, b) => b.motm.compareTo(a.motm));
            final top5Motm =
                byMotm.where((p) => p.motm > 0).take(5).toList();

            // Gardiens pour clean sheets
            final goalkeepers = all
                .where((p) => p.isGoalkeeper)
                .toList()
              ..sort((a, b) => b.cleanSheets.compareTo(a.cleanSheets));

            // Tous les joueurs classés alphabétiquement
            final alphabetical = [...all]
              ..sort((a, b) => a.sortName.compareTo(b.sortName));

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // ── Top 5 Buteurs ──────────────────────────────────────
                _SectionHeader(
                  icon: Icons.sports_soccer_rounded,
                  label: 'Top 5 Buteurs',
                ),
                const SizedBox(height: 8),
                if (top5Goals.isEmpty)
                  _EmptyChip('Aucun but enregistré')
                else
                  ...top5Goals.indexed.map(
                    (e) => _TopRankRow(
                      rank: e.$1 + 1,
                      name: e.$2.displayName,
                      value: e.$2.goals,
                      unit: 'but${e.$2.goals > 1 ? 's' : ''}',
                      isGoalkeeper: e.$2.isGoalkeeper,
                    ),
                  ),
                const SizedBox(height: 24),

                // ── Top 5 Passeurs décisifs ────────────────────────────
                _SectionHeader(
                  icon: Icons.swap_calls_rounded,
                  label: 'Top 5 Passeurs décisifs',
                ),
                const SizedBox(height: 8),
                if (top5Assists.isEmpty)
                  _EmptyChip('Aucune passe décisive enregistrée')
                else
                  ...top5Assists.indexed.map(
                    (e) => _TopRankRow(
                      rank: e.$1 + 1,
                      name: e.$2.displayName,
                      value: e.$2.assists,
                      unit: 'passe${e.$2.assists > 1 ? 's' : ''}',
                      isGoalkeeper: e.$2.isGoalkeeper,
                    ),
                  ),
                const SizedBox(height: 24),

                // ── Top 5 Hommes du Match ──────────────────────────────
                _SectionHeader(
                  icon: Icons.emoji_events_rounded,
                  label: 'Top 5 Hommes du Match',
                ),
                const SizedBox(height: 8),
                if (top5Motm.isEmpty)
                  _EmptyChip('Aucun Homme du Match enregistré')
                else
                  ...top5Motm.indexed.map(
                    (e) => _TopRankRow(
                      rank: e.$1 + 1,
                      name: e.$2.displayName,
                      value: e.$2.motm,
                      unit: 'HDM',
                      isGoalkeeper: e.$2.isGoalkeeper,
                    ),
                  ),
                const SizedBox(height: 24),

                // ── Clean sheets gardien(s) ────────────────────────────
                _SectionHeader(
                  icon: Icons.shield_outlined,
                  label: 'Clean sheets gardien${goalkeepers.length > 1 ? 's' : ''}',
                ),
                const SizedBox(height: 8),
                if (goalkeepers.isEmpty)
                  _EmptyChip('Aucun gardien enregistré')
                else
                  ...goalkeepers.map(
                    (gk) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              const Color(0xFFFF6F00).withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.sports_handball,
                            color: Color(0xFFFF6F00),
                          ),
                        ),
                        title: Text(
                          gk.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${gk.matches} match${gk.matches > 1 ? 's' : ''} '
                          '• ${gk.minutesPlayed} min',
                        ),
                        trailing: _BigStat(
                          value: gk.cleanSheets,
                          label: 'CS',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // ── Statistiques individuelles (A → Z) ─────────────────
                _SectionHeader(
                  icon: Icons.bar_chart_rounded,
                  label: 'Statistiques individuelles',
                ),
                const SizedBox(height: 4),
                Text(
                  'Classées par surnom, A → Z',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ...alphabetical.map(
                  (player) => _PlayerStatsCard(player: player),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Widgets locaux ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _EmptyChip extends StatelessWidget {
  const _EmptyChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _TopRankRow extends StatelessWidget {
  const _TopRankRow({
    required this.rank,
    required this.name,
    required this.value,
    required this.unit,
    required this.isGoalkeeper,
  });

  final int rank;
  final String name;
  final int value;
  final String unit;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTop3 = rank <= 3;
    final medalColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : const Color(0xFFCD7F32);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isTop3
              ? medalColor.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          child: Text(
            '$rank',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isTop3 ? medalColor : cs.onSurfaceVariant,
            ),
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
            ),
            const SizedBox(width: 6),
            Text(unit, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PlayerStatsCard extends StatelessWidget {
  const _PlayerStatsCard({required this.player});
  final PlayerStatistics player;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: player.isGoalkeeper
              ? const Color(0xFFFF6F00).withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            player.isGoalkeeper
                ? Icons.sports_handball
                : Icons.sports_soccer_rounded,
            size: 20,
            color: player.isGoalkeeper
                ? const Color(0xFFFF6F00)
                : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          player.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${player.matches} match${player.matches > 1 ? 's' : ''} '
          '• ${player.minutesPlayed} min',
        ),
        trailing: Wrap(
          spacing: 10,
          children: [
            _StatBadge(label: 'B', value: player.goals),
            _StatBadge(label: 'P', value: player.assists),
            _StatBadge(label: 'M', value: player.motm),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Minutes',
                value: '${player.minutesPlayed}',
              ),
              _DetailRow(
                icon: Icons.sports_soccer_outlined,
                label: 'Buts',
                value: '${player.goals}',
              ),
              _DetailRow(
                icon: Icons.swap_calls_rounded,
                label: 'Passes D.',
                value: '${player.assists}',
              ),
              _DetailRow(
                icon: Icons.emoji_events_outlined,
                label: 'HDM',
                value: '${player.motm}',
              ),
              _DetailRow(
                icon: Icons.square_rounded,
                label: 'Jaunes',
                value: '0',
                iconColor: const Color(0xFFFDD835),
              ),
              _DetailRow(
                icon: Icons.square_rounded,
                label: 'Rouges',
                value: '0',
                iconColor: const Color(0xFFE53935),
              ),
              if (player.isGoalkeeper)
                _DetailRow(
                  icon: Icons.shield_outlined,
                  label: 'Clean sheets',
                  value: '${player.cleanSheets}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleMedium),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
