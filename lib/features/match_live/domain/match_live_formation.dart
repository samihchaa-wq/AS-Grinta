import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Repositionne les joueurs déjà présents sur le terrain selon [formationCode].
///
/// Le changement de dispositif n'est jamais un remplacement : aucune frontière
/// terrain/banc n'est franchie. Comme dans l'éditeur de composition, le gardien
/// est placé en premier puis les joueurs de champ conservent leur ordre courant.
MatchComposition repositionLiveLineupForFormation(
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
