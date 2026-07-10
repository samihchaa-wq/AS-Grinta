import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/preferences/data/preferences_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.date,
    required this.kind,
  });

  final String id;
  final String title;
  final String message;
  final DateTime date;
  final String kind;
}

class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotificationItem>> fetch(AppPreferences preferences) async {
    final rows = await _client
        .from('matches')
        .select('id,match_date,match_time,location,status,opponents(name)')
        .inFilter('status', const ['a_venir', 'en_cours'])
        .order('match_date')
        .order('match_time')
        .limit(8);

    final notifications = <AppNotificationItem>[];
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final matchId = row['id'].toString();
      final opponentMap = row['opponents'];
      final opponent = opponentMap is Map
          ? (opponentMap['name'] ?? 'Adversaire').toString()
          : 'Adversaire';
      final date = DateTime.tryParse('${row['match_date']}T${row['match_time']}') ??
          DateTime.tryParse('${row['match_date']}') ??
          DateTime.now();
      final home = row['location'] == 'domicile';
      final status = row['status']?.toString();

      if (preferences.matchReminders) {
        notifications.add(
          AppNotificationItem(
            id: 'match-$matchId',
            title: status == 'en_cours' ? 'Match en cours' : 'Prochain match',
            message: home
                ? 'AS Grinta reçoit $opponent.'
                : 'AS Grinta se déplace chez $opponent.',
            date: date,
            kind: status == 'en_cours' ? 'live' : 'match',
          ),
        );
      }

      if (preferences.predictionReminders && status == 'a_venir') {
        notifications.add(
          AppNotificationItem(
            id: 'prediction-$matchId',
            title: 'Pronostic à vérifier',
            message: 'Pense à valider ton pronostic pour le match contre $opponent.',
            date: date.subtract(const Duration(hours: 2)),
            kind: 'prediction',
          ),
        );
      }
    }

    notifications.sort((a, b) => a.date.compareTo(b.date));
    return notifications;
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});

final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotificationItem>>((ref) async {
  final preferences = await ref.watch(appPreferencesProvider.future);
  return ref.watch(notificationsRepositoryProvider).fetch(preferences);
});
