import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppPreferences {
  const AppPreferences({
    this.predictionNotifications = true,
    this.motmVoteNotifications = true,
    this.convocationNotifications = true,
    this.compositionNotifications = true,
  });

  /// Prévenir à J−5 lorsqu'un pronostic n'est pas encore rempli.
  final bool predictionNotifications;

  /// Prévenir à l'ouverture du vote Homme du match et à son résultat.
  final bool motmVoteNotifications;

  /// Prévenir lorsqu'un joueur passe de la liste d'attente aux convoqués.
  final bool convocationNotifications;

  /// Prévenir à la mise en ligne de la composition d'un match.
  final bool compositionNotifications;

  AppPreferences copyWith({
    bool? predictionNotifications,
    bool? motmVoteNotifications,
    bool? convocationNotifications,
    bool? compositionNotifications,
  }) {
    return AppPreferences(
      predictionNotifications:
          predictionNotifications ?? this.predictionNotifications,
      motmVoteNotifications:
          motmVoteNotifications ?? this.motmVoteNotifications,
      convocationNotifications:
          convocationNotifications ?? this.convocationNotifications,
      compositionNotifications:
          compositionNotifications ?? this.compositionNotifications,
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
      predictionNotifications: row['notify_prediction_reminders'] != false,
      motmVoteNotifications: row['notify_motm_vote'] != false,
      convocationNotifications: row['notify_convocation'] != false,
      compositionNotifications: row['notify_composition'] != false,
    );
  }

  Future<void> update(AppPreferences preferences) async {
    final result = await _client.rpc(
      'update_my_notification_preferences',
      params: {
        'p_notify_prediction': preferences.predictionNotifications,
        'p_notify_motm_vote': preferences.motmVoteNotifications,
        'p_notify_convocation': preferences.convocationNotifications,
        'p_notify_composition': preferences.compositionNotifications,
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

final appPreferencesProvider =
    FutureProvider.autoDispose<AppPreferences>((ref) {
  return ref.watch(preferencesRepositoryProvider).fetch();
});
