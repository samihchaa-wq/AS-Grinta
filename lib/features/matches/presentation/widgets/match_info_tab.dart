import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Onglet « Info » d'une fiche de match : heure, adresse cliquable et les 5
/// dernières rencontres contre l'adversaire.
class MatchInfoTab extends ConsumerWidget {
  const MatchInfoTab({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(matchInfoProvider(matchId));
    return infoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Infos du match indisponibles.'),
        ),
      ),
      data: (info) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: AppFormats.dateTime(info.kickoffAt!),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.groups_rounded,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Rendez-vous  ',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: AppFormats.time(
                            info.kickoffAt!
                                .subtract(const Duration(minutes: 30)),
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
              ],
              const SizedBox(height: 12),
              if (info.address != null)
                InkWell(
                  onTap: () => showMatchAddressSheet(context, info.address!),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _InfoRow(
                      icon: Icons.place_outlined,
                      iconColor: const Color(0xFF9B6CFF),
                      child: Text(
                        info.address!,
                        style: const TextStyle(
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
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                '5 dernières rencontres',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              if (info.lastEncounters.isEmpty)
                Text(
                  'Aucune rencontre passée contre cet adversaire.',
                  style: TextStyle(color: Theme.of(context).hintColor),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final encounter in info.lastEncounters)
                      _EncounterChip(encounter: encounter),
                  ],
                ),
            ],
          ),
        ),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${encounter.grintaScore}–${encounter.opponentScore}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          if (encounter.date != null)
            Text(
              AppFormats.date(encounter.date!),
              style: TextStyle(
                color: color.withValues(alpha: .8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
