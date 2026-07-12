import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un joueur de l'effectif : une simple fiche nom/prénom (+ gardien), sans
/// compte. C'est sur ces joueurs que portent les buts, clean sheets et
/// pronostics de saison.
class RosterPlayer {
  const RosterPlayer({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.isGoalkeeper,
    required this.isActive,
  });

  final String id;
  final String firstName;
  final String lastName;
  final bool isGoalkeeper;
  final bool isActive;

  String get displayName {
    final first = firstName.trim();
    if (first.isNotEmpty) return first;
    return lastName.trim().isEmpty ? 'Joueur' : lastName.trim();
  }

  String get fullName => '$firstName $lastName'.trim();
}

class RosterRepository {
  RosterRepository(this._client);

  final SupabaseClient _client;

  Future<String?> openSeasonId() async {
    final row = await _client
        .from('seasons')
        .select('id')
        .eq('status', 'open')
        .maybeSingle();
    return row?['id']?.toString();
  }

  Future<List<RosterPlayer>> fetchRoster(String seasonId) async {
    final rows = await _client
        .from('season_players')
        .select('id,first_name,last_name,is_goalkeeper,is_active')
        .eq('season_id', seasonId)
        .order('is_active', ascending: false)
        .order('first_name');
    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row);
      return RosterPlayer(
        id: map['id'].toString(),
        firstName: (map['first_name'] ?? '').toString(),
        lastName: (map['last_name'] ?? '').toString(),
        isGoalkeeper: map['is_goalkeeper'] == true,
        isActive: map['is_active'] != false,
      );
    }).toList();
  }

  Future<void> addPlayer({
    required String seasonId,
    required String firstName,
    required String lastName,
    required bool isGoalkeeper,
  }) async {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty || l.isEmpty) {
      throw ArgumentError('Le prénom et le nom sont obligatoires.');
    }
    await _client.from('season_players').insert({
      'season_id': seasonId,
      'first_name': f,
      'last_name': l,
      'is_goalkeeper': isGoalkeeper,
      'is_active': true,
    });
  }

  Future<void> updatePlayer({
    required String id,
    required String firstName,
    required String lastName,
    required bool isGoalkeeper,
  }) async {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty || l.isEmpty) {
      throw ArgumentError('Le prénom et le nom sont obligatoires.');
    }
    await _client.from('season_players').update({
      'first_name': f,
      'last_name': l,
      'is_goalkeeper': isGoalkeeper,
    }).eq('id', id);
  }

  Future<void> setActive({required String id, required bool active}) async {
    await _client
        .from('season_players')
        .update({'is_active': active}).eq('id', id);
  }

  /// Supprime définitivement un joueur de l'effectif. Ses buts, clean sheets et
  /// les pronostics de saison le concernant sont supprimés en cascade.
  Future<void> deletePlayer(String id) async {
    await _client.from('season_players').delete().eq('id', id);
  }
}

final rosterRepositoryProvider = Provider<RosterRepository>((ref) {
  return RosterRepository(ref.watch(supabaseClientProvider));
});

final openSeasonIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(rosterRepositoryProvider).openSeasonId();
});

final rosterProvider =
    FutureProvider.family<List<RosterPlayer>, String>((ref, seasonId) {
  return ref.watch(rosterRepositoryProvider).fetchRoster(seasonId);
});
