import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Données légères communes à toute la fiche d'un match.
///
/// Elles sont chargées une seule fois puis partagées entre le bandeau, les
/// règles temporelles et l'onglet Info. L'historique des confrontations reste
/// volontairement séparé afin de n'être demandé que lorsque l'onglet Info en a
/// réellement besoin.
class MatchCore {
  const MatchCore({
    required this.kickoffAt,
    required this.address,
    required this.opponentId,
    required this.status,
    required this.location,
    required this.opponentName,
    this.matchType = 'championnat',
    this.jerseyNote,
  });

  final DateTime? kickoffAt;
  final String? address;
  final String? opponentId;
  final String status;
  final String location;
  final String opponentName;
  final String matchType;
  final String? jerseyNote;

  bool get isFriendly => matchType == 'amical';
  bool get isInternal => matchType == 'entre_nous';
  bool get isUpcoming => status == 'a_venir';
  bool get grintaIsHome => location == 'domicile';
}

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
  bool get isInternal => matchType == 'entre_nous';
  String get matchTypeLabel {
    if (isInternal) return 'Match entre nous';
    return isFriendly ? 'Match amical' : 'Championnat';
  }
}

String? _clean(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

const _emptyMatchInfo = MatchInfo(
  kickoffAt: null,
  address: null,
  lastEncounters: [],
);

MatchInfo _infoFromCore(
  MatchCore core, {
  List<MatchEncounter> encounters = const [],
}) {
  return MatchInfo(
    kickoffAt: core.kickoffAt,
    address: core.address,
    lastEncounters: encounters,
    matchType: core.matchType,
    jerseyNote: core.jerseyNote,
  );
}

final matchCoreProvider = FutureProvider.family<MatchCore?, String>((
  ref,
  matchId,
) async {
  final client = ref.watch(supabaseClientProvider);
  final match = await client
      .from('matches')
      .select(
        'kickoff_at, match_date, match_time, status, location, address, '
        'opponent_id, match_type, jersey_note, opponents(name, address)',
      )
      .eq('id', matchId)
      .maybeSingle();

  if (match == null) return null;

  final opponent = match['opponents'] is Map
      ? Map<String, dynamic>.from(match['opponents'] as Map)
      : const <String, dynamic>{};
  final opponentName = _clean(opponent['name']) ?? 'Adversaire';
  final opponentAddress = _clean(opponent['address']);
  final location = (match['location']?.toString() ?? 'domicile').trim();
  final isHome = location == 'domicile';
  final address = _clean(match['address']) ?? (isHome ? null : opponentAddress);

  final serverKickoff = DateTime.tryParse('${match['kickoff_at'] ?? ''}');
  final date = match['match_date']?.toString() ?? '';
  final time = match['match_time']?.toString() ?? '00:00:00';
  final kickoffAt = serverKickoff ?? DateTime.tryParse('${date}T$time');

  return MatchCore(
    kickoffAt: kickoffAt,
    address: address,
    opponentId: _clean(match['opponent_id']),
    status: (match['status'] ?? '').toString(),
    location: location,
    opponentName: opponentName,
    matchType: (match['match_type'] ?? 'championnat').toString(),
    jerseyNote: _clean(match['jersey_note']),
  );
});

/// Version légère utilisée par la structure de la fiche (onglets, temporalité,
/// admin). Elle n'effectue aucune lecture de l'historique des confrontations.
final matchInfoProvider = FutureProvider.family<MatchInfo, String>((
  ref,
  matchId,
) async {
  final core = await ref.watch(matchCoreProvider(matchId).future);
  return core == null ? _emptyMatchInfo : _infoFromCore(core);
});

/// Version complète chargée uniquement par l'onglet Info.
final matchDetailedInfoProvider = FutureProvider.family<MatchInfo, String>((
  ref,
  matchId,
) async {
  final client = ref.watch(supabaseClientProvider);
  final baseInfo = await ref.watch(matchInfoProvider(matchId).future);
  final core = await ref.watch(matchCoreProvider(matchId).future);
  if (core == null) return baseInfo;

  final encounters = <MatchEncounter>[];
  if (core.opponentId != null && core.opponentId!.isNotEmpty) {
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
    kickoffAt: baseInfo.kickoffAt,
    address: baseInfo.address,
    lastEncounters: encounters,
    matchType: baseInfo.matchType,
    jerseyNote: baseInfo.jerseyNote,
  );
});
