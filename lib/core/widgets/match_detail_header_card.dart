import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:flutter/material.dart';

/// Libellé court du type de match, identique à celui des cartes du
/// calendrier : « Amical », « Championnat · J22 », « Match entre nous ».
String calendarMatchTypeLabel(String? matchType, int? championshipRound) {
  return switch (matchType) {
    'entre_nous' => 'Match entre nous',
    'amical' => 'Amical',
    _ => championshipRound == null
        ? 'Championnat'
        : 'Championnat · J$championshipRound',
  };
}

/// En-tête d'une fiche de match, au même gabarit que la carte du calendrier
/// (« Défilé ») : bandeau date • heure • type, affiche sur une ligne (score
/// une fois le match terminé, « VS » avant), puis adresse cliquable. La
/// couleur suit le type de match, comme dans le calendrier.
///
/// Homme du match, buteurs et passeurs se lisent sur le terrain juste en
/// dessous : l'en-tête ne les répète pas. Seul le lien vers le vote HDM en
/// cours y reste. Les informations absentes de la source sont omises.
class MatchDetailHeaderCard extends StatelessWidget {
  const MatchDetailHeaderCard({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    required this.kickoffAt,
    this.showTime = true,
    this.matchType,
    this.typeLabel,
    this.homeScore,
    this.awayScore,
    this.finished = false,
    this.unknownTypeAsFinished = false,
    this.address,
    this.motmActionLabel,
    this.onMotmTap,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final DateTime kickoffAt;
  final bool showTime;

  /// « championnat », « amical » ou « entre_nous » : choisit la couleur.
  final String? matchType;
  final String? typeLabel;
  final int? homeScore;
  final int? awayScore;
  final bool finished;

  /// Archive sans type connu : carte grise plutôt que bleu championnat.
  final bool unknownTypeAsFinished;
  final String? address;
  final String? motmActionLabel;
  final VoidCallback? onMotmTap;

  bool get _isInternal => matchType == 'entre_nous';

  @override
  Widget build(BuildContext context) {
    final cleanAddress = address?.trim();
    final cleanMotmAction = motmActionLabel?.trim();
    final showMotmAction = cleanMotmAction != null &&
        cleanMotmAction.isNotEmpty &&
        onMotmTap != null;
    final surface = CalendarCardPalette.matchSurface(
      matchType,
      unknownAsFinished: unknownTypeAsFinished,
    );
    final border = CalendarCardPalette.matchBorder(
      matchType,
      unknownAsFinished: unknownTypeAsFinished,
    );
    final hasScores = finished && homeScore != null && awayScore != null;

    return Card(
      margin: EdgeInsets.zero,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border, width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: CalendarCardSections(
        header: CalendarDateLine(
          kickoffAt: kickoffAt,
          showTime: showTime,
          // Un match entre nous l'annonce déjà au centre de la carte.
          label: _isInternal && !hasScores ? null : typeLabel,
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isInternal && !hasScores)
              const CalendarCenteredTitle('Match entre nous')
            else
              CalendarScoreline(
                homeName: homeName,
                awayName: awayName,
                grintaIsHome: grintaIsHome,
                homeScore: homeScore,
                awayScore: awayScore,
                finished: hasScores,
              ),
            if (showMotmAction) ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: onMotmTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          cleanMotmAction,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w400,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        footer: cleanAddress != null && cleanAddress.isNotEmpty
            ? CalendarAddressLine(
                cleanAddress,
                onTap: () => showMatchAddressSheet(context, cleanAddress),
              )
            : null,
      ),
    );
  }
}
