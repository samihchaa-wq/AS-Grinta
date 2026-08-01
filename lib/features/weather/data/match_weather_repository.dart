import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/weather/domain/match_weather.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class MatchWeatherRepository {
  Stream<MatchWeather?> watchMatchWeather(String matchId);
}

class SupabaseMatchWeatherRepository implements MatchWeatherRepository {
  const SupabaseMatchWeatherRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<MatchWeather?> watchMatchWeather(String matchId) {
    return _client
        .from('match_weather')
        .stream(primaryKey: ['match_id'])
        .eq('match_id', matchId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return MatchWeather.fromJson(Map<String, dynamic>.from(rows.first));
        });
  }
}

final matchWeatherRepositoryProvider = Provider<MatchWeatherRepository>((ref) {
  return SupabaseMatchWeatherRepository(ref.watch(supabaseClientProvider));
});

final matchWeatherProvider =
    StreamProvider.autoDispose.family<MatchWeather?, String>((ref, matchId) {
  return ref.watch(matchWeatherRepositoryProvider).watchMatchWeather(matchId);
});
