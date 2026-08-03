import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpcomingMatchFixtureData {
  const UpcomingMatchFixtureData({
    required this.status,
    required this.location,
    required this.opponentName,
    this.isInternal = false,
  });

  final String status;
  final String location;
  final String opponentName;
  final bool isInternal;

  bool get isUpcoming => status == 'a_venir';
  bool get grintaIsHome => location == 'domicile';
  String get homeName => grintaIsHome ? 'AS Grinta' : opponentName;
  String get awayName => grintaIsHome ? opponentName : 'AS Grinta';
}

final upcomingMatchFixtureProvider =
    FutureProvider.family<UpcomingMatchFixtureData?, String>((
  ref,
  matchId,
) async {
  final core = await ref.watch(matchCoreProvider(matchId).future);
  if (core == null) return null;
  return UpcomingMatchFixtureData(
    status: core.status,
    location: core.location,
    opponentName: core.opponentName,
    isInternal: core.isInternal,
  );
});

/// Affiche les équipes d'un match à venir au-dessus des onglets de sa fiche.
/// Les matchs terminés ou archivés ne rendent rien.
class UpcomingMatchFixtureHeader extends ConsumerWidget {
  const UpcomingMatchFixtureHeader({
    super.key,
    required this.matchId,
    this.bottomSpacing = 16,
  });

  final String matchId;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixture = ref.watch(upcomingMatchFixtureProvider(matchId));
    return fixture.maybeWhen(
      data: (data) {
        if (data == null || !data.isUpcoming) return const SizedBox.shrink();
        if (data.isInternal) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottomSpacing),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Center(
                  child: Text(
                    '⚽ Match entre nous',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Semantics(
                label: '${data.homeName}, domicile, contre '
                    '${data.awayName}, extérieur',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _FixtureTeam(
                        name: data.homeName,
                        isGrinta: data.grintaIsHome,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'VS',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    Expanded(
                      child: _FixtureTeam(
                        name: data.awayName,
                        isGrinta: !data.grintaIsHome,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FixtureTeam extends StatelessWidget {
  const _FixtureTeam({
    required this.name,
    required this.isGrinta,
    required this.textAlign,
  });

  final String name;
  final bool isGrinta;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: isGrinta ? FontWeight.w900 : FontWeight.w800,
      ),
    );
  }
}
