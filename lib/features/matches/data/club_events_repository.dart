import 'dart:convert';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClubEventsRepository {
  ClubEventsRepository(this._client);

  final SupabaseClient _client;
  Future<List<ClubEvent>>? _fetchInFlight;
  List<ClubEvent>? _cache;
  DateTime? _cacheAt;
  int _cacheGeneration = 0;

  static const _cacheTtl = Duration(minutes: 2);
  static const _persistentKey = 'club_events_v1';

  Future<List<ClubEvent>> fetchEvents({bool forceRefresh = false}) {
    final cached = _cache;
    final cachedAt = _cacheAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return Future.value(cached);
    }

    final existing = _fetchInFlight;
    if (!forceRefresh && existing != null) return existing;

    final generation = _cacheGeneration;
    final request = _fetchEventsFromServer(generation);
    _fetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_fetchInFlight, request)) _fetchInFlight = null;
    });
  }

  Stream<List<ClubEvent>> watchEventsLocalFirst() async* {
    final local = await _readPersistent();
    if (local != null) {
      _cache = local;
      _cacheAt = DateTime.now();
      yield local;
    }

    try {
      final fresh = await fetchEvents(forceRefresh: true);
      yield fresh;
    } catch (_) {
      if (local == null) rethrow;
    }
  }

  Future<List<ClubEvent>> _fetchEventsFromServer(int generation) async {
    final response = await _client
        .from('club_events')
        .select('id, season_id, title, starts_at, location, created_by')
        .order('starts_at', ascending: false);
    final events = (response as List)
        .map((row) => ClubEvent.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);

    // Une lecture commencée avant une création/modification/suppression ne doit
    // jamais réécrire un ancien snapshot dans le cache après la mutation.
    if (generation == _cacheGeneration) {
      _cache = events;
      _cacheAt = DateTime.now();
      await _writePersistent(events);
    }
    return events;
  }

  Future<List<ClubEvent>?> _readPersistent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistentKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(ClubEvent.fromJson)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePersistent(List<ClubEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _persistentKey,
        jsonEncode(
          events
              .map(
                (event) => {
                  'id': event.id,
                  'season_id': event.seasonId,
                  'title': event.title,
                  'starts_at': event.startsAt.toUtc().toIso8601String(),
                  'location': event.location,
                  'created_by': event.createdBy,
                },
              )
              .toList(growable: false),
        ),
      );
    } catch (_) {
      // Le stockage local est une optimisation : Supabase reste la source.
    }
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
    await _invalidateCache();
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
    await _invalidateCache();
  }

  Future<void> deleteEvent(String id) async {
    await _client.from('club_events').delete().eq('id', id);
    await _invalidateCache();
  }

  Future<void> _invalidateCache() async {
    _cacheGeneration += 1;
    _fetchInFlight = null;
    _cache = null;
    _cacheAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistentKey);
    } catch (_) {
      // Le stockage local est une optimisation : l'invalidation mémoire suffit
      // pour continuer à fonctionner si SharedPreferences est indisponible.
    }
  }
}

final clubEventsRepositoryProvider = Provider<ClubEventsRepository>((ref) {
  return ClubEventsRepository(ref.watch(supabaseClientProvider));
});

final clubEventsProvider = StreamProvider<List<ClubEvent>>((ref) {
  return ref.watch(clubEventsRepositoryProvider).watchEventsLocalFirst();
});
