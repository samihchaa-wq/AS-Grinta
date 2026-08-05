import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClubEventsRepository {
  ClubEventsRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClubEvent>> fetchEvents() async {
    final response = await _client
        .from('club_events')
        .select('id, season_id, title, starts_at, location, created_by')
        .order('starts_at', ascending: false);
    return (response as List)
        .map((row) => ClubEvent.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> createEvent({
    required String seasonId,
    required String title,
    required DateTime startsAt,
    required String location,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentification requise.');
    await _client.from('club_events').insert({
      'season_id': seasonId,
      'title': title.trim(),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'location': location.trim(),
      'created_by': userId,
    });
  }

  Future<void> updateEvent({
    required String id,
    required String seasonId,
    required String title,
    required DateTime startsAt,
    required String location,
  }) async {
    await _client.from('club_events').update({
      'season_id': seasonId,
      'title': title.trim(),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'location': location.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteEvent(String id) async {
    await _client.from('club_events').delete().eq('id', id);
  }
}

final clubEventsRepositoryProvider = Provider<ClubEventsRepository>((ref) {
  return ClubEventsRepository(ref.watch(supabaseClientProvider));
});

final clubEventsProvider = FutureProvider<List<ClubEvent>>((ref) async {
  return ref.watch(clubEventsRepositoryProvider).fetchEvents();
});
