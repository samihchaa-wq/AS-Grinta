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
    final rows = await _client
        .from('profiles')
        .select('id, first_name, surnom, is_goalkeeper')
        .eq('status', 'active')
        .order('first_name');

    final players = (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      final firstName = (map['first_name'] ?? '').toString().trim();
      final nickname = (map['surnom'] ?? '').toString().trim();
      return MatchSheetPlayer(
        id: map['id'].toString(),
        name: nickname.isNotEmpty
            ? nickname
            : (firstName.isNotEmpty ? firstName : 'Joueur sans nom'),
        isGoalkeeper: map['is_goalkeeper'] == true,
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
