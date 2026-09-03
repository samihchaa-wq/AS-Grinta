/// Rangs sportifs, convention « competition ranking » : deux ex aequo
/// partagent le meilleur rang, et le suivant reprend a la place reellement
/// occupee.
///
/// Trois joueurs a 100, 100 et 90 points sont classes 1, 1 et 3 — pas 1, 2, 3
/// (qui inventerait un ecart inexistant) ni 1, 1, 2 (qui masquerait le nombre
/// de joueurs devant).
///
/// [sorted] doit deja etre trie dans l'ordre du classement. [rankKey] doit
/// renvoyer la valeur qui fait le classement, et elle seule : y melanger un
/// depart d'egalite, comme le nom, rendrait toute egalite invisible.
///
/// A ne pas utiliser pour une simple position dans une liste — une file
/// d'attente, un ordre alphabetique — ou chaque ligne occupe une place
/// distincte par nature.
List<int> competitionRanks<T>(
  List<T> sorted,
  Object? Function(T item) rankKey,
) {
  final ranks = <int>[];
  Object? previousKey;
  var currentRank = 0;

  for (var index = 0; index < sorted.length; index += 1) {
    final key = rankKey(sorted[index]);
    if (index == 0 || key != previousKey) {
      currentRank = index + 1;
      previousKey = key;
    }
    ranks.add(currentRank);
  }

  return ranks;
}
