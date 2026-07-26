import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpcomingMatchFixtureData {
  const UpcomingMatchFixtureData({
    required this.status,
    required this.location,
    required this.opponentName,
  });

  factory UpcomingMatchFixtureData.fromJson(Map<String, dynamic> json) {
    final opponent = json['opponents'];
    final opponentName = opponent is Map
        ? opponent['name']?.toString().trim()
        : null;
    return UpcomingMatchFixtureData(
      status: (json['status'] ?? '').toString(),
      location: (json['location'] ?? 'domicile').toString(),
      opponentName: opponentName == null || opponentName.isEmpty
          ? 'Adversaire'
          : opponentName,
    );
  }

  final String status;
  final String location;
  final String opponentName;

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
      final client = ref.watch(supabaseClientProvider);
      final row = await client
          .from('matches')
          .select('status, location, opponents(name)')
          .eq('id', matchId)
          .maybeSingle();
      if (row == null) return null;
      return UpcomingMatchFixtureData.fromJson(Map<String, dynamic>.from(row));
    });

/// Affiche l'affiche domicile/extérieur d'un match à venir au-dessus des
/// onglets de sa fiche. Les matchs terminés ou archivés ne rendent rien.
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
        return Padding(
          padding: EdgeInsets.only(bottom: bottomSpacing),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Semantics(
                label:
                    '${data.homeName}, domicile, contre '
                    '${data.awayName}, extérieur',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _FixtureTeam(
                        label: 'Domicile',
                        name: data.homeName,
                        isGrinta: data.grintaIsHome,
                        alignment: CrossAxisAlignment.end,
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
                        label: 'Extérieur',
                        name: data.awayName,
                        isGrinta: !data.grintaIsHome,
                        alignment: CrossAxisAlignment.start,
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
    required this.label,
    required this.name,
    required this.isGrinta,
    required this.alignment,
    required this.textAlign,
  });

  final String label;
  final String name;
  final bool isGrinta;
  final CrossAxisAlignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: isGrinta ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
