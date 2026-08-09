import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar network loads are coalesced and briefly cached', () async {
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
    final calendar = await File(
      'lib/features/predictions/presentation/merged_matches_view.dart',
    ).readAsString();

    expect(availability, contains('_fetchesInFlight'));
    expect(availabilityProvider, contains('ref.keepAlive()'));
    expect(
      availabilityProvider,
      contains('const Duration(minutes: 2)'),
    );

    expect(history, contains('_allInFlight'));
    expect(history, contains('_allCacheTtl = Duration(minutes: 10)'));

    expect(events, contains('_fetchInFlight'));
    expect(events, contains('_cacheTtl = Duration(minutes: 2)'));

    expect(matches, contains('Future<void>? _loadInFlight'));
    expect(matches, contains('if (_loadKey == key) return existing'));
    expect(matches, contains('_performLoad'));
    expect(matches, contains('final seasonsFuture = _repository.fetchSeasons()'));
    expect(matches, contains('final opponentsFuture = _repository.fetchOpponents()'));
    expect(matches, contains('allSeasons ? _repository.fetchMatches() : null'));

    expect(calendar, contains('const cacheExtent = 1800.0'));
    expect(calendar, isNot(contains('entries.length * 360.0')));
    expect(calendar, contains('position.jumpTo'));
    expect(calendar, contains('Scrollable.ensureVisible'));
  });
}
