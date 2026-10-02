import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_squad_editing.dart';

/// Repositionne les joueurs déjà présents sur le terrain selon [formationCode].
///
/// Le changement de dispositif n'est jamais un remplacement : aucune frontière
/// terrain/banc n'est franchie. C'est exactement la règle de l'éditeur de
/// composition : chaque joueur rejoint le poste le plus proche de sa place,
/// le gardien reste au but.
MatchComposition repositionLiveLineupForFormation(
  MatchComposition lineup,
  String formationCode,
) =>
    repositionForFormation(lineup, formationCode);
