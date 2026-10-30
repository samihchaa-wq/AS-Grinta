import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation_camera.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectNear(Offset actual, Offset expected, {double tolerance = 1}) {
  expect(
    (actual - expected).distance,
    lessThan(tolerance),
    reason: 'attendu $expected, obtenu $actual',
  );
}

void main() {
  test('la caméra du stade retombe sur les repères de la vidéo', () {
    final camera = PresentationCamera.stadium();
    // Valeurs relevées sur la vidéo calculée dans Blender (scène 390 × 844).
    _expectNear(camera.project(-170, 0, -250)!.offset, const Offset(-26, 685));
    _expectNear(camera.project(-170, 0, 250)!.offset, const Offset(33, 229));
    _expectNear(camera.project(0, 0, -195)!.offset, const Offset(195, 619));
    // Le fond du terrain est plus petit que le devant.
    expect(
      camera.project(0, 0, 250)!.scale,
      lessThan(camera.project(0, 0, -250)!.scale),
    );
  });

  test('le dernier plan pose le terrain exactement sur celui de l’écran', () {
    const rect = Rect.fromLTWH(44, 300, 300, 300 / .68);
    final camera = PresentationCamera.landing(rect);
    const local = Size(340, 500);
    for (final corner in [
      Offset.zero,
      const Offset(340, 0),
      const Offset(0, 500),
      const Offset(340, 500),
    ]) {
      final ground = PresentationCamera.groundPoint(corner, local);
      final projected = camera.project(ground.$1, ground.$2, ground.$3)!;
      _expectNear(
        projected.offset,
        rect.topLeft + Offset(corner.dx / 340 * 300, corner.dy / 500 * 441.18),
        tolerance: .5,
      );
      expect(projected.scale, closeTo(300 / 340, 1e-6));
    }
  });

  test('le passage commence au stade et finit au dernier plan', () {
    const rect = Rect.fromLTWH(30, 280, 320, 320 / .68);
    final start = PresentationCamera.between(rect, 0);
    final end = PresentationCamera.between(rect, 1);
    final stadium = PresentationCamera.stadium();
    final landing = PresentationCamera.landing(rect);
    for (final point in [(0.0, 0.0, 0.0), (-170.0, 0.0, 250.0)]) {
      _expectNear(
        start.project(point.$1, point.$2, point.$3)!.offset,
        stadium.project(point.$1, point.$2, point.$3)!.offset,
        tolerance: .01,
      );
      _expectNear(
        end.project(point.$1, point.$2, point.$3)!.offset,
        landing.project(point.$1, point.$2, point.$3)!.offset,
        tolerance: .01,
      );
    }
  });

  test('la matrice du terrain suit la même perspective que les joueurs', () {
    const rect = Rect.fromLTWH(30, 280, 320, 320 / .68);
    const local = Size(326, 326 / .68);
    for (final camera in [
      PresentationCamera.stadium(),
      PresentationCamera.between(rect, .5),
      PresentationCamera.landing(rect),
    ]) {
      final matrix = camera.pitchMatrix(local);
      for (final point in [
        Offset.zero,
        Offset(local.width, 0),
        Offset(local.width / 2, local.height / 2),
        Offset(local.width * .2, local.height * .9),
      ]) {
        final ground = PresentationCamera.groundPoint(point, local);
        _expectNear(
          MatrixUtils.transformPoint(matrix, point),
          camera.project(ground.$1, ground.$2, ground.$3)!.offset,
          tolerance: .01,
        );
      }
    }
  });
}
