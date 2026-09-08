import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_identity.dart';
import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _displayNamesKey = '__display_names_by_player_id';

class PlayerIdentityResolution {
  const PlayerIdentityResolution({
    required this.identitiesByName,
    required this.displayNamesByPlayerId,
  });

  static const empty = PlayerIdentityResolution(
    identitiesByName: <String, String>{},
    displayNamesByPlayerId: <String, String>{},
  );

  final Map<String, String> identitiesByName;
  final Map<String, String> displayNamesByPlayerId;
}

/// Résout les joueurs de l'archive vers leur identité canonique actuelle.
abstract interface class PlayerIdentityRepository {
  /// Une seule résolution serveur fournit à la fois :
  /// - nom d'archive normalisé -> `players.id` canonique ;
  /// - `players.id` -> libellé réellement affiché aujourd'hui.
  ///
  /// Le second bloc est optionnel côté serveur pour rester compatible avec une
  /// base qui n'aurait pas encore reçu la migration associée.
  Future<PlayerIdentityResolution> resolvePlayerPositionIdentities(
    List<String> names,
  );
}

class SupabasePlayerIdentityRepository implements PlayerIdentityRepository {
  SupabasePlayerIdentityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PlayerIdentityResolution> resolvePlayerPositionIdentities(
    List<String> names,
  ) async {
    final wanted = names
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (wanted.isEmpty) return PlayerIdentityResolution.empty;

    final response = await _client.rpc(
      'resolve_player_identities',
      params: {'p_names': wanted},
    );
    if (response is! Map) return PlayerIdentityResolution.empty;

    final json = Map<String, dynamic>.from(response);
    final rawDisplayNames = json.remove(_displayNamesKey);

    final identities = <String, String>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is! String) continue;
      final playerId = value.trim();
      if (playerId.isNotEmpty) identities[entry.key] = playerId;
    }

    final displayNames = <String, String>{};
    if (rawDisplayNames is Map) {
      for (final entry in Map<String, dynamic>.from(rawDisplayNames).entries) {
        final displayName = entry.value?.toString().trim();
        if (displayName != null && displayName.isNotEmpty) {
          displayNames[entry.key] = displayName;
        }
      }
    }

    return PlayerIdentityResolution(
      identitiesByName: identities,
      displayNamesByPlayerId: displayNames,
    );
  }
}

final playerIdentityRepositoryProvider = Provider<PlayerIdentityRepository>(
  (ref) => SupabasePlayerIdentityRepository(ref.watch(supabaseClientProvider)),
);

/// L'archive des postes, réancrée sur les identités canoniques d'aujourd'hui
/// et libellée comme l'effectif courant.
///
/// La résolution reste un seul aller-retour réseau, comme avant ce correctif :
/// elle ne rajoute donc aucune dépendance asynchrone aux autres écrans qui
/// utilisent les profils de poste.
///
/// Le serveur continue aussi d'accepter les anciens clients : si le bloc de
/// libellés courants n'est pas présent, on garde simplement les noms d'archive.
final playerPositionArchiveProvider =
    FutureProvider<Map<String, PlayerPositionProfile>>((ref) async {
  try {
    final resolution = await ref
        .watch(playerIdentityRepositoryProvider)
        .resolvePlayerPositionIdentities([
      for (final profile in kPlayerPositionProfiles.values)
        if (profile.displayName.isNotEmpty) profile.displayName,
    ]);

    final profiles = realignPlayerPositionProfiles(
      identitiesByName: resolution.identitiesByName,
    );
    return relabelPlayerPositionProfilesForDisplay(
      profiles: profiles,
      displayNamesByPlayerId: resolution.displayNamesByPlayerId,
    );
  } catch (_) {
    return kPlayerPositionProfiles;
  }
});
