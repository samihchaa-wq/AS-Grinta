import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar network loads are coalesced and locally cached', () async {
    final availability = await File(
      'lib/features/sports_management/data/match_availability_repository.dart',
    ).readAsString();
    final availabilityProvider = await File(
      'lib/features/sports_management/presentation/match_availability_provider.dart',
    ).readAsString();
    final history = await File(
      'lib/features/matches/data/calendar_history_repository.dart',
    ).readAsString();
    final events = await File(
      'lib/features/matches/data/club_events_repository.dart',
    ).readAsString();
    final matches = await File(
      'lib/features/matches/presentation/matches_controller.dart',
    ).readAsString();
    final matchesLocalCache = await File(
      'lib/features/matches/data/calendar_matches_local_cache.dart',
    ).readAsString();
    final calendar = await File(
      'lib/features/predictions/presentation/merged_matches_view.dart',
    ).readAsString();
    final pubspec = await File('pubspec.yaml').readAsString();

    expect(availability, contains('_fetchesInFlight'));
    expect(availabilityProvider, contains('ref.keepAlive()'));
    expect(
      availabilityProvider,
      contains('const Duration(minutes: 2)'),
    );

    expect(history, contains('_allInFlight'));
    expect(history, contains('_allCacheTtl = Duration(minutes: 10)'));
    expect(history, contains('SharedPreferences.getInstance()'));
    expect(history, contains('watchAllLocalFirst'));
    expect(history, contains('StreamProvider<List<HistoricalMatchResult>>'));

    expect(events, contains('_fetchInFlight'));
    expect(events, contains('_cacheTtl = Duration(minutes: 2)'));
    expect(events, contains('SharedPreferences.getInstance()'));
    expect(events, contains('watchEventsLocalFirst'));
    expect(events, contains('StreamProvider<List<ClubEvent>>'));

    expect(pubspec, contains('shared_preferences: ^2.5.3'));

    expect(matches, contains('Future<void>? _loadInFlight'));
    expect(matches, contains('if (_loadKey == key) return existing'));
    expect(matches, contains('_performLoad'));
    expect(matches, contains('final seasonsFuture = _repository.fetchSeasons()'));
    expect(matches, contains('final opponentsFuture = _repository.fetchOpponents()'));
    expect(matches, contains('allSeasons ? _repository.fetchMatches() : null'));
    expect(matches, contains('final localMatches = await _localCache.read()'));
    expect(matches, contains('await _localCache.write(matches)'));
    expect(matches, contains('hasLocalFallback'));

    expect(matchesLocalCache, contains('SharedPreferences.getInstance()'));
    expect(matchesLocalCache, contains('Supabase.instance.client.auth.currentUser?.id'));
    expect(matchesLocalCache, contains('calendar_matches_v'));
    expect(matchesLocalCache, contains('MatchModel.fromJson'));

    expect(calendar, contains('const cacheExtent = 1800.0'));
    expect(calendar, isNot(contains('entries.length * 360.0')));
    expect(calendar, contains('position.jumpTo'));
    expect(calendar, contains('Scrollable.ensureVisible'));
  });
}
