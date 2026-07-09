import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/live/domain/live_gameplay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveFormationDefinition {
  const LiveFormationDefinition({
    required this.code,
    required this.label,
    required this.slots,
  });

  final String code;
  final String label;
  final List<String> slots;
}

class LiveSetupData {
  const LiveSetupData({
    required this.players,
    required this.formations,
  });

  final List<LivePlayer> players;
  final List<LiveFormationDefinition> formations;
}

class LiveSetupRepository {
  LiveSetupRepository(this._client);

  final SupabaseClient _client;

  Future<LiveSetupData> fetch(String matchId) async {
    final participantsResponse = await _client
        .from('match_participants')
        .select('profile_id, profiles!inner(first_name, last_name, status)')
        .eq('match_id', matchId);

    final players = <LivePlayer>[];
    for (final row in participantsResponse as List) {
      final map = Map<String, dynamic>.from(row);
      final profile = Map<String, dynamic>.from(map['profiles'] as Map);
      if (profile['status'] != 'active') continue;
      final firstName = (profile['first_name'] ?? '').toString().trim();
      final lastName = (profile['last_name'] ?? '').toString().trim();
      final name = '$firstName $lastName'.trim();
      players.add(
        LivePlayer(
          id: map['profile_id'].toString(),
          name: name.isEmpty ? 'Joueur sans nom' : name,
        ),
      );
    }

    final formationsResponse = await _client
        .from('formations')
        .select('code, label, slots')
        .order('code');
    final formations = <LiveFormationDefinition>[];
    for (final row in formationsResponse as List) {
      final map = Map<String, dynamic>.from(row);
      final rawSlots = map['slots'];
      final slots = rawSlots is List
          ? rawSlots
              .map((slot) => Map<String, dynamic>.from(slot as Map))
              .map((slot) => slot['code']?.toString())
              .whereType<String>()
              .where((code) => code.isNotEmpty)
              .toList()
          : <String>[];
      formations.add(
        LiveFormationDefinition(
          code: map['code'].toString(),
          label: map['label'].toString(),
          slots: slots,
        ),
      );
    }

    return LiveSetupData(players: players, formations: formations);
  }
}

final liveSetupRepositoryProvider = Provider<LiveSetupRepository>((ref) {
  return LiveSetupRepository(ref.watch(supabaseClientProvider));
});

final liveSetupProvider =
    FutureProvider.family<LiveSetupData, String>((ref, matchId) {
  return ref.watch(liveSetupRepositoryProvider).fetch(matchId);
});
