import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/weather/presentation/match_weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';

/// Onglet « Info » d'une fiche de match : heure, adresse cliquable et les
/// dernières rencontres contre l'adversaire.
class MatchInfoTab extends ConsumerWidget {
  const MatchInfoTab({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(matchInfoProvider(matchId));
    return infoAsync.when(
      loading: () => const Center(child: GrintaProgressIndicator()),
      error: (_, __) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Infos du match indisponibles.'),
        ),
      ),
      data: (info) {
        final encounters = info.lastEncounters.take(5).toList();
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.kickoffAt != null) ...[
                  _InfoRow(
                    icon: Icons.sports_soccer_rounded,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Coup d’envoi  ',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: AppFormats.dateTime(info.kickoffAt!),
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.groups_rounded,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Rendez-vous  ',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: AppFormats.time(
                              info.kickoffAt!.subtract(
                                const Duration(minutes: 30),
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(
                            text: '  (30 min avant)',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (info.address != null)
                  InkWell(
                    onTap: () => showMatchAddressSheet(context, info.address!),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _InfoRow(
                        icon: Icons.place_outlined,
                        iconColor: const Color(0xFF9B6CFF),
                        child: Text(
                          info.address!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Color(0xFF9B6CFF),
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF9B6CFF),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  _InfoRow(
                    icon: Icons.place_outlined,
                    child: Text(
                      'Adresse non renseignée.',
                      style: TextStyle(
                        fontSize: 15.5,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                _InfoRow(
                  icon: info.isFriendly
                      ? Icons.handshake_outlined
                      : Icons.emoji_events_outlined,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Type de match  ',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: info.matchTypeLabel,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (info.jerseyNote != null) ...[
                  const SizedBox(height: 9),
                  Builder(
                    builder: (context) {
                      final jersey = JerseyOption.fromId(info.jerseyNote);
                      if (jersey == null) {
                        return _InfoRow(
                          icon: Icons.checkroom_outlined,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Maillot  ',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                TextSpan(
                                  text: info.jerseyNote!,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return _InfoRow(
                        icon: Icons.checkroom_outlined,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Maillot  ',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
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
                if (info.kickoffAt != null)
                  MatchWeatherCard(
                    matchId: matchId,
                    kickoffAt: info.kickoffAt!,
                    plannedDurationMinutes: 90,
                  ),
                const SizedBox(height: 12),
                Text(
                  encounters.length > 1
                      ? '5 dernières rencontres'
                      : 'Dernière rencontre',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                if (encounters.isEmpty)
                  Text(
                    'Aucune rencontre passée contre cet adversaire.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).hintColor,
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0;
                          index < encounters.length;
                          index++) ...[
                        if (index > 0) const SizedBox(width: 4),
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
  const _InfoRow({required this.icon, required this.child, this.iconColor});

  final IconData icon;
  final Widget child;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 21, color: iconColor),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
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
    return Container(
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
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          if (encounter.date != null) ...[
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppFormats.date(encounter.date!),
                maxLines: 1,
                style: TextStyle(
                  color: color.withValues(alpha: .82),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
