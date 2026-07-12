import 'package:flutter/material.dart';

/// Petits logos dessinés à la main (trait) pour les sections de statistiques,
/// en clin d'œil à deux images cultes : la célébration bras croisés (buteurs)
/// et l'arrêt/plongeon du gardien (clean sheets). Rendus en CustomPaint pour
/// rester nets à toute taille sans dépendance ni asset externe.

class CrossedArmsIcon extends StatelessWidget {
  const CrossedArmsIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(size: Size.square(size), painter: _CrossedArmsPainter(c));
  }
}

class KeeperSaveIcon extends StatelessWidget {
  const KeeperSaveIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(size: Size.square(size), painter: _KeeperSavePainter(c));
  }
}

/// Base : repère 24×24 mis à l'échelle de la taille demandée.
abstract class _GridPainter extends CustomPainter {
  _GridPainter(this.color);

  final Color color;

  Paint _stroke(double s) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = s / 24 * 2.3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Offset _p(double vx, double vy, double s) => Offset(vx / 24 * s, vy / 24 * s);

  void _poly(Canvas canvas, double s, Paint paint, List<List<double>> pts) {
    final path = Path()..moveTo(_p(pts.first[0], pts.first[1], s).dx,
        _p(pts.first[0], pts.first[1], s).dy);
    for (final pt in pts.skip(1)) {
      final o = _p(pt[0], pt[1], s);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}

class _CrossedArmsPainter extends _GridPainter {
  _CrossedArmsPainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(s);
    // Tête
    canvas.drawCircle(_p(12, 4.6, s), 2.8 / 24 * s, paint);
    // Torse (épaules ouvertes → hanches)
    _poly(canvas, s, paint, [
      [7.5, 10.5],
      [9, 20],
      [15, 20],
      [16.5, 10.5],
    ]);
    // Avant-bras croisés sur la poitrine
    _poly(canvas, s, paint, [
      [7.5, 10.5],
      [14, 14.5]
    ]);
    _poly(canvas, s, paint, [
      [16.5, 10.5],
      [10, 14.5]
    ]);
  }
}

class _KeeperSavePainter extends _GridPainter {
  _KeeperSavePainter(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(s);
    // Ballon
    canvas.drawCircle(_p(20, 7, s), 1.9 / 24 * s, paint);
    // Tête
    canvas.drawCircle(_p(12, 8.5, s), 2.2 / 24 * s, paint);
    // Bras tendu vers le ballon
    _poly(canvas, s, paint, [
      [13.5, 9],
      [17.9, 7.8]
    ]);
    // Corps en vol horizontal
    _poly(canvas, s, paint, [
      [11, 10],
      [4, 14]
    ]);
    // Jambes qui fouettent l'air
    _poly(canvas, s, paint, [
      [4, 14],
      [7, 17.5]
    ]);
    _poly(canvas, s, paint, [
      [4, 14],
      [1.5, 17.5]
    ]);
  }
}
