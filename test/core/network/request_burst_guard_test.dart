import 'package:as_grinta/core/network/request_burst_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Horloge simulée : les attentes du garde-fou avancent le temps au lieu de
/// bloquer le test.
class _FakeClock {
  DateTime now = DateTime.utc(2026, 11, 3, 9);
  final List<Duration> waits = <Duration>[];

  Future<void> wait(Duration delay) async {
    waits.add(delay);
    now = now.add(delay);
  }

  void advance(Duration delay) => now = now.add(delay);
}

const _base = 'https://exemple.supabase.co';

http.Request _rpc(String name, String body) =>
    http.Request('POST', Uri.parse('$_base/rest/v1/rpc/$name'))..body = body;

void main() {
  late _FakeClock clock;
  late int sent;
  late List<String> bursts;
  late RequestBurstGuard guard;

  setUp(() {
    clock = _FakeClock();
    sent = 0;
    bursts = <String>[];
    guard = RequestBurstGuard(
      MockClient((_) async {
        sent++;
        return http.Response('{}', 200);
      }),
      now: () => clock.now,
      wait: clock.wait,
      onBurst: bursts.add,
    );
  });

  test('un usage normal n’est jamais ralenti ni signalé', () async {
    // Une relecture toutes les 4 s pendant 10 minutes : bien plus que ce que
    // fait l'application, et pourtant sous le seuil.
    for (var i = 0; i < 150; i++) {
      await guard.send(_rpc('get_match_live_state', '{"p_match_id":"m1"}'));
      clock.advance(const Duration(seconds: 4));
    }
    expect(sent, 150);
    expect(clock.waits, isEmpty);
    expect(bursts, isEmpty);
  });

  test('des requêtes différentes ne se cumulent pas', () async {
    for (var i = 0; i < 300; i++) {
      await guard
          .send(_rpc('get_my_match_availability', '{"p_match_id":"m$i"}'));
    }
    expect(clock.waits, isEmpty);
    expect(bursts, isEmpty);
  });

  test('la panne de la cloche : la boucle est espacée et signalée une fois',
      () async {
    // Reproduction du bug du 3 novembre : la même lecture relancée dès que la
    // réponse arrive (~50 ms), pendant 10 minutes.
    final end = clock.now.add(const Duration(minutes: 10));
    while (clock.now.isBefore(end)) {
      await guard.send(
        _rpc('get_match_live_notification_subscription', '{"p_match_id":"m"}'),
      );
      clock.advance(const Duration(milliseconds: 50));
    }

    // Sans garde-fou : 10 min / 50 ms = 12 000 requêtes.
    // Avec : 61 avant détection, puis des envois de plus en plus espacés
    // (5 s, 10 s, 20 s, 40 s, puis une par minute).
    expect(sent, lessThan(80));
    expect(clock.waits.last, greaterThan(const Duration(seconds: 59)));
    expect(bursts, ['rpc/get_match_live_notification_subscription']);
  });

  test('la requête redevient libre après deux minutes de silence', () async {
    for (var i = 0; i < 61; i++) {
      await guard.send(_rpc('x', '{}'));
    }
    expect(bursts, hasLength(1));

    clock.advance(const Duration(minutes: 2));
    clock.waits.clear();
    for (var i = 0; i < 10; i++) {
      await guard.send(_rpc('x', '{}'));
      clock.advance(const Duration(seconds: 2));
    }
    expect(clock.waits, isEmpty);
    expect(bursts, hasLength(1), reason: 'un seul signalement par session');
  });

  test('seules la base et les fonctions serveur sont surveillées', () {
    String? label(String url) =>
        RequestBurstGuard.endpointLabel(Uri.parse(url));

    expect(label('$_base/rest/v1/rpc/get_state?x=1'), 'rpc/get_state');
    expect(label('$_base/rest/v1/matches?select=*'), 'matches');
    expect(label('$_base/functions/v1/send-push'), 'send-push');
    expect(label('$_base/auth/v1/token?grant_type=refresh_token'), isNull);
    expect(label('$_base/storage/v1/object/sign/profile-photos'), isNull);
  });

  test('les envois volumineux ne sont jamais ralentis', () async {
    final big = 'x' * 5000;
    for (var i = 0; i < 100; i++) {
      await guard.send(_rpc('upload_like', big));
    }
    expect(sent, 100);
    expect(clock.waits, isEmpty);
  });
}
