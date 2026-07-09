import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchParticipantOption {
  const MatchParticipantOption({
    required this.profileId,
    required this.name,
    required this.isGoalkeeper,
    required this.selected,
  });

  final String profileId;
  final String name;
  final bool isGoalkeeper;
  final bool selected;
}

class MatchParticipantsRepository {
  MatchParticipantsRepository(this._client);

  final SupabaseClient _client;

  Future<List<MatchParticipantOption>> fetchOptions(String matchId) async {
    final match = await _client
        .from('matches')
        .select('season_id')
        .eq('id', matchId)
        .single();
    final seasonId = match['season_id'].toString();

    final players = await _client
        .from('season_players')
        .select(
            'profile_id, is_goalkeeper_snapshot, '
            'profiles!inner(first_name, last_name, surnom, status)')
        .eq('season_id', seasonId);
    final selectedRows = await _client
        .from('match_participants')
        .select('profile_id')
        .eq('match_id', matchId);
    final selectedIds = (selectedRows as List)
        .map((row) => Map<String, dynamic>.from(row)['profile_id'].toString())
        .toSet();

    final options = <MatchParticipantOption>[];
    for (final row in players as List) {
      final map = Map<String, dynamic>.from(row);
      final profile = Map<String, dynamic>.from(map['profiles'] as Map);
      if (profile['status'] != 'active') continue;
      final profileId = map['profile_id'].toString();
      final surnom = profile['surnom']?.toString().trim() ?? '';
      final firstName = (profile['first_name'] ?? '').toString().trim();
      final lastName = (profile['last_name'] ?? '').toString().trim();
      final name = surnom.isNotEmpty
          ? surnom
          : '$firstName $lastName'.trim();
      options.add(
        MatchParticipantOption(
          profileId: profileId,
          name: name.isEmpty ? 'Joueur sans nom' : name,
          isGoalkeeper: map['is_goalkeeper_snapshot'] == true,
          selected: selectedIds.contains(profileId),
        ),
      );
    }
    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  Future<void> setSelected({
    required String matchId,
    required String profileId,
    required bool selected,
  }) async {
    if (selected) {
      await _client.from('match_participants').upsert(
        {'match_id': matchId, 'profile_id': profileId},
        onConflict: 'match_id,profile_id',
      );
    } else {
      await _client
          .from('match_participants')
          .delete()
          .eq('match_id', matchId)
          .eq('profile_id', profileId);
    }
  }
}

final matchParticipantsRepositoryProvider =
    Provider<MatchParticipantsRepository>((ref) {
  return MatchParticipantsRepository(ref.watch(supabaseClientProvider));
});

final matchParticipantOptionsProvider =
    FutureProvider.family<List<MatchParticipantOption>, String>((ref, matchId) {
  return ref.watch(matchParticipantsRepositoryProvider).fetchOptions(matchId);
});
