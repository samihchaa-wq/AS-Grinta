import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MatchSheetPlayer {
  const MatchSheetPlayer({
    required this.id,
    required this.name,
    required this.isGoalkeeper,
  });

  final String id;
  final String name;
  final bool isGoalkeeper;
}

class MatchFinalizationContext {
  const MatchFinalizationContext({required this.players});

  final List<MatchSheetPlayer> players;
}

class MatchFinalizationRepository {
  MatchFinalizationRepository(this._client);

  final SupabaseClient _client;

  Future<MatchFinalizationContext> fetch(String matchId) async {
    final match = await _client
        .from('matches')
        .select('season_id')
        .eq('id', matchId)
        .single();
    final seasonId = match['season_id'].toString();

    final membershipRows = await _client
        .from('season_players')
        .select('profile_id,is_goalkeeper_snapshot')
        .eq('season_id', seasonId);
    final memberships = <String, bool>{};
    for (final row in membershipRows as List) {
      final map = Map<String, dynamic>.from(row);
      memberships[map['profile_id'].toString()] =
          map['is_goalkeeper_snapshot'] == true;
    }
    if (memberships.isEmpty) {
      return const MatchFinalizationContext(players: []);
    }

    final profileRows = await _client
        .from('profiles')
        .select('id,first_name,surnom,status')
        .inFilter('id', memberships.keys.toList())
        .eq('status', 'active')
        .order('first_name');

    final players = (profileRows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final firstName = (map['first_name'] ?? '').toString().trim();
      final nickname = (map['surnom'] ?? '').toString().trim();
      final id = map['id'].toString();
      return MatchSheetPlayer(
        id: id,
        name: nickname.isNotEmpty
            ? nickname
            : (firstName.isNotEmpty ? firstName : 'Joueur sans nom'),
        isGoalkeeper: memberships[id] == true,
      );
    }).toList();

    return MatchFinalizationContext(players: players);
  }
}

final matchFinalizationRepositoryProvider =
    Provider<MatchFinalizationRepository>((ref) {
  return MatchFinalizationRepository(ref.watch(supabaseClientProvider));
});

final matchFinalizationContextProvider =
    FutureProvider.family<MatchFinalizationContext, String>((ref, matchId) {
  return ref.watch(matchFinalizationRepositoryProvider).fetch(matchId);
});
