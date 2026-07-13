import 'package:as_grinta/core/design_system/components/grinta_card.dart';
import 'package:as_grinta/core/design_system/components/grinta_loading.dart';
import 'package:as_grinta/core/design_system/components/grinta_status_message.dart';
import 'package:as_grinta/core/design_system/components/grinta_surface.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_typography.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _LeaderboardMode { cumulative, season, match }

class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key});

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  _LeaderboardMode _mode = _LeaderboardMode.cumulative;

  String _formatNumber(double value) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  double _points(LeaderboardEntry item) {
    return switch (_mode) {
      _LeaderboardMode.cumulative => item.totalPoints,
      _LeaderboardMode.season => item.seasonPoints,
      _LeaderboardMode.match => item.matchPoints,
    };
  }

  String get _modeTitle {
    return switch (_mode) {
      _LeaderboardMode.cumulative => 'Classement général',
      _LeaderboardMode.season => 'Pronostics de saison',
      _LeaderboardMode.match => 'Pronostics de match',
    };
  }

  String get _modeDescription {
    return switch (_mode) {
      _LeaderboardMode.cumulative =>
        'Score pondéré : 70 % matchs et 30 % saison.',
      _LeaderboardMode.season =>
        'Points obtenus sur les pronostics de fin de saison.',
      _LeaderboardMode.match =>
        'Points obtenus sur les scores et résultats des matchs.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(leaderboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Classement')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leaderboardProvider);
          await ref.read(leaderboardProvider.future);
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: GrintaSpacing.contentMaxWidth,
            ),
            child: leaderboardAsync.when(
              loading: () => const _ScrollableState(
                child: GrintaLoadingIndicator(
                  label: 'Chargement du classement',
                ),
              ),
              error: (error, _) => _ScrollableState(
                child: GrintaStatusMessage(
                  title: 'Impossible de charger le classement',
                  message: humanizeError(error),
                  tone: GrintaStatusTone.danger,
                ),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return const _ScrollableState(
                    child: GrintaStatusMessage(
                      title: 'Classement indisponible',
                      message: 'Aucun point calculable pour le moment.',
                      tone: GrintaStatusTone.info,
                    ),
                  );
                }

                final sorted = [...entries]
                  ..sort((a, b) => _points(b).compareTo(_points(a)));
                final maxPoints = sorted
                    .map(_points)
                    .fold<double>(0, (maximum, points) {
                  return points > maximum ? points : maximum;
                });
                final podium = sorted.take(3).toList();
                final remaining = sorted.skip(3).toList();

                return ListView(
                  padding: GrintaSpacing.screenInsets,
                  children: [
                    _ModeSelector(
                      mode: _mode,
                      onChanged: (mode) => setState(() => _mode = mode),
                    ),
                    const SizedBox(height: GrintaSpacing.sectionGap),
                    _LeaderboardIntro(
                      title: _modeTitle,
                      description: _modeDescription,
                      participantCount: sorted.length,
                    ),
                    const SizedBox(height: GrintaSpacing.sectionGap),
                    _Podium(
                      entries: podium,
                      points: _points,
                      formatNumber: _formatNumber,
                    ),
                    if (remaining.isNotEmpty) ...[
                      const SizedBox(height: GrintaSpacing.majorSectionGap),
                      Text(
                        'Classement complet',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: GrintaSpacing.contentGap),
                      ...remaining.asMap().entries.map((entry) {
                        final rank = entry.key + 4;
                        final item = entry.value;
                        final points = _points(item);
                        final fraction =
                            maxPoints <= 0 ? 0.0 : points / maxPoints;

                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: GrintaSpacing.contentGap,
                          ),
                          child: _RankingRow(
                            rank: rank,
                            name: item.name,
                            points: _formatNumber(points),
                            progress: fraction.clamp(0.0, 1.0).toDouble(),
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: GrintaSpacing.screenInsets,
      children: [
        const SizedBox(height: GrintaSpacing.space20),
        child,
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final _LeaderboardMode mode;
  final ValueChanged<_LeaderboardMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_LeaderboardMode>(
      segments: const [
        ButtonSegment(
          value: _LeaderboardMode.cumulative,
          label: Text('Général'),
        ),
        ButtonSegment(
          value: _LeaderboardMode.season,
          label: Text('Saison'),
        ),
        ButtonSegment(value: _LeaderboardMode.match, label: Text('Match')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _LeaderboardIntro extends StatelessWidget {
  const _LeaderboardIntro({
    required this.title,
    required this.description,
    required this.participantCount,
  });

  final String title;
  final String description;
  final int participantCount;

  @override
  Widget build(BuildContext context) {
    return GrintaCard(
      level: GrintaSurfaceLevel.emphasis,
      title: title,
      subtitle: description,
      leading: const Icon(Icons.emoji_events_outlined),
      child: Row(
        children: [
          const Icon(
            Icons.groups_outlined,
            color: GrintaColors.contentTertiary,
          ),
          const SizedBox(width: GrintaSpacing.inlineGap),
          Text(
            '$participantCount participant${participantCount > 1 ? 's' : ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({
    required this.entries,
    required this.points,
    required this.formatNumber,
  });

  final List<LeaderboardEntry> entries;
  final double Function(LeaderboardEntry) points;
  final String Function(double) formatNumber;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final displayOrder = <int>[1, 0, 2]
        .where((index) => index < entries.length)
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: displayOrder.map((index) {
        final rank = index + 1;
        final entry = entries[index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: index == displayOrder.first
                  ? 0
                  : GrintaSpacing.space2,
              right: index == displayOrder.last
                  ? 0
                  : GrintaSpacing.space2,
            ),
            child: _PodiumCard(
              rank: rank,
              name: entry.name,
              points: formatNumber(points(entry)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.rank,
    required this.name,
    required this.points,
  });

  final int rank;
  final String name;
  final String points;

  @override
  Widget build(BuildContext context) {
    final isWinner = rank == 1;
    final accent = switch (rank) {
      1 => GrintaColors.statusWarning,
      2 => GrintaColors.contentSecondary,
      _ => GrintaColors.accentPrimary,
    };

    return GrintaSurface(
      level: isWinner
          ? GrintaSurfaceLevel.emphasis
          : GrintaSurfaceLevel.raised,
      padding: EdgeInsets.fromLTRB(
        GrintaSpacing.space3,
        isWinner ? GrintaSpacing.space6 : GrintaSpacing.space4,
        GrintaSpacing.space3,
        GrintaSpacing.space4,
      ),
      borderRadius: GrintaRadii.prominentCardRadius,
      child: Column(
        children: [
          Container(
            width: isWinner ? 52 : 44,
            height: isWinner ? 52 : 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              shape: BoxShape.circle,
              border: Border.all(color: accent),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: GrintaSpacing.space3),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: GrintaSpacing.space3),
          Text(points, style: GrintaTypography.statistic),
          Text('points', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.name,
    required this.points,
    required this.progress,
  });

  final int rank;
  final String name;
  final String points;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return GrintaCard(
      padding: GrintaSpacing.compactCardInsets,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GrintaColors.surfaceElevated,
              borderRadius: GrintaRadii.controlRadius,
            ),
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: GrintaSpacing.inlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: GrintaSpacing.space2),
                ClipRRect(
                  borderRadius: GrintaRadii.badgeRadius,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: GrintaColors.surfaceElevated,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GrintaSpacing.inlineGap),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(points, style: GrintaTypography.statistic),
              Text('pts', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
