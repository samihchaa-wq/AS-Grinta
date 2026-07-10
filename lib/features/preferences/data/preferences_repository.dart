import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppPreferences {
  const AppPreferences({
    required this.matchReminders,
    required this.predictionReminders,
  });

  final bool matchReminders;
  final bool predictionReminders;

  AppPreferences copyWith({
    bool? matchReminders,
    bool? predictionReminders,
  }) {
    return AppPreferences(
      matchReminders: matchReminders ?? this.matchReminders,
      predictionReminders: predictionReminders ?? this.predictionReminders,
    );
  }
}

class PreferencesRepository {
  PreferencesRepository(this._client);

  final SupabaseClient _client;

  Future<AppPreferences> fetch() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Utilisateur non authentifié.');

    final row = await _client
        .from('profiles')
        .select('notify_match_reminders,notify_prediction_reminders')
        .eq('id', userId)
        .single();

    return AppPreferences(
      matchReminders: row['notify_match_reminders'] != false,
      predictionReminders: row['notify_prediction_reminders'] != false,
    );
  }

  Future<void> update(AppPreferences preferences) async {
    final result = await _client.rpc(
      'update_my_app_preferences',
      params: {
        'p_notify_match_reminders': preferences.matchReminders,
        'p_notify_prediction_reminders': preferences.predictionReminders,
      },
    );
    if (result != true) {
      throw StateError('Les préférences n’ont pas pu être enregistrées.');
    }
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  return PreferencesRepository(ref.watch(supabaseClientProvider));
});

final appPreferencesProvider = FutureProvider.autoDispose<AppPreferences>((ref) {
  return ref.watch(preferencesRepositoryProvider).fetch();
});
