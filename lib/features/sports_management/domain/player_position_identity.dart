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
