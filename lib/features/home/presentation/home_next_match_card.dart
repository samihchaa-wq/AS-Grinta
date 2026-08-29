import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/core/widgets/moment_card_watermark.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Carte d'un match actif, réutilisable pour « Prochain », « En direct »
/// et « À valider », avec le même rendu que les autres matchs du calendrier.
class HomeNextMatchCard extends StatelessWidget {
  const HomeNextMatchCard({
    required this.match,
    required this.isAdmin,
    this.initialSection = 'info',
    this.showAvailability = true,
    super.key,
  });

  final MatchModel match;
  final bool isAdmin;
  final String initialSection;
  final bool showAvailability;

  @override
  Widget build(BuildContext context) {
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';
    final cardSurface = CalendarCardPalette.matchSurface(match.matchType);
    final cardBorder = CalendarCardPalette.matchBorder(match.matchType);

    final fixtureRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: match.isInternal
              ? Text(
                  'Match entre nous',
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                )
              : MatchFixture(
                  homeName: homeName,
                  awayName: awayName,
                  grintaIsHome: match.isHome,
                  nameStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                  foreground: AppTheme.textPrimary,
                  textAlign: TextAlign.start,
                ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: AppSpacing.microGap),
          SizedBox(
            width: 48,
            child: IconTheme(
              data: IconThemeData(color: cardBorder),
              child: AdminMatchOptionsButton(match: match),
            ),
          ),
        ],
        const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppTheme.textFaint,
        ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        12,
        AppSpacing.cardPadding,
        13,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MatchDateHeader(
            kickoffAt: match.kickoffAt,
            foreground: AppTheme.textPrimary,
            secondary: AppTheme.textPrimary,
            dividerColor: cardBorder,
            child: fixtureRow,
          ),
          const SizedBox(height: 7),
          Text(
            match.calendarTypeLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cardBorder,
                  fontWeight: FontWeight.w900,
                ),
          ),
          if (match.address case final address?) ...[
            const SizedBox(height: AppSpacing.contentGap),
            InkWell(
              onTap: () => showMatchAddressSheet(context, address),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place_outlined, size: 16, color: cardBorder),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (showAvailability)
            MatchAvailabilitySelector(
              matchId: match.id,
              embeddedOnDark: true,
              topSpacing: 10,
            ),
        ],
      ),
    );

    final decoratedContent = MomentCardWatermark(
      kind: momentWatermarkKindForMatchType(match.matchType),
      color: cardBorder,
      child: content,
    );

    return Card(
      color: cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: cardBorder, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/matches/${match.id}/lineup?section=$initialSection',
        ),
        child: decoratedContent,
      ),
    );
  }
}
