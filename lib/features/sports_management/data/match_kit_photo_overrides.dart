import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Correspondance avec les trois maillots de l'onglet Infos.
/// Les anciens identifiants de match restent stables : blue = Brésil,
/// orange = Pays-Bas. France reprend la photo historique de chaque joueur.
String? kitPhotoColumn(String? jerseyId) =>
    switch (JerseyOption.fromId(jerseyId)) {
      JerseyOption.blue => 'brazil_url',
      JerseyOption.orange => 'netherlands_url',
      _ => null,
    };

/// Pour un match, récupère seulement les portraits alternatifs du maillot
/// sélectionné. Une variante absente conserve la photo France existante.
final matchKitPhotoOverridesProvider =
    FutureProvider.autoDispose.family<Map<String, String>, String>(
  (ref, matchId) async {
    final match = await ref.watch(matchInfoProvider(matchId).future);
    final column = kitPhotoColumn(match.jerseyNote);
    if (column == null) return const <String, String>{};

    final rows = await ref
        .watch(supabaseClientProvider)
        .from('season_player_kit_photos')
        .select('season_player_id,$column');
    return {
      for (final row in rows)
        if (row[column] is String && (row[column] as String).trim().isNotEmpty)
          row['season_player_id'].toString(): (row[column] as String).trim(),
    };
  },
);

/// Applique uniquement à l'affichage : aucun champ de la composition publiée
/// ou de son brouillon n'est enregistré ou réécrit.
List<MatchCompositionEntry> withMatchKitPhotos(
  List<MatchCompositionEntry> entries,
  Map<String, String> photoOverrides,
) {
  if (photoOverrides.isEmpty) return entries;
  return [
    for (final entry in entries)
      if (!entry.isGuest && photoOverrides.containsKey(entry.seasonPlayerId))
        entry.copyWith(photoUrl: photoOverrides[entry.seasonPlayerId])
      else
        entry,
  ];
}

/// Choisit le portrait du coach pour le maillot du match, avec France en
/// repli. Il est identifié par sa fiche de saison, comme les joueurs.
String? coachPhotoForMatchKit({
  required String? seasonPlayerId,
  required String? francePhotoUrl,
  required Map<String, String> photoOverrides,
}) {
  if (seasonPlayerId == null || seasonPlayerId.isEmpty) {
    return francePhotoUrl;
  }
  final alternative = photoOverrides[seasonPlayerId];
  return alternative == null || alternative.trim().isEmpty
      ? francePhotoUrl
      : alternative;
}

/// Both alternate kits for internal matches, keyed by season player ID.
/// A missing variant is intentionally absent so France remains the fallback.
final internalTeamKitPhotosProvider =
    FutureProvider.autoDispose<Map<String, Map<String, String>>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from(
        'season_player_kit_photos',
      )
      .select('season_player_id,brazil_url,netherlands_url');
  return {
    for (final row in rows)
      row['season_player_id'].toString(): {
        for (final column in ['brazil_url', 'netherlands_url'])
          if (row[column] is String &&
              (row[column] as String).trim().isNotEmpty)
            column: (row[column] as String).trim(),
      },
  };
});
