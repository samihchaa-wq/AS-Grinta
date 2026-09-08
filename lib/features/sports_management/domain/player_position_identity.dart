import 'package:as_grinta/features/sports_management/domain/player_position_profiles.dart';

/// Normalise un nom de joueur comme le fait la base.
///
/// Même règle que `private.normalize_player_name` : minuscules et espaces
/// resserrés, sans toucher aux accents. Les deux orthographes d'un même nom
/// cohabitent de toute façon comme deux alias de la même identité.
String normalizePlayerName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Réancre les profils de postes sur les identités canoniques d'aujourd'hui.
///
/// Le fichier d'archive est rangé par `players.id`, mais cette clé ne survit
/// pas à une fusion d'identités : la fusion déplace l'historique sur
/// l'identité gagnante puis supprime la perdante, et le profil se retrouve
/// rangé sous une identité qui n'existe plus. Le joueur perd alors son poste
/// de référence sans que rien ne le signale.
///
/// Le nom, lui, survit : la fusion recolle les alias de l'identité perdante
/// sur la gagnante. [identitiesByName] est cette résolution, relevée en base
/// et indexée par nom normalisé. Un profil dont le nom n'y figure pas garde sa
/// clé d'origine : à défaut de mieux, le relevé figé reste la meilleure
/// approximation.
Map<String, PlayerPositionProfile> realignPlayerPositionProfiles({
  required Map<String, String> identitiesByName,
  Map<String, PlayerPositionProfile> archive = kPlayerPositionProfiles,
}) {
  if (identitiesByName.isEmpty) return archive;

  final realigned = <String, PlayerPositionProfile>{};
  var moved = false;
  for (final entry in archive.entries) {
    final name = normalizePlayerName(entry.value.displayName);
    final live = name.isEmpty ? null : identitiesByName[name];
    final key = live ?? entry.key;
    if (key != entry.key) moved = true;

    // Deux profils d'archive peuvent atterrir sur la même identité si les
    // personnes ont été fusionnées depuis. On garde alors le plus fourni,
    // plutôt que de laisser l'ordre du fichier décider.
    final existing = realigned[key];
    if (existing == null || existing.appearances < entry.value.appearances) {
      realigned[key] = entry.value;
    }
  }
  return moved ? realigned : archive;
}

/// Donne aux profils leur libellé réellement affiché aujourd'hui.
///
/// Les compositions « entre nous » affichent le surnom quand il existe,
/// sinon le prénom. Leur regroupement papier indexe ensuite les profils par ce
/// libellé. Sans ce raccord, un profil archivé sous « Luka Brunel » ne peut
/// pas être retrouvé quand la composition affiche « Lulu ».
///
/// L'identité canonique reste la seule clé de rapprochement :
/// [displayNamesByPlayerId] est indexé par `players.id`. En cas de doublon de
/// libellé visible, on conserve volontairement les noms d'archive afin de ne
/// jamais attribuer le profil d'un homonyme à l'autre. Le comptage porte sur
/// tous les joueurs visibles, même ceux qui n'ont pas encore de profil de
/// poste : un homonyme sans historique ne doit jamais hériter de celui d'un
/// autre joueur.
Map<String, PlayerPositionProfile> relabelPlayerPositionProfilesForDisplay({
  required Map<String, PlayerPositionProfile> profiles,
  required Map<String, String> displayNamesByPlayerId,
}) {
  if (profiles.isEmpty || displayNamesByPlayerId.isEmpty) return profiles;

  final displayNameCounts = <String, int>{};
  for (final entry in displayNamesByPlayerId.entries) {
    final normalized = normalizePlayerName(entry.value);
    if (normalized.isEmpty) continue;
    displayNameCounts.update(
      normalized,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  var changed = false;
  final relabelled = <String, PlayerPositionProfile>{};
  for (final entry in profiles.entries) {
    final requested = displayNamesByPlayerId[entry.key]?.trim();
    final normalized = requested == null ? '' : normalizePlayerName(requested);
    if (requested == null ||
        requested.isEmpty ||
        displayNameCounts[normalized] != 1 ||
        requested == entry.value.displayName) {
      relabelled[entry.key] = entry.value;
      continue;
    }

    changed = true;
    relabelled[entry.key] = PlayerPositionProfile(
      displayName: requested,
      appearances: entry.value.appearances,
      samples: entry.value.samples,
      totalWeight: entry.value.totalWeight,
    );
  }

  return changed ? relabelled : profiles;
}
