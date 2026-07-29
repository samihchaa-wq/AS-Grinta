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
          child: MatchFixture(
            homeName: homeName,
            awayName: awayName,
            grintaIsHome: match.isHome,
            nameStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 19,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
            foreground: AppTheme.textPrimary,
            textAlign: TextAlign.center,
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: AdminMatchOptionsButton(match: match),
          ),
        ],
        const SizedBox(width: 2),
        const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: AppTheme.primaryBright,
        ),
      ],
    );

    return Card(
      color: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: AppTheme.primaryBright.withValues(alpha: .55),
          width: 1.2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.surfaceHigh.withValues(alpha: .96),
              AppTheme.surface.withValues(alpha: .9),
            ],
          ),
        ),
        child: InkWell(
          onTap: () => context.push('/matches/${match.id}/lineup?section=info'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.primaryBright.withValues(alpha: .35),
                        ),
                      ),
                      child: const Text(
                        'PROCHAIN MATCH',
                        style: TextStyle(
                          color: AppTheme.primaryBright,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      match.isHome
                          ? Icons.home_rounded
                          : Icons.directions_bus_filled_rounded,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      match.isHome ? 'Domicile' : 'Extérieur',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                MatchDateHeader(
                  kickoffAt: match.kickoffAt,
                  foreground: AppTheme.textPrimary,
                  secondary: AppTheme.textSecondary,
                  dividerColor: AppTheme.outline.withValues(alpha: .7),
                  child: fixtureRow,
                ),
                if (match.address case final address?) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => showMatchAddressSheet(context, address),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: AppTheme.primaryBright,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                MatchAvailabilitySelector(
                  matchId: match.id,
                  embeddedOnDark: true,
                  topSpacing: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
