import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/widgets.dart' show Matrix4;

/// Taille de la scène de la présentation, en pixels logiques : celle d'un
/// téléphone de 390 × 844. La vidéo du stade est calculée pour elle ; la scène
/// est ensuite mise à l'échelle de l'écran.
const Size presentationStageSize = Size(390, 844);

/// Le terrain du stade, dans le repère du monde : 340 × 500 unités, comme le
/// terrain de l'écran Composition, centré sur l'origine, l'attaque vers +z.
const double presentationPitchWidth = 340;
const double presentationPitchLength = 500;

/// Caméra de la vidéo du stade, et projection des points du terrain sur la
/// scène. Ce sont exactement les réglages qui ont servi à calculer la vidéo :
/// les joueurs dessinés par l'appli tombent donc sur la pelouse filmée.
class PresentationCamera {
  PresentationCamera._(this.position, this._f, this._r, this._u, this._tanHalf);

  /// Caméra placée sur une sphère autour de [target] : [elevationDegrees] est
  /// la hauteur de vue (90 = à la verticale), [distance] l'éloignement.
  factory PresentationCamera.orbit({
    required (double, double, double) target,
    required double elevationDegrees,
    required double distance,
    required double fovDegrees,
  }) {
    final e = elevationDegrees * math.pi / 180;
    final position = (
      target.$1,
      target.$2 + distance * math.sin(e),
      target.$3 - distance * math.cos(e),
    );
    final f = _norm(_sub(target, position));
    // Près de la verticale, le haut de l'image bascule doucement de « vers le
    // ciel » à « vers l'attaque », pour finir sur un terrain vu d'en haut,
    // l'attaque en haut de l'écran.
    final elevation = math.asin((-f.$2).clamp(-1.0, 1.0));
    var k = ((elevation - 1.15) / (1.5 - 1.15)).clamp(0.0, 1.0);
    k = k * k * (3 - 2 * k);
    final up = _norm((0, 1 - k, k));
    final r = _norm(_cross(up, f));
    final u = _cross(f, r);
    return PresentationCamera._(
      position,
      f,
      r,
      u,
      math.tan(fovDegrees * math.pi / 360),
    );
  }

  /// La caméra fixe du stade pendant toute la présentation des lignes.
  factory PresentationCamera.stadium() => PresentationCamera.orbit(
        target: (0, 0, 0),
        elevationDegrees: 54,
        distance: 950,
        fovDegrees: 44,
      );

  /// Caméra à la verticale qui fait coïncider le terrain avec [pitchRect]
  /// (dans le repère de la scène) : c'est le dernier plan, quand la vidéo
  /// rejoint l'écran Composition.
  factory PresentationCamera.landing(Rect pitchRect) {
    const fov = 40.0;
    final focal =
        (presentationStageSize.height / 2) / math.tan(fov * math.pi / 360);
    final scale = pitchRect.width / presentationPitchWidth;
    final center = pitchRect.center;
    return PresentationCamera.orbit(
      target: (
        (presentationStageSize.width / 2 - center.dx) / scale,
        0,
        (center.dy - presentationStageSize.height / 2) / scale,
      ),
      elevationDegrees: 90,
      distance: focal / scale,
      fovDegrees: fov,
    );
  }

  /// Passage progressif de la caméra du stade à celle du dernier plan
  /// ([progress] de 0 à 1, déjà adouci par l'appelant si besoin).
  factory PresentationCamera.between(Rect pitchRect, double progress) {
    final p = progress.clamp(0.0, 1.0);
    final landing = _LandingParameters(pitchRect);
    double lerp(double a, double b) => a + (b - a) * p;
    return PresentationCamera.orbit(
      target: (lerp(0, landing.x), 0, lerp(0, landing.z)),
      elevationDegrees: lerp(54, 90),
      distance: lerp(950, landing.distance),
      fovDegrees: lerp(44, 40),
    );
  }

  final (double, double, double) position;
  final (double, double, double) _f;
  final (double, double, double) _r;
  final (double, double, double) _u;
  final double _tanHalf;

  double get _focal => (presentationStageSize.height / 2) / _tanHalf;

  /// Point du monde → position sur la scène, avec l'échelle locale (pixels de
  /// scène par unité du monde à cette profondeur). Null derrière la caméra.
  ({Offset offset, double scale})? project(double x, double y, double z) {
    final v = _sub((x, y, z), position);
    final depth = _dot(v, _f);
    if (depth <= 1e-3) return null;
    final focal = _focal;
    return (
      offset: Offset(
        presentationStageSize.width / 2 + focal * _dot(v, _r) / depth,
        presentationStageSize.height / 2 - focal * _dot(v, _u) / depth,
      ),
      scale: focal / depth,
    );
  }

  /// Point du sol à partir d'une position du widget terrain de taille
  /// [local] (repère du widget, origine en haut à gauche).
  static (double, double, double) groundPoint(Offset localPoint, Size local) {
    return (
      localPoint.dx / local.width * presentationPitchWidth -
          presentationPitchWidth / 2,
      0,
      presentationPitchLength / 2 -
          localPoint.dy / local.height * presentationPitchLength,
    );
  }

  /// Matrice qui pose un widget terrain de taille [local] sur la pelouse
  /// filmée : c'est une perspective exacte, le widget épouse le sol du stade.
  Matrix4 pitchMatrix(Size local) {
    // Point du sol pour (u, v) : a·u + b·v + c, moins la position caméra.
    final a = (presentationPitchWidth / local.width, 0.0, 0.0);
    final b = (0.0, 0.0, -presentationPitchLength / local.height);
    final c = (
      -presentationPitchWidth / 2 - position.$1,
      -position.$2,
      presentationPitchLength / 2 - position.$3,
    );
    final focal = _focal;
    const halfW = 390 / 2, halfH = 844 / 2;
    // Dénominateur : profondeur ; numérateurs : abscisse et ordonnée écran.
    final du = _dot(a, _f), dv = _dot(b, _f), dc = _dot(c, _f);
    final xu = halfW * du + focal * _dot(a, _r);
    final xv = halfW * dv + focal * _dot(b, _r);
    final xc = halfW * dc + focal * _dot(c, _r);
    final yu = halfH * du - focal * _dot(a, _u);
    final yv = halfH * dv - focal * _dot(b, _u);
    final yc = halfH * dc - focal * _dot(c, _u);
    return Matrix4(
      xu, yu, 0, du, //
      xv, yv, 0, dv, //
      0, 0, 1, 0, //
      xc, yc, 0, dc,
    );
  }
}

class _LandingParameters {
  _LandingParameters(Rect pitchRect)
      : scale = pitchRect.width / presentationPitchWidth,
        focal =
            (presentationStageSize.height / 2) / math.tan(40 * math.pi / 360),
        center = pitchRect.center;

  final double scale;
  final double focal;
  final Offset center;

  double get x => (presentationStageSize.width / 2 - center.dx) / scale;
  double get z => (center.dy - presentationStageSize.height / 2) / scale;
  double get distance => focal / scale;
}

typedef _V = (double, double, double);

_V _sub(_V a, _V b) => (a.$1 - b.$1, a.$2 - b.$2, a.$3 - b.$3);
double _dot(_V a, _V b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
_V _cross(_V a, _V b) => (
      a.$2 * b.$3 - a.$3 * b.$2,
      a.$3 * b.$1 - a.$1 * b.$3,
      a.$1 * b.$2 - a.$2 * b.$1,
    );
_V _norm(_V a) {
  final length = math.sqrt(_dot(a, a));
  return length == 0 ? a : (a.$1 / length, a.$2 / length, a.$3 / length);
}
