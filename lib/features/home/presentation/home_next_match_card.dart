import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_availability_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Carte complète du prochain match, réutilisable sur l'accueil historique et
/// dans le nouvel onglet Matchs fusionné.
class HomeNextMatchCard extends StatelessWidget {
  const HomeNextMatchCard({
    required this.match,
    this.adminActions,
    super.key,
  });

  final HomeMatch match;
  final Widget? adminActions;

  @override
  Widget build(BuildContext context) {
    final homeName = match.isHome ? 'AS Grinta' : match.opponent;
    final awayName = match.isHome ? match.opponent : 'AS Grinta';

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
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: MatchFixture(
                      homeName: homeName,
                      awayName: awayName,
                      grintaIsHome: match.isHome,
                      nameStyle: Theme.of(context).textTheme.titleLarge,
                      foreground: Colors.white,
                    ),
                  ),
                  if (adminActions != null) ...[
                    const SizedBox(width: 6),
                    adminActions!,
                  ],
                  const Icon(Icons.chevron_right, color: Color(0xFFD7C8FF)),
                ],
              ),
              if (match.kickoffAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  AppFormats.dateTime(match.kickoffAt!),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD7C8FF),
                      ),
                ),
              ],
              if (match.address != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => showMatchAddressSheet(context, match.address!),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
                            match.address!,
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
