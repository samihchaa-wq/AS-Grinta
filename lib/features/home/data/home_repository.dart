import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider de compatibilité temporaire pour les invalidations historiques.
///
/// Il ne déclenche plus aucune requête : l'ancien tableau de bord Accueil a été
/// supprimé et son contenu vit désormais dans les modules Matchs et Stats.
@Deprecated('Supprimer les invalidations restantes de homeDashboardProvider.')
final homeDashboardProvider = Provider<void>((ref) {});
