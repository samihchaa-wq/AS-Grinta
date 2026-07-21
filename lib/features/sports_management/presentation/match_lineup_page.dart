import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_board_card.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchLineupPage extends ConsumerWidget {
  const MatchLineupPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Équipe')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(publishedMatchCompositionProvider(matchId))
            ..invalidate(matchAvailabilityBoardProvider(matchId));
          await Future.wait([
            ref.read(publishedMatchCompositionProvider(matchId).future),
            ref.read(matchAvailabilityBoardProvider(matchId).future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            MatchAvailabilitySelector(matchId: matchId, bottomSpacing: 16),
            PublishedLineupPreview(
              matchId: matchId,
              showLists: true,
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}

class PublishedLineupCard extends ConsumerWidget {
  const PublishedLineupCard({
    super.key,
    required this.matchId,
    this.bottomSpacing = 0,
    this.showAvailabilityFlow = true,
  });

  final String matchId;
  final double bottomSpacing;
  final bool showAvailabilityFlow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showAvailabilityFlow)
            MatchAvailabilitySelector(matchId: matchId, bottomSpacing: 12),
          PublishedLineupPreview(matchId: matchId, showLists: true),
        ],
      ),
    );
  }
}

class PublishedLineupPreview extends ConsumerWidget {
  const PublishedLineupPreview({
    super.key,
    required this.matchId,
    this.embeddedOnDark = false,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
    this.showLists = false,
    this.expanded = false,
  });

  final String matchId;
  final bool embeddedOnDark;
  final double topSpacing;
  final double bottomSpacing;
  final bool showLists;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineup = ref.watch(publishedMatchCompositionProvider(matchId));
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: lineup.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (composition) {
          if (composition == null) {
            return MatchAvailabilityBoardCard(matchId: matchId, compact: true);
          }
          final board =
              ref.watch(matchAvailabilityBoardProvider(matchId)).valueOrNull;
          final beforeKickoff =
              board == null || DateTime.now().isBefore(board.kickoffAt);
          final foreground = embeddedOnDark ? Colors.white : null;
          final secondary = embeddedOnDark ? Colors.white70 : null;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.sports_soccer_outlined, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Équipe',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Text(
                    composition.formationCode ?? '4-3-3',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: expanded ? 500 : 360),
                  child: CompositionPitch(
                    entries: composition.entriesFor(MatchCompositionZone.field),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Remplaçants (${composition.benchCount})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              if (composition.benchCount == 0)
                Text(
                  'Aucun remplaçant.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final entry
                        in composition.entriesFor(MatchCompositionZone.bench))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(entry.displayName),
                      ),
                  ],
                ),
              if (showLists && beforeKickoff) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8),
                  leading: Icon(Icons.list_alt_outlined, color: foreground),
                  title: Text(
                    'Voir les listes',
                    style: TextStyle(
                        color: foreground, fontWeight: FontWeight.w800),
                  ),
                  children: [
                    MatchAvailabilityBoardCard(matchId: matchId, compact: true),
                  ],
                ),
              ],
            ],
          );
          if (embeddedOnDark) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: const Color(0xFF9B6CFF).withValues(alpha: .55)),
              ),
              child: content,
            );
          }
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: const EdgeInsets.all(16), child: content),
          );
        },
      ),
    );
  }
}
