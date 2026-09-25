import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/matches/presentation/match_encounter_route.dart';
import 'package:as_grinta/features/weather/presentation/match_weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

/// Onglet « Info » d'une fiche de match : rendez-vous, maillot, météo et les
/// dernières rencontres contre l'adversaire. Date, heure, type et adresse sont
/// portés par la carte du match au-dessus des onglets.
class MatchInfoTab extends ConsumerWidget {
  const MatchInfoTab({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(matchDetailedInfoProvider(matchId));
    return infoAsync.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (_, __) => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.cardPadding),
          child: Text('Infos du match indisponibles.'),
        ),
      ),
      data: (info) {
        final encounters = info.lastEncounters.take(5).toList();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.effectiveMeetingAt != null)
                  _InfoRow(
                    child: Text(
                      'Rendez-vous  ${AppFormats.time(info.effectiveMeetingAt!)}',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                if (info.jerseyNote != null) ...[
                  const SizedBox(height: AppSpacing.contentGap),
                  Builder(
                    builder: (context) {
                      final jersey = JerseyOption.fromId(info.jerseyNote);
                      if (jersey == null) {
                        return _InfoRow(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Maillot  ',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                TextSpan(
                                  text: info.jerseyNote!,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return _InfoRow(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Maillot  ',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            SizedBox(
                              width: 34,
                              height: 38,
                              child: Image.asset(
                                jersey.assetPath,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                // On ne récupère la météo au coup d'envoi que quand une
                // adresse est renseignée : sinon la carte affichait la météo
                // d'un lieu par défaut (généralement Toulouse), sans rapport
                // avec le match — trompeur.
                if (info.kickoffAt != null && info.address != null)
                  MatchWeatherCard(
                    matchId: matchId,
                    kickoffAt: info.kickoffAt!,
                    plannedDurationMinutes: 90,
                  ),
                if (!info.isInternal)
                  const SizedBox(height: AppSpacing.sectionGap),
                if (!info.isInternal)
                  Text(
                    encounters.length > 1
                        ? '5 dernières rencontres'
                        : 'Dernière rencontre',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w400),
                  ),
                if (!info.isInternal)
                  const SizedBox(height: AppSpacing.contentGap),
                if (!info.isInternal && encounters.isEmpty)
                  Text(
                    'Aucune rencontre passée contre cet adversaire.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).hintColor,
                    ),
                  )
                else if (!info.isInternal)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0;
                          index < encounters.length;
                          index++) ...[
                        if (index > 0)
                          const SizedBox(width: AppSpacing.microGap),
                        Expanded(
                          child: _EncounterChip(encounter: encounters[index]),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Expanded(child: child)]);
  }
}

class _EncounterChip extends StatelessWidget {
  const _EncounterChip({required this.encounter});

  final MatchEncounter encounter;

  @override
  Widget build(BuildContext context) {
    final color = MatchFixture.resultColor(
      encounter.grintaScore,
      encounter.opponentScore,
    );
    final route = matchEncounterRoute(
      encounterId: encounter.id,
      isHistorical: encounter.isHistorical,
    );
    final dateLabel =
        encounter.date == null ? null : AppFormats.date(encounter.date!);
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${encounter.grintaScore}–${encounter.opponentScore}',
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w400,
                fontSize: 15,
              ),
            ),
          ),
          if (dateLabel != null) ...[
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dateLabel,
                maxLines: 1,
                style: TextStyle(
                  color: color.withValues(alpha: .82),
                  fontSize: 9,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (route == null) return chip;
    return Semantics(
      button: true,
      label: dateLabel == null
          ? 'Ouvrir ce match'
          : 'Ouvrir le match du $dateLabel',
      child: InkWell(
        onTap: () => context.push(route),
        borderRadius: BorderRadius.circular(8),
        child: chip,
      ),
    );
  }
}
