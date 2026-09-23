import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:flutter/material.dart';

/// En-tête d'une fiche de match terminé (affiche, score, date, adresse) —
/// même gabarit qu'il s'agisse d'un match du système Live ou d'un match
/// archivé importé. Homme du match, buteurs et passeurs se lisent sur le
/// terrain juste en dessous (couronne, ballons, crampons) : l'en-tête ne
/// les répète pas. Seul le lien vers le vote HDM en cours y reste.
///
/// L'affiche et le score restent strictement portés par [MatchFixture]. Les
/// informations absentes de la source sont simplement omises : aucune valeur
/// n'est inventée pour remplir la fiche. La composition est affichée ensuite
/// comme premier module de contenu détaillé, sans bloc Effectif intermédiaire.
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
    this.motmActionLabel,
    this.onMotmTap,
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
  final String? motmActionLabel;
  final VoidCallback? onMotmTap;

  @override
  Widget build(BuildContext context) {
    final cleanDate = dateLabel.trim();
    final cleanTime = kickoffTimeLabel?.trim();
    final cleanType = matchTypeLabel?.trim();
    final cleanAddress = address?.trim();
    final cleanMotmAction = motmActionLabel?.trim();
    final summaryParts = <String>[
      if (cleanDate.isNotEmpty) cleanDate,
      if (cleanTime != null && cleanTime.isNotEmpty) cleanTime,
      if (cleanType != null && cleanType.isNotEmpty) cleanType,
    ];

    final showMotmAction = cleanMotmAction != null &&
        cleanMotmAction.isNotEmpty &&
        onMotmTap != null;

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
            if (summaryParts.isNotEmpty) ...[
              const SizedBox(height: 14),
              _MetadataLine(
                text: summaryParts.join(' · '),
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
            if (showMotmAction) ...[
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 18),
              InkWell(
                onTap: onMotmTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _MetadataLine(
                    text: cleanMotmAction,
                    color: AppTheme.accent,
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppTheme.accent,
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
    required this.text,
    this.color,
    this.trailing,
  });

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = color ?? AppTheme.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w400,
                ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}
