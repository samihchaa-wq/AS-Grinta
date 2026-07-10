import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeDashboardData {
  const HomeDashboardData({
    required this.nextMatchId,
    required this.nextOpponent,
    required this.nextKickoffAt,
    required this.pendingPredictions,
  });

  final String? nextMatchId;
  final String? nextOpponent;
  final DateTime? nextKickoffAt;
  final int pendingPredictions;
}

class HomeRepository {
  HomeRepository(this._client);

  final SupabaseClient _client;

  Future<HomeDashboardData> fetchDashboard() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final matches = await _client
        .from('matches')
        .select('id, match_date, match_time, opponents(name)')
        .eq('status', 'a_venir')
        .order('match_date', ascending: true)
        .order('match_time', ascending: true);

    final predictions = await _client
        .from('match_predictions')
        .select('match_id, is_filled')
        .eq('profile_id', userId);
    final filledByMatch = <String, bool>{};
    for (final row in predictions as List) {
      final map = Map<String, dynamic>.from(row);
      filledByMatch[map['match_id'].toString()] = map['is_filled'] == true;
    }

    String? nextMatchId;
    String? nextOpponent;
    DateTime? nextKickoffAt;
    var pendingPredictions = 0;
    final now = DateTime.now();

    for (final row in matches as List) {
      final map = Map<String, dynamic>.from(row);
      final id = map['id'].toString();
      final date = map['match_date']?.toString() ?? '';
      final time = map['match_time']?.toString() ?? '00:00:00';
      final kickoff = DateTime.tryParse('${date}T$time');
      final opponent = map['opponents'] is Map
          ? Map<String, dynamic>.from(map['opponents'] as Map)
          : const <String, dynamic>{};

      if (nextMatchId == null) {
        nextMatchId = id;
        nextOpponent = opponent['name']?.toString() ?? 'Adversaire';
        nextKickoffAt = kickoff;
      }

      if (kickoff != null &&
          now.isBefore(kickoff.subtract(const Duration(minutes: 5))) &&
          filledByMatch[id] != true) {
        pendingPredictions++;
      }
    }

    return HomeDashboardData(
      nextMatchId: nextMatchId,
      nextOpponent: nextOpponent,
      nextKickoffAt: nextKickoffAt,
      pendingPredictions: pendingPredictions,
    );
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(supabaseClientProvider));
});

final homeDashboardProvider = FutureProvider<HomeDashboardData>((ref) {
  return ref.watch(homeRepositoryProvider).fetchDashboard();
});
