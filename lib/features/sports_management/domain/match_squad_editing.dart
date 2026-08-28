import 'dart:ui' show Offset;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Règles de manipulation d'un effectif sur le terrain et le banc.
///
/// Le Tableau Blanc (avant le coup d'envoi) et le compte rendu d'après-match
/// partagent exactement ces fonctions : un glisser-déposer se comporte donc de
/// la même façon des deux côtés. Elles sont pures — elles ne parlent jamais au
/// serveur — pour être testables et réutilisables telles quelles.

/// Nombre maximal de titulaires sur le terrain.
const int kMaxStarters = 11;

/// Distance en dessous de laquelle deux positions désignent le même poste.
const double _slotProximity = .12;

/// Place [moving] sur [slot].
///
/// Si un joueur occupait déjà ce poste, les deux échangent leurs places quand
/// le joueur déplacé venait du terrain, sinon l'occupant repart sur le banc.
MatchComposition placeEntryOnSlot(
  MatchComposition lineup,
  MatchCompositionEntry moving,
  FootballFormationSlot slot,
) {
  final currentAtSlot = lineup.entries
      .where((entry) => entry.zone == MatchCompositionZone.field)
      .where((entry) => entry.participantId != moving.participantId)
      .cast<MatchCompositionEntry?>()
      .firstWhere(
        (entry) =>
            entry != null &&
            (Offset(entry.x ?? .5, entry.y ?? .5) - slot.position).distance <
                _slotProximity,
        orElse: () => null,
      );
  final oldPosition = moving.zone == MatchCompositionZone.field
      ? Offset(moving.x ?? .5, moving.y ?? .5)
      : null;

  return lineup.copyWith(
    entries: [
      for (final entry in lineup.entries)
        if (entry.participantId == moving.participantId)
          entry.moveTo(
            MatchCompositionZone.field,
            x: slot.position.dx,
            y: slot.position.dy,
          )
        else if (currentAtSlot != null &&
            entry.participantId == currentAtSlot.participantId)
          oldPosition == null
              ? entry.moveTo(
                  MatchCompositionZone.bench,
                  sortOrder: _nextBenchOrder(lineup),
                )
              : entry.moveTo(
                  MatchCompositionZone.field,
                  x: oldPosition.dx,
                  y: oldPosition.dy,
                )
        else
          entry,
    ],
  );
}

/// Renvoie [moving] sur le banc. Le joueur reste dans le compte rendu, comme
/// remplaçant.
MatchComposition moveEntryToBench(
  MatchComposition lineup,
  MatchCompositionEntry moving,
) {
  if (moving.zone == MatchCompositionZone.bench) return lineup;
  final benchOrder = _nextBenchOrder(lineup);
  return lineup.copyWith(
    entries: [
      for (final entry in lineup.entries)
        if (entry.participantId == moving.participantId)
          entry.moveTo(MatchCompositionZone.bench, sortOrder: benchOrder)
        else
          entry,
    ],
  );
}

/// Retire [moving] du match. Il ne fait plus partie du compte rendu final.
MatchComposition removeEntryFromSquad(
  MatchComposition lineup,
  MatchCompositionEntry moving,
) {
  return lineup.copyWith(
    entries: [
      for (final entry in lineup.entries)
        if (entry.participantId == moving.participantId)
          entry.moveTo(MatchCompositionZone.notSelected)
        else
          entry,
    ],
  );
}

/// Remet dans l'effectif, sur le banc, un joueur qui en avait été retiré.
MatchComposition restoreEntryToSquad(
  MatchComposition lineup,
  String participantId,
) {
  final benchOrder = _nextBenchOrder(lineup);
  return lineup.copyWith(
    entries: [
      for (final entry in lineup.entries)
        if (entry.participantId == participantId &&
            entry.zone != MatchCompositionZone.field)
          entry.moveTo(MatchCompositionZone.bench, sortOrder: benchOrder)
        else
          entry,
    ],
  );
}

/// Vrai si le terrain est déjà complet et que [moving] n'y est pas encore.
bool wouldExceedStarterLimit(
  MatchComposition lineup,
  MatchCompositionEntry moving,
) {
  if (moving.zone == MatchCompositionZone.field) return false;
  return lineup.entriesFor(MatchCompositionZone.field).length >= kMaxStarters;
}

/// Tous les joueurs de l'effectif : terrain d'abord, puis banc.
///
/// C'est la liste dans laquelle on choisit un buteur ou un passeur : un joueur
/// retiré du match n'y figure plus.
List<MatchCompositionEntry> squadEntries(MatchComposition lineup) => [
      ...lineup.entriesFor(MatchCompositionZone.field),
      ...lineup.entriesFor(MatchCompositionZone.bench),
    ];

/// Participants retirés du match, proposés à la réintégration.
List<MatchCompositionEntry> removedEntries(MatchComposition lineup) => [
      ...lineup.entriesFor(MatchCompositionZone.notSelected),
      ...lineup.entriesFor(MatchCompositionZone.available),
    ];

/// Replace les titulaires selon [formationCode] sans franchir la frontière
/// terrain/banc : changer de dispositif n'est jamais un remplacement.
///
/// Quand le terrain contient plus de joueurs que le dispositif n'a de postes,
/// le changement est refusé plutôt que d'éjecter quelqu'un en silence.
MatchComposition repositionForFormation(
  MatchComposition lineup,
  String formationCode,
) {
  final formation = formationForCode(formationCode);
  final slots = formation.slots;
  final field = lineup.entriesFor(MatchCompositionZone.field);
  final ordered = [
    ...field.where((entry) => entry.isGoalkeeper),
    ...field.where((entry) => !entry.isGoalkeeper),
  ];

  if (ordered.length > slots.length) {
    throw StateError(
      'Le dispositif ${formation.code} ne peut pas contenir '
      '${ordered.length} joueurs sur le terrain.',
    );
  }

  final positionByParticipant = <String, FootballFormationSlot>{
    for (var index = 0; index < ordered.length; index += 1)
      ordered[index].participantId: slots[index],
  };

  return lineup.copyWith(
    formationCode: formation.code,
    entries: [
      for (final entry in lineup.entries)
        if (positionByParticipant[entry.participantId] case final slot?)
          entry.moveTo(
            MatchCompositionZone.field,
            x: slot.position.dx,
            y: slot.position.dy,
          )
        else
          entry,
    ],
  );
}

int _nextBenchOrder(MatchComposition lineup) {
  final orders = lineup.entries
      .where((entry) => entry.zone == MatchCompositionZone.bench)
      .map((entry) => entry.sortOrder);
  return orders.isEmpty ? 0 : orders.reduce((a, b) => a > b ? a : b) + 1;
}
