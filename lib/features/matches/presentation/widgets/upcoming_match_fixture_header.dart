import 'package:as_grinta/core/widgets/match_detail_header_card.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpcomingMatchFixtureData {
  const UpcomingMatchFixtureData({
    required this.status,
    required this.location,
    required this.opponentName,
    this.kickoffAt,
    this.address,
    this.matchType = 'championnat',
    this.championshipRound,
  });

  final String status;
  final String location;
  final String opponentName;
  final DateTime? kickoffAt;
  final String? address;
  final String matchType;
  final int? championshipRound;

  bool get isUpcoming => status == 'a_venir';
  bool get isFinished => status == 'termine' || status == 'archive';
  bool get isCancelled => status == 'annule';
  bool get isInternal => matchType == 'entre_nous';
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
    kickoffAt: core.kickoffAt,
    address: core.address,
    matchType: core.matchType,
    championshipRound: core.championshipRound,
  );
});

/// Carte du match au-dessus des onglets de sa fiche, au même gabarit que le
/// calendrier : date, heure et type, affiche, adresse cliquable. L'onglet Info
/// ne répète donc plus ces informations. Les matchs terminés ou annulés ne
/// rendent rien (ils ont leur propre fiche).
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
        final kickoffAt = data?.kickoffAt;
        if (data == null ||
            kickoffAt == null ||
            data.isFinished ||
            data.isCancelled) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: MatchDetailHeaderCard(
            homeName: data.homeName,
            awayName: data.awayName,
            grintaIsHome: data.grintaIsHome,
            kickoffAt: kickoffAt,
            matchType: data.matchType,
            typeLabel: calendarMatchTypeLabel(
              data.matchType,
              data.championshipRound,
            ),
            address: data.address,
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
