import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Providers partagés de la vue « Prono joueurs » (jauges, verrou, nombre de
/// matchs terminés). La saisie et l'affichage vivent dans
/// `season_prediction_entry_page.dart` et `scorer_dashboard_page.dart`.

final enhancedSeasonLockedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).isLocked();
});

final enhancedSeasonGaugesProvider =
    FutureProvider.autoDispose<List<PlayerGauge>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchGauges();
});

final enhancedSeasonCompletedMatchesProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final season = await client
      .from('seasons')
      .select('id')
      .eq('status', 'open')
      .maybeSingle();
  final seasonId = season?['id']?.toString();
  if (seasonId == null) return 0;

  final rows = await client
      .from('matches')
      .select('id')
      .eq('season_id', seasonId)
      .inFilter('status', const ['termine', 'archive']);
  return (rows as List).length;
});
