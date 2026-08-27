import 'dart:ui';

/// Rapport largeur/hauteur du terrain dessiné par les compositions.
///
/// Les coordonnées des joueurs sont normalisées entre 0 et 1 sur chaque axe,
/// mais le terrain est bien plus haut que large : comparer deux distances
/// sans en tenir compte revient à écraser l'écart vertical et à désigner le
/// mauvais poste. Toutes les distances de ce fichier sont donc ramenées en
/// proportion réelle de l'écran.
const double kPitchAspectRatio = .68;

double _squaredPitchDistance(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  // Un même écart normalisé vaut plus de pixels en hauteur qu'en largeur.
  final dy = (a.dy - b.dy) / kPitchAspectRatio;
  return dx * dx + dy * dy;
}

/// Le poste le plus proche d'un point du terrain, en coordonnées normalisées.
///
/// Renvoie `null` uniquement si la liste des postes est vide.
int? nearestSlotIndex(List<Offset> slotPositions, Offset point) {
  var best = -1;
  var bestDistance = double.infinity;
  for (var index = 0; index < slotPositions.length; index += 1) {
    final distance = _squaredPitchDistance(slotPositions[index], point);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index;
    }
  }
  return best < 0 ? null : best;
}

/// Associe chaque poste du dispositif au joueur qui l'occupe.
///
/// L'ancienne version cherchait, pour chaque poste indépendamment, le joueur
/// le plus proche. Deux postes voisins pouvaient donc désigner **le même**
/// joueur : celui-ci s'affichait deux fois et un autre disparaissait du
/// terrain sans prévenir. Ici chaque joueur n'occupe qu'un poste et chaque
/// poste n'accueille qu'un joueur : on apparie d'abord les couples les plus
/// proches, puis on place d'office les joueurs restants sur les postes encore
/// libres pour que personne ne devienne invisible.
///
/// Renvoie une table `indice de poste` → `indice de joueur`.
Map<int, int> assignEntriesToSlots({
  required List<Offset> slotPositions,
  required List<Offset> entryPositions,
}) {
  final pairs = <({int slot, int entry, double distance})>[];
  for (var slot = 0; slot < slotPositions.length; slot += 1) {
    for (var entry = 0; entry < entryPositions.length; entry += 1) {
      pairs.add((
        slot: slot,
        entry: entry,
        distance: _squaredPitchDistance(
          slotPositions[slot],
          entryPositions[entry],
        ),
      ));
    }
  }
  pairs.sort((a, b) => a.distance.compareTo(b.distance));

  final assignment = <int, int>{};
  final takenEntries = <int>{};
  for (final pair in pairs) {
    if (assignment.containsKey(pair.slot)) continue;
    if (takenEntries.contains(pair.entry)) continue;
    assignment[pair.slot] = pair.entry;
    takenEntries.add(pair.entry);
  }
  return assignment;
}
