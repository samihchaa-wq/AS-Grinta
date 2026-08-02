import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/widgets/admin_match_options_button.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Carte complète du prochain match, réutilisable sur l'accueil historique et
/// dans le nouvel onglet Matchs fusionné.
class HomeNextMatchCard extends StatelessWidget {
  const HomeNextMatchCard({
    required this.match,
    required this.isAdmin,
    super.key,
  });

  final MatchModel match;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final opponent = match.opponentName ?? 'Adversaire';
    final homeName = match.isHome ? 'AS Grinta' : opponent;
    final awayName = match.isHome ? opponent : 'AS Grinta';

    final fixtureRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: match.isInternal
              ? Text(
                  '⚽ Match entre nous',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                )
              : MatchFixture(
                  homeName: homeName,
                  awayName: awayName,
                  grintaIsHome: match.isHome,
                  nameStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                  foreground: AppTheme.textPrimary,
                  textAlign: TextAlign.center,
                ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 4),
          SizedBox(width: 40, child: AdminMatchOptionsButton(match: match)),
        ],
        const SizedBox(width: 2),
        Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppTheme.textFaint.withValues(alpha: .72),
        ),
      ],
    );

    return Card(
      color: Colors.transparent,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .18),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(color: AppTheme.primaryBright.withValues(alpha: .3)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.surfaceHero,
              AppTheme.surface,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, -.08),
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.primary.withValues(alpha: .16),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () =>
                  context.push('/matches/${match.id}/lineup?section=info'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MatchDateHeader(
                      kickoffAt: match.kickoffAt,
                      foreground: AppTheme.textPrimary,
                      secondary: AppTheme.textSecondary,
                      dividerColor: AppTheme.outline.withValues(alpha: .5),
                      child: fixtureRow,
                    ),
                    if (match.address case final address?) ...[
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => showMatchAddressSheet(context, address),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                size: 17,
                                color: AppTheme.textFaint,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textFaint,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    MatchAvailabilitySelector(
                      matchId: match.id,
                      embeddedOnDark: true,
                      topSpacing: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
