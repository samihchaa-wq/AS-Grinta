import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchAvailabilityBoardCard extends ConsumerWidget {
  const MatchAvailabilityBoardCard({
    super.key,
    required this.matchId,
    this.bottomSpacing = 0,
    this.compact = false,
    this.showAfterComposition = false,
  });

  final String matchId;
  final double bottomSpacing;
  final bool compact;
  final bool showAfterComposition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sportsManagementEnabledProvider)) {
      return const SizedBox.shrink();
    }

    final boardAsync = ref.watch(matchAvailabilityBoardProvider(matchId));
    return boardAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (board) {
        final now = DateTime.now();
        final visible =
            board != null &&
            (board.isVisibleAt(now) ||
                (showAfterComposition && now.isBefore(board.kickoffAt)));
        if (!visible) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: Card(
            margin: compact ? EdgeInsets.zero : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MatchAvailabilityBoardContent(board: board),
            ),
          ),
        );
      },
    );
  }
}

class MatchAvailabilityBoardContent extends StatelessWidget {
  const MatchAvailabilityBoardContent({super.key, required this.board});

  final MatchAvailabilityBoard board;

  @override
  Widget build(BuildContext context) {
    final absent = board.playersWith(MatchAvailabilityBoardStatus.absent);
    final noResponse = board.playersWith(
      MatchAvailabilityBoardStatus.noResponse,
    );
    final overLimit = board.convoked.length > board.squadSizeLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_2_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Effectif',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (overLimit)
              const Tooltip(
                message: 'La limite indicative est dépassée',
                child: Icon(Icons.warning_amber_rounded, color: Colors.orange),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Mise à jour en direct · limite indicative ${board.squadSizeLimit}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final groups = [
              _BoardGroup(
                title: 'Convoqués',
                players: board.convoked,
                color: const Color(0xFF168A52),
                icon: Icons.check_circle_outline,
              ),
              _BoardGroup(
                title: 'Liste d’attente',
                players: board.waitlisted,
                color: const Color(0xFFE08A00),
                icon: Icons.hourglass_top_rounded,
              ),
              _BoardGroup(
                title: 'Absents',
                players: absent,
                color: const Color(0xFFB33A3A),
                icon: Icons.cancel_outlined,
              ),
              _BoardGroup(
                title: 'Sans réponse',
                players: noResponse,
                color: const Color(0xFF6B7280),
                icon: Icons.schedule_outlined,
              ),
            ];
            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < groups.length; index += 1) ...[
                    Expanded(child: groups[index]),
                    if (index < groups.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var index = 0; index < groups.length; index += 1) ...[
                  groups[index],
                  if (index < groups.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _BoardGroup extends StatelessWidget {
  const _BoardGroup({
    required this.title,
    required this.players,
    required this.color,
    required this.icon,
  });

  final String title;
  final List<MatchAvailabilityBoardPlayer> players;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$title (${players.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (players.isEmpty)
            Text('Aucun joueur.', style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final player in players)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: color.withValues(alpha: .45)),
                    backgroundColor: color.withValues(alpha: .10),
                    avatar: player.isGuest
                        ? const Icon(Icons.person_add_alt_1_outlined, size: 16)
                        : null,
                    label: Text(player.firstNameOnly),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
