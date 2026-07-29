import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une rencontre passée contre l'adversaire (pour l'historique « 5 dernières »).
class MatchEncounter {
  const MatchEncounter({
    required this.grintaScore,
    required this.opponentScore,
    this.date,
  });

  final int grintaScore;
  final int opponentScore;
  final DateTime? date;
}

/// Données de l'onglet « Info » d'un match : heure, adresse (celle de l'équipe
/// à domicile) et les 5 dernières rencontres contre l'adversaire.
class MatchInfo {
  const MatchInfo({
    required this.kickoffAt,
    required this.address,
    required this.lastEncounters,
    this.matchType = 'championnat',
    this.jerseyNote,
  });

  final DateTime? kickoffAt;
  final String? address;
  final List<MatchEncounter> lastEncounters;
  final String matchType;
  final String? jerseyNote;

  bool get isFriendly => matchType == 'amical';
  String get matchTypeLabel => isFriendly ? 'Match amical' : 'Championnat';
}

String? _clean(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

final matchInfoProvider = FutureProvider.family<MatchInfo, String>((
  ref,
  matchId,
) async {
  final client = ref.watch(supabaseClientProvider);

  final match = await client
      .from('matches')
      .select(
        'kickoff_at, match_date, match_time, location, address, opponent_id, '
        'match_type, jersey_note, opponents(address)',
      )
      .eq('id', matchId)
      .maybeSingle();

  if (match == null) {
    return const MatchInfo(kickoffAt: null, address: null, lastEncounters: []);
  }

  final opponentId = match['opponent_id']?.toString();
  final isHome = (match['location']?.toString() ?? 'domicile') == 'domicile';
  final opponentAddress = match['opponents'] is Map
      ? _clean((match['opponents'] as Map)['address'])
      : null;
  // L'adresse est celle de l'équipe à domicile : repli sur l'adversaire
  // uniquement pour un match à l'extérieur.
  final address = _clean(match['address']) ?? (isHome ? null : opponentAddress);

  final serverKickoff = DateTime.tryParse(
    '${match['kickoff_at'] ?? ''}',
  )?.toLocal();
  final date = match['match_date']?.toString() ?? '';
  final time = match['match_time']?.toString() ?? '00:00:00';
  final kickoffAt = serverKickoff ?? DateTime.tryParse('${date}T$time');

  final encounters = <MatchEncounter>[];
  if (opponentId != null && opponentId.isNotEmpty) {
    final rows = await client.rpc(
      'get_last_opponent_encounters',
      params: {'p_match_id': matchId},
    );
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      encounters.add(
        MatchEncounter(
          grintaScore: (map['grinta_score'] as num?)?.toInt() ?? 0,
          opponentScore: (map['opponent_score'] as num?)?.toInt() ?? 0,
          date: DateTime.tryParse('${map['encounter_date'] ?? ''}')?.toLocal(),
        ),
      );
    }
  }

  return MatchInfo(
    kickoffAt: kickoffAt,
    address: address,
    lastEncounters: encounters,
    matchType: (match['match_type'] ?? 'championnat').toString(),
    jerseyNote: _clean(match['jersey_note']),
  );
});
