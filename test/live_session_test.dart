import 'package:as_grinta/features/live/domain/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveSessionState', () {
    test('parses JSON into a live session state', () {
      final session = LiveSessionState.fromJson({
        'status': 'running',
        'started_at': '2024-01-01T10:00:00.000Z',
        'last_updated_at': '2024-01-01T10:01:00.000Z',
        'elapsed_seconds': 60,
        'controller_profile_id': 'profile-1',
        'controller_session_id': 'session-1',
      });

      expect(session.status, 'running');
      expect(session.elapsedSeconds, 60);
      expect(session.controllerProfileId, 'profile-1');
      expect(session.controllerSessionId, 'session-1');
    });

    test('defaults missing values safely', () {
      final session = LiveSessionState.fromJson({});

      expect(session.status, 'not_started');
      expect(session.elapsedSeconds, 0);
      expect(session.controllerProfileId, isNull);
      expect(session.controllerSessionId, isNull);
    });
  });
}
