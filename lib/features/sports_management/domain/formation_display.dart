import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/formation_assignment.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Écart maximal accepté entre un joueur et le poste qui lui est attribué
/// quand ses coordonnées viennent déjà de la grille de l'application.
const double _sameGridTolerance = .12;

/// Écart maximal accepté après mise à l'échelle d'une équipe complète.
///
/// Les archives importées dessinent leurs dispositifs à leur façon (milieux
/// défensifs d'un 4-2-3-1 plus écartés, par exemple) : jusqu'à 0,17 d'écart
/// sur les 189 matchs archivés, sans qu'aucun joueur ne change de ligne.
/// Au-delà, la composition ne ressemble plus à son dispositif et on la
/// laisse telle quelle.
const double _rescaledTolerance = .2;

/// Replace, pour l'affichage seulement, les titulaires d'une composition
/// enregistrée sur les emplacements actuels de son dispositif.
///
/// Une composition garde les coordonnées exactes de chaque joueur, telles
/// qu'elles étaient au moment où elle a été faite (ou importée des
/// archives). Sans cette étape, une amélioration des emplacements d'un
/// dispositif ne profiterait jamais aux matchs déjà joués. Les données
/// enregistrées ne sont jamais modifiées : seul le dessin change.
///
/// Chaque joueur rejoint le poste le plus proche (voir
/// [assignFieldPlayersToSlots]). Une équipe complète est d'abord mise à
/// l'échelle du dispositif, pour que des coordonnées dessinées autrement
/// (attaquants collés au bord, par exemple) retrouvent leur ligne.
///
/// La liste est rendue telle quelle quand le dispositif est inconnu, qu'un
/// joueur n'a pas de position, ou que la composition s'éloigne trop de son
/// dispositif : on préfère l'ancien dessin à un placement inventé.
List<MatchCompositionEntry> alignFieldToFormation(
  String? formationCode,
  List<MatchCompositionEntry> field,
) {
  final formation = formationForCodeOrNull(formationCode);
  if (formation == null || field.isEmpty) return field;
  final slots = formation.slots;
  if (field.length > slots.length) return field;
  if (field.any((entry) => entry.x == null || entry.y == null)) return field;

  final complete = field.length == slots.length;
  final positioned =
      complete ? _rescaledToFormation(field, slots) : List.of(field);
  final assigned = assignFieldPlayersToSlots(positioned, slots);
  if (assigned.length != field.length) return field;

  final tolerance = complete ? _rescaledTolerance : _sameGridTolerance;
  for (final entry in positioned) {
    final slot = assigned[entry.participantId]!;
    final position = Offset(entry.x!, entry.y!);
    if ((position - slot.position).distance > tolerance) return field;
  }

  return [
    for (final entry in field)
      entry.moveTo(
        MatchCompositionZone.field,
        x: assigned[entry.participantId]!.position.dx,
        y: assigned[entry.participantId]!.position.dy,
        sortOrder: entry.sortOrder,
      ),
  ];
}

/// Étire les joueurs de champ pour qu'ils occupent la même surface que les
/// postes de champ du dispositif. Le gardien n'est pas déplacé : il rejoint
/// le but quoi qu'il arrive.
List<MatchCompositionEntry> _rescaledToFormation(
  List<MatchCompositionEntry> field,
  List<FootballFormationSlot> slots,
) {
  final outfield = [
    for (final entry in field)
      if (!entry.isGoalkeeper) Offset(entry.x!, entry.y!),
  ];
  final targets = [
    for (final slot in slots)
      if (slot.label != 'GB') slot.position,
  ];
  if (outfield.isEmpty || targets.isEmpty) return List.of(field);

  final from = _bounds(outfield);
  final to = _bounds(targets);

  double scale(
      double value, double min, double max, double toMin, double toMax) {
    if (max - min < 1e-6) return (toMin + toMax) / 2;
    return toMin + (value - min) / (max - min) * (toMax - toMin);
  }

  return [
    for (final entry in field)
      if (entry.isGoalkeeper)
        entry
      else
        entry.moveTo(
          MatchCompositionZone.field,
          x: scale(entry.x!, from.left, from.right, to.left, to.right),
          y: scale(entry.y!, from.top, from.bottom, to.top, to.bottom),
          sortOrder: entry.sortOrder,
        ),
  ];
}

({double left, double right, double top, double bottom}) _bounds(
  List<Offset> points,
) {
  return (
    left: points.map((point) => point.dx).reduce(math.min),
    right: points.map((point) => point.dx).reduce(math.max),
    top: points.map((point) => point.dy).reduce(math.min),
    bottom: points.map((point) => point.dy).reduce(math.max),
  );
}
