import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppPreferences {
  const AppPreferences({
    this.predictionOpen = true,
    this.predictionReminders = true,
    this.matchReminders = true,
  });

  /// Prévenir quand un pronostic est ouvert (nouveau match).
  final bool predictionOpen;

  /// Prévenir 2 h avant le match si le pronostic n'est pas rempli.
  final bool predictionReminders;

  /// Prévenir quand le match est fini (points + pronostics des autres).
  final bool matchReminders;

  AppPreferences copyWith({
    bool? predictionOpen,
    bool? predictionReminders,
    bool? matchReminders,
  }) {
    return AppPreferences(
      predictionOpen: predictionOpen ?? this.predictionOpen,
      predictionReminders: predictionReminders ?? this.predictionReminders,
      matchReminders: matchReminders ?? this.matchReminders,
    );
  }
}

class PreferencesRepository {
  PreferencesRepository(this._client);

  final SupabaseClient _client;

  Future<AppPreferences> fetch() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Utilisateur non authentifié.');
    }

    final response = await _client.rpc('get_my_profile');
    if (response is! Map) return const AppPreferences();
    final row = Map<String, dynamic>.from(response);

    return AppPreferences(
      predictionOpen: row['notify_prediction_open'] != false,
      predictionReminders: row['notify_prediction_reminders'] != false,
      matchReminders: row['notify_match_reminders'] != false,
    );
  }

  Future<void> update(AppPreferences preferences) async {
    final result = await _client.rpc(
      'update_my_app_preferences',
      params: {
        'p_notify_prediction_open': preferences.predictionOpen,
        'p_notify_prediction_reminders': preferences.predictionReminders,
        'p_notify_match_reminders': preferences.matchReminders,
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