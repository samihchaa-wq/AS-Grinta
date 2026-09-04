import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_identity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Résout un nom de joueur de l'archive vers l'identité canonique qui porte
/// aujourd'hui son histoire.
abstract interface class PlayerIdentityRepository {
  /// Renvoie les identités trouvées, indexées par nom normalisé. Un nom
  /// ambigu ou inconnu est simplement absent de la réponse.
  Future<Map<String, String>> resolveIdentitiesByName(List<String> names);
}

class SupabasePlayerIdentityRepository implements PlayerIdentityRepository {
  SupabasePlayerIdentityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, String>> resolveIdentitiesByName(
    List<String> names,
  ) async {
    final wanted = names
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (wanted.isEmpty) return const {};

    final response = await _client.rpc(
      'resolve_player_identities',
      params: {'p_names': wanted},
    );
    if (response is! Map) return const {};

    return {
      for (final entry in Map<String, dynamic>.from(response).entries)
        if (entry.value?.toString().trim() case final playerId?)
          if (playerId.isNotEmpty) entry.key: playerId,
    };
  }
}

final playerIdentityRepositoryProvider = Provider<PlayerIdentityRepository>(
  (ref) => SupabasePlayerIdentityRepository(ref.watch(supabaseClientProvider)),
);

/// L'archive des postes, réancrée sur les identités canoniques d'aujourd'hui.
///
/// Sans ce réancrage, une fusion d'identités suffit à faire disparaître le
/// poste de référence d'un joueur : sa clé dans le fichier généré pointe alors
/// sur une fiche supprimée. On repasse donc par le nom, qui survit à la
/// fusion.
///
/// Le relevé figé du fichier reste le repli : si la base ne répond pas, mieux
/// vaut des postes un peu datés que pas de postes du tout.
final playerPositionArchiveProvider =
    FutureProvider<Map<String, PlayerPositionProfile>>((ref) async {
  try {
    final identities = await ref
        .watch(playerIdentityRepositoryProvider)
        .resolveIdentitiesByName([
      for (final profile in kPlayerPositionProfiles.values)
        if (profile.displayName.isNotEmpty) profile.displayName,
    ]);
    return realignPlayerPositionProfiles(identitiesByName: identities);
  } catch (_) {
    return kPlayerPositionProfiles;
  }
});
