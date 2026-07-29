import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Fiche explicative du fonctionnement du prono de saison. Purement
/// pédagogique — ouverte à la demande depuis la saisie et le classement.
Future<void> showSeasonPronoHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _HelpContent(),
  );
}

class _HelpContent extends StatelessWidget {
  const _HelpContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('📈', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 12),
            Text(
              'Le prono de saison',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Le jeu de pronostic sur toute la saison.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            const _HelpRow(
              icon: Icons.groups_rounded,
              title: 'Tu pronostiques tout l\'effectif',
              subtitle:
                  'Pour chaque joueur, devine son total de buts sur la saison '
                  '(ou de clean sheets pour les gardiens). Il faut remplir '
                  'tout le monde pour être classé.',
            ),
            const _HelpRow(
              icon: Icons.lock_clock_rounded,
              title: 'Secret jusqu\'au lancement',
              subtitle:
                  'Les pronos de chacun restent cachés jusqu\'à ce que l\'admin '
                  'ferme les paris. Ils sont alors révélés et le classement '
                  'démarre.',
            ),
            const _HelpRow(
              icon: Icons.my_location_rounded,
              title: 'Plus proche = plus de points',
              subtitle:
                  'Sur chaque joueur, plus ton prono est proche du total réel, '
                  'plus tu marques. Tomber sur le nombre exact double tes '
                  'points (×2).',
            ),
            const _HelpRow(
              icon: Icons.leaderboard_rounded,
              title: 'Bonus d\'ordre des buteurs',
              subtitle:
                  'Si tu devines aussi le bon ordre (qui marque plus que qui), '
                  'tu gagnes un bonus, maximal quand tout l\'ordre est correct.',
            ),
            const _HelpRow(
              icon: Icons.show_chart_rounded,
              title: 'Une jauge qui vit',
              subtitle:
                  'Au fil des matchs, ta jauge progresse en direct : tu vois '
                  'qui se rapproche de son prono et le classement bouger.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Compris !'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: AppTheme.primaryBright.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.primaryBright.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(icon, color: AppTheme.primaryBright, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
