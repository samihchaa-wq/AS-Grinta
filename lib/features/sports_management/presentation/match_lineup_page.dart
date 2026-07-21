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
import 'package:go_router/go_router.dart';

class MatchLineupPage extends ConsumerWidget {
  const MatchLineupPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(sportsManagementEnabledProvider);
    if (!enabled) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final lineup = ref.watch(publishedMatchCompositionProvider(matchId));
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Composition')),
      body: lineup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('La composition est momentanément indisponible.'),
        ),
        data: (composition) {
          if (composition == null) {
            return const Center(child: Text('Composition non publiée.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(publishedMatchCompositionProvider(matchId));
              await ref.read(publishedMatchCompositionProvider(matchId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _PublicationHeader(composition: composition),
                const SizedBox(height: 16),
                Center(
                  child: CompositionPitch(
                    entries: composition.entriesFor(MatchCompositionZone.field),
                  ),
                ),
                const SizedBox(height: 16),
                _PublishedGroup(
                  title: 'Remplaçants',
                  icon: Icons.event_seat_outlined,
                  entries: composition.entriesFor(MatchCompositionZone.bench),
                ),
                const SizedBox(height: 12),
                _PublishedGroup(
                  title: 'Non convoqués',
                  icon: Icons.person_off_outlined,
                  entries: composition.entriesFor(
                    MatchCompositionZone.notSelected,
                  ),
                ),
              ],
            ),
          );
        },
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

    final boardAsync = ref.watch(matchAvailabilityBoardProvider(matchId));
    final matchStarted = boardAsync.maybeWhen(
      data: (board) =>
          board != null && !DateTime.now().isBefore(board.kickoffAt),
      orElse: () => false,
    );
    if (matchStarted) return const SizedBox.shrink();

    final lineup = ref.watch(publishedMatchCompositionProvider(matchId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showAvailabilityFlow)
          MatchAvailabilitySelector(
            matchId: matchId,
            bottomSpacing: bottomSpacing,
          ),
        lineup.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (composition) {
            if (composition == null) {
              return showAvailabilityFlow
                  ? MatchAvailabilityBoardCard(
                      matchId: matchId,
                      bottomSpacing: bottomSpacing,
                    )
                  : const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(bottom: bottomSpacing),
              child: Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.sports_soccer_outlined),
                  ),
                  title: const Text(
                    'Composition publiée',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${composition.formationCode ?? 'Formation libre'} · '
                    '${composition.fieldCount} titulaires · '
                    '${composition.benchCount} remplaçants',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/matches/$matchId/lineup'),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PublicationHeader extends StatelessWidget {
  const _PublicationHeader({required this.composition});

  final MatchComposition composition;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.campaign_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    composition.formationCode ?? 'Formation libre',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Version ${composition.version}'
                    '${composition.publishedAt == null ? '' : ' · ${_formatDateTime(composition.publishedAt!)}'}',
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(
                '${composition.fieldCount} + ${composition.benchCount}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedGroup extends StatelessWidget {
  const _PublishedGroup({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<MatchCompositionEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  '$title (${entries.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('Aucun joueur.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in entries)
                    CompositionPlayerChip(entry: entry),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month à $hour:$minute';
}
