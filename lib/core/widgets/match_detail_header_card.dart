import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:flutter/material.dart';

/// Module « Info » d'une fiche de match terminé — même gabarit qu'il s'agisse
/// d'un match du système Live ou d'un match archivé importé.
///
/// L'affiche et le score restent strictement portés par [MatchFixture]. Les
/// informations absentes de la source sont simplement omises : aucune valeur
/// n'est inventée pour remplir la fiche.
class MatchDetailHeaderCard extends StatelessWidget {
  const MatchDetailHeaderCard({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    required this.homeScore,
    required this.awayScore,
    required this.dateLabel,
    this.kickoffTimeLabel,
    this.matchTypeLabel,
    this.address,
    this.manOfMatchNames = const [],
    this.motmActionLabel,
    this.onMotmTap,
    this.scorerLabels = const [],
    this.teamScoredZero = false,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final int homeScore;
  final int awayScore;
  final String dateLabel;
  final String? kickoffTimeLabel;
  final String? matchTypeLabel;
  final String? address;
  final List<String> manOfMatchNames;
  final String? motmActionLabel;
  final VoidCallback? onMotmTap;
  final List<String> scorerLabels;
  final bool teamScoredZero;

  @override
  Widget build(BuildContext context) {
    final cleanTime = kickoffTimeLabel?.trim();
    final cleanType = matchTypeLabel?.trim();
    final cleanAddress = address?.trim();
    final cleanMotmAction = motmActionLabel?.trim();
    final motmNames = manOfMatchNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final scorers = scorerLabels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Info',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            MatchFixture(
              homeName: homeName,
              awayName: awayName,
              grintaIsHome: grintaIsHome,
              homeScore: homeScore,
              awayScore: awayScore,
              finished: true,
              nameStyle: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _MetadataLine(
              icon: Icons.calendar_today_outlined,
              text: 'Date · $dateLabel',
            ),
            if (cleanTime != null && cleanTime.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetadataLine(
                icon: Icons.schedule_rounded,
                text: 'Coup d’envoi · $cleanTime',
              ),
            ],
            if (cleanType != null && cleanType.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetadataLine(
                icon: Icons.emoji_events_outlined,
                text: 'Type · $cleanType',
              ),
            ],
            if (cleanAddress != null && cleanAddress.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => showMatchAddressSheet(context, cleanAddress),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _MetadataLine(
                    icon: Icons.place_outlined,
                    text: 'Adresse · $cleanAddress',
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppTheme.textFaint,
                    ),
                  ),
                ),
              ),
            ],
            if (motmNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetadataLine(
                icon: Icons.workspace_premium_outlined,
                text: 'HDM · ${motmNames.join(' · ')}',
              ),
            ] else if (cleanMotmAction != null &&
                cleanMotmAction.isNotEmpty &&
                onMotmTap != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onMotmTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _MetadataLine(
                    icon: Icons.how_to_vote_outlined,
                    text: cleanMotmAction,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppTheme.textFaint,
                    ),
                  ),
                ),
              ),
            ],
            if (scorers.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetadataLine(
                icon: Icons.sports_soccer_rounded,
                text: 'Buteurs · ${scorers.join(' · ')}',
              ),
            ] else if (teamScoredZero) ...[
              const SizedBox(height: 8),
              const _MetadataLine(
                icon: Icons.sports_soccer_rounded,
                text: 'Buteurs · Aucun',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}
