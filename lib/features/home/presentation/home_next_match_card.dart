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
            nameStyle: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 18, height: 1.1),
            foreground: Colors.white,
            textAlign: TextAlign.center,
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 2),
          SizedBox(
            width: 38,
            child: AdminMatchOptionsButton(match: match),
          ),
        ],
        const Icon(Icons.chevron_right, size: 22, color: Color(0xFFD7C8FF)),
      ],
    );

    return Card(
      color: const Color(0xFF25164F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF9B6CFF), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/matches/${match.id}/lineup?section=info'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MatchDateHeader(
                kickoffAt: match.kickoffAt,
                foreground: Colors.white,
                secondary: const Color(0xFFD7C8FF),
                dividerColor: const Color(0xFF7A5AB7),
                child: fixtureRow,
              ),
              if (match.address case final address?) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => showMatchAddressSheet(context, address),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: Color(0xFF9B6CFF),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              color: Color(0xFF9B6CFF),
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF9B6CFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              MatchAvailabilitySelector(
                matchId: match.id,
                embeddedOnDark: true,
                topSpacing: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
