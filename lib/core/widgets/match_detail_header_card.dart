import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:flutter/material.dart';

/// En-tête d'une fiche de match terminé — même gabarit qu'il s'agisse d'un
/// match du système Live ou d'un match archivé importé.
///
/// L'affiche et le score restent strictement portés par [MatchFixture]. Les
/// informations de contexte sont simplement ajoutées dessous : date/heure,
/// type de match (avec Jx pour le championnat) et adresse lorsqu'elle est
/// connue.
class MatchDetailHeaderCard extends StatelessWidget {
  const MatchDetailHeaderCard({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    required this.homeScore,
    required this.awayScore,
    required this.dateLabel,
    this.matchTypeLabel,
    this.address,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final int homeScore;
  final int awayScore;
  final String dateLabel;
  final String? matchTypeLabel;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final cleanType = matchTypeLabel?.trim();
    final cleanAddress = address?.trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MatchFixture(
              homeName: homeName,
              awayName: awayName,
              grintaIsHome: grintaIsHome,
              homeScore: homeScore,
              awayScore: awayScore,
              finished: true,
              nameStyle: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _MetadataLine(icon: Icons.schedule_rounded, text: dateLabel),
            if (cleanType != null && cleanType.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetadataLine(
                icon: Icons.emoji_events_outlined,
                text: cleanType,
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
                    text: cleanAddress,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppTheme.textFaint,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({
    required this.icon,
    required this.text,
    this.trailing,
  });

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
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing!,
        ],
      ],
    );
  }
}
