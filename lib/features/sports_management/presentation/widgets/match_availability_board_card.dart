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
  });

  final String matchId;
  final double bottomSpacing;

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
        if (board == null || !board.isVisibleAt(DateTime.now())) {
          return const SizedBox.shrink();
        }

        final present = board.playersWith(MatchAvailabilityBoardStatus.present);
        final absent = board.playersWith(MatchAvailabilityBoardStatus.absent);
        final noResponse = board.playersWith(
          MatchAvailabilityBoardStatus.noResponse,
        );

        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups_2_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Réponses des joueurs',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'La composition remplacera ces listes dès sa publication.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _AvailabilityGroup(
                    title: 'Présents',
                    players: present,
                    color: const Color(0xFF168A52),
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(height: 14),
                  _AvailabilityGroup(
                    title: 'Absents',
                    players: absent,
                    color: const Color(0xFFB33A3A),
                    icon: Icons.cancel_outlined,
                  ),
                  const SizedBox(height: 14),
                  _AvailabilityGroup(
                    title: 'Sans réponse',
                    players: noResponse,
                    color: const Color(0xFFE08A00),
                    icon: Icons.schedule_outlined,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AvailabilityGroup extends StatelessWidget {
  const _AvailabilityGroup({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Text(
              '$title (${players.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                  backgroundColor: color.withValues(alpha: .1),
                  label: Text(player.displayName),
                ),
            ],
          ),
      ],
    );
  }
}
