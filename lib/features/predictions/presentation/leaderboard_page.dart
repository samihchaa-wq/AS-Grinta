import 'package:as_grinta/core/design_system/components/grinta_loading.dart';
import 'package:as_grinta/core/design_system/components/grinta_status_message.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
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

  String get _description {
    return switch (_mode) {
      _LeaderboardMode.cumulative =>
        '70 % pronostics de match, 30 % pronostics de saison.',
      _LeaderboardMode.season => 'Points des pronostics de fin de saison.',
      _LeaderboardMode.match => 'Points des pronostics de match.',
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
                      message: 'Aucun point calculable pour le moment.',
                      tone: GrintaStatusTone.info,
                    ),
                  );
                }

                final sorted = [...entries]
                  ..sort((a, b) => _points(b).compareTo(_points(a)));

                return ListView(
                  padding: GrintaSpacing.screenInsets,
                  children: [
                    _ModeSelector(
                      mode: _mode,
                      onChanged: (mode) => setState(() => _mode = mode),
                    ),
                    const SizedBox(height: GrintaSpacing.space6),
                    Text(
                      _description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: GrintaSpacing.space6),
                    const _TableHeader(),
                    const SizedBox(height: GrintaSpacing.space2),
                    ...sorted.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return _RankingRow(
                        rank: index + 1,
                        name: item.name,
                        points: _formatNumber(_points(item)),
                        isTopThree: index < 3,
                        showDivider: index < sorted.length - 1,
                      );
                    }),
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

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: GrintaColors.contentTertiary,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GrintaSpacing.space2,
      ),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text('RANG', style: style)),
          const SizedBox(width: GrintaSpacing.inlineGap),
          Expanded(child: Text('JOUEUR', style: style)),
          Text('POINTS', style: style),
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
    required this.isTopThree,
    required this.showDivider,
  });

  final int rank;
  final String name;
  final String points;
  final bool isTopThree;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final nameStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: GrintaColors.contentPrimary,
          fontWeight: isTopThree ? FontWeight.w700 : FontWeight.w500,
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GrintaSpacing.space2,
            vertical: GrintaSpacing.space4,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '$rank',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isTopThree
                            ? GrintaColors.contentPrimary
                            : GrintaColors.contentTertiary,
                        fontWeight:
                            isTopThree ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ),
              const SizedBox(width: GrintaSpacing.inlineGap),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
              ),
              const SizedBox(width: GrintaSpacing.inlineGap),
              Text(
                points,
                style: GrintaTypography.statistic.copyWith(
                  fontSize: 18,
                  color: GrintaColors.contentPrimary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            indent: 54,
          ),
      ],
    );
  }
}
