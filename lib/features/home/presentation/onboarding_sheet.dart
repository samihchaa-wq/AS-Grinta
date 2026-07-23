import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Fiche d'accueil affichée une seule fois, à la première ouverture, pour
/// présenter les fonctions clés de Ma Petite Grinta.
Future<void> showOnboardingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const _OnboardingContent(),
  );
}

class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent();

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
            const Text('🦩', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              'Bienvenue sur Ma Petite Grinta',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Voici l\'essentiel en quatre points.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            const _OnboardingRow(
              icon: Icons.event_available_rounded,
              title: 'Ta disponibilité',
              subtitle: 'Indique si tu es présent ou absent pour chaque match, '
                  'directement depuis l\'accueil.',
            ),
            const _OnboardingRow(
              icon: Icons.sports_score_rounded,
              title: 'Ton prono',
              subtitle: 'Devine le score avant le coup d\'envoi et grimpe au '
                  'classement des pronostiqueurs.',
            ),
            const _OnboardingRow(
              icon: Icons.groups_rounded,
              title: 'La compo',
              subtitle:
                  'Découvre l\'équipe alignée, l\'homme du match 👑 et les '
                  'buteurs ⚽ une fois le match publié.',
            ),
            const _OnboardingRow(
              icon: Icons.emoji_events_rounded,
              title: 'Tes badges',
              subtitle: 'Débloque des badges dans ton armoire au fil de tes '
                  'exploits et de tes présences.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('C\'est parti !'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingRow extends StatelessWidget {
  const _OnboardingRow({
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
