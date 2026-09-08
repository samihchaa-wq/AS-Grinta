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

  /// Renvoie le libellé actuellement affiché pour chaque identité canonique.
  ///
  /// C'est le surnom du profil lorsqu'il existe, sinon son prénom, puis le
  /// prénom de l'effectif pour les joueurs sans compte actif.
  Future<Map<String, String>> resolveCurrentDisplayNamesByPlayerId();
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

  @override
  Future<Map<String, String>> resolveCurrentDisplayNamesByPlayerId() async {
    final seasonRows = await _client
        .from('season_players')
        .select('player_id, first_name')
        .eq('is_active', true);
    final profileRows = await _client
        .from('profiles')
        .select('player_id, surnom, first_name')
        .eq('status', 'active');

    final displayNames = <String, String>{};
    for (final row in seasonRows) {
      final playerId = _cleanText(row['player_id']);
      final firstName = _cleanText(row['first_name']);
      if (playerId != null && firstName != null) {
        displayNames[playerId] = firstName;
      }
    }
    for (final row in profileRows) {
      final playerId = _cleanText(row['player_id']);
      final displayName =
          _cleanText(row['surnom']) ?? _cleanText(row['first_name']);
      if (playerId != null && displayName != null) {
        displayNames[playerId] = displayName;
      }
    }
    return displayNames;
  }
}

String? _cleanText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

final playerIdentityRepositoryProvider = Provider<PlayerIdentityRepository>(
  (ref) => SupabasePlayerIdentityRepository(ref.watch(supabaseClientProvider)),
);

/// L'archive des postes, réancrée sur les identités canoniques d'aujourd'hui
/// et libellée comme l'effectif courant.
///
/// Sans ce réancrage, une fusion d'identités suffit à faire disparaître le
/// poste de référence d'un joueur : sa clé dans le fichier généré pointe alors
/// sur une fiche supprimée. On repasse donc par le nom, qui survit à la
/// fusion.
///
/// Le libellé courant est ensuite appliqué via l'identité canonique. Ainsi une
/// composition qui affiche « Lulu » retrouve bien le profil archivé de « Luka
/// Brunel », sans dépendre d'une comparaison approximative de noms.
///
/// Si la résolution canonique échoue (par exemple dans un environnement sans
/// Supabase), on rend immédiatement le relevé figé : la lecture optionnelle des
/// libellés courants ne doit jamais retarder le chargement des écrans.
final playerPositionArchiveProvider =
    FutureProvider<Map<String, PlayerPositionProfile>>((ref) async {
  final repository = ref.watch(playerIdentityRepositoryProvider);
  Map<String, PlayerPositionProfile> profiles;

  try {
    final identities = await repository.resolveIdentitiesByName([
      for (final profile in kPlayerPositionProfiles.values)
        if (profile.displayName.isNotEmpty) profile.displayName,
    ]);
    profiles = realignPlayerPositionProfiles(
      identitiesByName: identities,
    );
  } catch (_) {
    return kPlayerPositionProfiles;
  }

  try {
    final displayNames =
        await repository.resolveCurrentDisplayNamesByPlayerId();
    return relabelPlayerPositionProfilesForDisplay(
      profiles: profiles,
      displayNamesByPlayerId: displayNames,
    );
  } catch (_) {
    return profiles;
  }
});
