import 'package:as_grinta/features/sports_management/domain/match_availability_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses public player statuses without staff-only fields', () {
    final board = MatchAvailabilityBoard.fromRpc({
      'match_id': 'match-1',
      'kickoff_at': '2026-08-20T18:45:00Z',
      'availability_opens_at': '2026-08-14T18:45:00Z',
      'availability_state': 'open',
      'composition_published': false,
      'players': [
        {'first_name': 'Samih', 'last_name': 'Chaa', 'status': 'available'},
        {'first_name': 'Luka', 'last_name': '', 'status': 'absent'},
        {'first_name': 'Milan', 'last_name': '', 'status': 'no_response'},
        {'first_name': 'Invité', 'last_name': '', 'status': 'not_applicable'},
      ],
    });

    expect(
      board
          .playersWith(MatchAvailabilityBoardStatus.present)
          .single
          .displayName,
      'Samih Chaa',
    );
    expect(
      board.playersWith(MatchAvailabilityBoardStatus.absent).single.displayName,
      'Luka',
    );
    expect(
      board
          .playersWith(MatchAvailabilityBoardStatus.noResponse)
          .single
          .displayName,
      'Milan',
    );
    expect(board.players, hasLength(3));
  });

  test('is hidden once kickoff starts or composition is published', () {
    final beforeKickoff = DateTime.utc(2026, 8, 20, 18);
    final raw = {
      'match_id': 'match-1',
      'kickoff_at': '2026-08-20T18:45:00Z',
      'availability_opens_at': '2026-08-14T18:45:00Z',
      'availability_state': 'open',
      'composition_published': false,
      'players': const [],
    };

    final board = MatchAvailabilityBoard.fromRpc(raw);
    expect(board.isVisibleAt(beforeKickoff), isTrue);
    expect(board.isVisibleAt(DateTime.utc(2026, 8, 20, 18, 45)), isFalse);

    final published = MatchAvailabilityBoard.fromRpc({
      ...raw,
      'composition_published': true,
    });
    expect(published.isVisibleAt(beforeKickoff), isFalse);
  });
}
