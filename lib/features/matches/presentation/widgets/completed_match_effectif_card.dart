import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/matches/data/completed_match_effectif_repository.dart';
import 'package:flutter/material.dart';

class CompletedMatchEffectifCard extends StatelessWidget {
  const CompletedMatchEffectifCard({super.key, required this.effectif});

  final CompletedMatchEffectif effectif;

  @override
  Widget build(BuildContext context) {
    if (effectif.isEmpty) return const SizedBox.shrink();
    final present = effectif.present;
    final absent = effectif.absent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Effectif',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _PresenceGroup(
              title: 'Présents',
              icon: Icons.check_circle_outline_rounded,
              players: present,
            ),
            const SizedBox(height: 14),
            _PresenceGroup(
              title: 'Absents',
              icon: Icons.person_off_outlined,
              players: absent,
              showEmpty: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceGroup extends StatelessWidget {
  const _PresenceGroup({
    required this.title,
    required this.icon,
    required this.players,
    this.showEmpty = false,
  });

  final String title;
  final IconData icon;
  final List<CompletedMatchEffectifPlayer> players;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty && !showEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text(
              '$title (${players.length})',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (players.isEmpty)
          Text(
            'Aucun',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final player in players)
                Chip(
                  label: Text(
                    player.isGuest
                        ? '${player.displayName} · Invité'
                        : player.displayName,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
