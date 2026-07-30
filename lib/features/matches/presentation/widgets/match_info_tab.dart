import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/match_address_sheet.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
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
          padding: EdgeInsets.all(18),
          child: Text('Infos du match indisponibles.'),
        ),
      ),
      data: (info) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: AppFormats.dateTime(info.kickoffAt!),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.groups_rounded,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Rendez-vous  ',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: AppFormats.time(
                            info.kickoffAt!
                                .subtract(const Duration(minutes: 30)),
                          ),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const TextSpan(
                          text: '  (30 min avant)',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
                          fontSize: 17,
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
                      fontSize: 17,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
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
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(
                        text: info.matchTypeLabel,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (info.jerseyNote != null) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final jersey = JerseyOption.fromId(info.jerseyNote);
                    if (jersey == null) {
                      // Anciennes fiches enregistrées avant le sélecteur
                      // visuel : on garde le texte libre tel quel.
                      return _InfoRow(
                        icon: Icons.checkroom_outlined,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Maillot  ',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextSpan(
                                text: info.jerseyNote!,
                                style: const TextStyle(
                                  fontSize: 17,
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
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            height: 50,
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
              const SizedBox(height: 24),
              Text(
                info.lastEncounters.length > 1
                    ? 'Dernières rencontres'
                    : 'Dernière rencontre',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              if (info.lastEncounters.isEmpty)
                Text(
                  'Aucune rencontre passée contre cet adversaire.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).hintColor,
                  ),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 23, color: iconColor),
        const SizedBox(width: 12),
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
              fontSize: 18,
            ),
          ),
          if (encounter.date != null)
            Text(
              AppFormats.date(encounter.date!),
              style: TextStyle(
                color: color.withValues(alpha: .8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
