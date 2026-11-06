import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/data/wrapped_music.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compte les ordres reçus, sans jamais toucher au lecteur audio.
class _FakeMusic extends WrappedMusic {
  int starts = 0;
  int pauses = 0;
  int resumes = 0;

  @override
  Future<void> start() async => starts += 1;

  @override
  Future<void> pause() async => pauses += 1;

  @override
  Future<void> resume() async => resumes += 1;

  @override
  Future<void> dispose() async {}
}

Widget _host(_FakeMusic music) {
  return ProviderScope(
    overrides: [
      mySeasonWrappedProvider.overrideWith(
        (ref) async => demoSeasonWrapped('2026-2027'),
      ),
      wrappedPlayerNameProvider.overrideWithValue('Samih'),
      wrappedMusicProvider.overrideWithValue(music),
    ],
    child: const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SeasonWrappedPage(),
      ),
    ),
  );
}

/// Le démarrage de la musique attend la préférence « son coupé », qui est
/// asynchrone : il faut laisser passer ce tour de boucle.
Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  for (var i = 0; i < 4; i += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('changer d’écran ne relance pas la musique', (tester) async {
    final music = _FakeMusic();
    await _open(tester, _host(music));

    expect(music.starts, 1, reason: 'la musique démarre une seule fois');

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 4; i += 1) {
      await tester.tapAt(Offset(size.width * .8, size.height * .5));
      await tester.pump();
      await tester.pump();
    }
    // Un appui simple annule le geste d'appui long : sans garde-fou, cette
    // annulation redemandait une reprise et la piste repartait de zéro.
    await tester.tapAt(Offset(size.width * .1, size.height * .5));
    await tester.pump();
    await tester.pump();

    expect(music.pauses, 0);
    expect(music.resumes, 0);
    expect(music.starts, 1);
  });

  testWidgets('un appui maintenu met en pause puis reprend', (tester) async {
    final music = _FakeMusic();
    await _open(tester, _host(music));

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final gesture = await tester.startGesture(
      Offset(size.width * .8, size.height * .5),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(music.pauses, 1);
    expect(music.resumes, 0);

    await gesture.up();
    await tester.pump();
    expect(music.resumes, 1);
  });

  test('le lecteur ne reprend que ce qu’il a mis en pause', () async {
    final music = WrappedMusic();

    // Jamais démarrée : une reprise ne doit rien casser.
    await music.pause();
    await music.resume();
  });
}
