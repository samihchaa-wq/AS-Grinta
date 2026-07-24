import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signal interne utilisé quand l'utilisateur sélectionne l'onglet Matchs.
///
/// Il évite de modifier l'URL et donc de reconstruire la route uniquement pour
/// recentrer la liste sur le prochain match.
final matchesFocusRequestProvider = StateProvider<int>((ref) => 0);
