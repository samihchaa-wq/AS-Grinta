import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:flutter/material.dart';

/// Regroupement des vingt-deux emplacements de la feuille de match en huit
/// postes lisibles.
///
/// Doit rester aligné sur le regroupement fait côté base pour le calcul du
/// bilan : c'est la même liste, écrite dans les deux langues du projet.
const Map<String, String> wrappedPositionFamilies = <String, String>{
  'GB': 'Gardien',
  'DG': 'Arrière latéral',
  'DD': 'Arrière latéral',
  'DCG': 'Défenseur central',
  'DC': 'Défenseur central',
  'DCD': 'Défenseur central',
  'MDG': 'Milieu défensif',
  'MDC': 'Milieu défensif',
  'MDD': 'Milieu défensif',
  'MG': 'Milieu',
  'MCG': 'Milieu',
  'MC': 'Milieu',
  'MCD': 'Milieu',
  'MD': 'Milieu',
  'MOG': 'Milieu offensif',
  'MOC': 'Milieu offensif',
  'MOD': 'Milieu offensif',
  'AG': 'Ailier',
  'AD': 'Ailier',
  'BUG': 'Attaquant',
  'BU': 'Attaquant',
  'BUD': 'Attaquant',
};

/// Les emplacements du terrain qui composent un poste.
List<Offset> wrappedPositionSpots(String? family) {
  if (family == null) return const [];
  return [
    for (final slot in matchSheetSlots)
      if (wrappedPositionFamilies[slot.label] == family) slot.position,
  ];
}

/// Le terrain réduit à ses lignes, aux couleurs de l'écran qui l'accueille.
class WrappedInkPitch extends StatelessWidget {
  const WrappedInkPitch({
    super.key,
    required this.skin,
    this.spots = const [],
    this.progress = 1,
  });

  final WrappedSkin skin;

  /// Les emplacements à encercler, en coordonnées relatives.
  final List<Offset> spots;

  /// Avancement de l'apparition des marques, de 0 à 1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: CustomPaint(
        painter: _InkPitchPainter(
          spots: spots,
          progress: progress,
          line: skin.text,
          mark: skin.figure,
        ),
      ),
    );
  }
}

class _InkPitchPainter extends CustomPainter {
  const _InkPitchPainter({
    required this.spots,
    required this.progress,
    required this.line,
    required this.mark,
  });

  final List<Offset> spots;
  final double progress;
  final Color line;
  final Color mark;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = line.withValues(alpha: .40);

    final inset = size.shortestSide * .04;
    final pitch = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );

    canvas.drawRect(pitch, stroke);
    canvas.drawLine(
      Offset(pitch.left, pitch.center.dy),
      Offset(pitch.right, pitch.center.dy),
      stroke,
    );
    canvas.drawCircle(pitch.center, pitch.width * .13, stroke);

    // Surfaces de réparation, haut et bas.
    final areaWidth = pitch.width * .58;
    final areaHeight = pitch.height * .16;
    for (final top in [pitch.top, pitch.bottom - areaHeight]) {
      canvas.drawRect(
        Rect.fromLTWH(
          pitch.center.dx - areaWidth / 2,
          top,
          areaWidth,
          areaHeight,
        ),
        stroke,
      );
    }

    // Les postes occupés, marqués à la craie.
    if (spots.isEmpty || progress <= 0) return;
    final radius = pitch.shortestSide * .062;
    for (var i = 0; i < spots.length; i += 1) {
      // Les marques apparaissent l'une après l'autre.
      final share = ((progress * spots.length) - i).clamp(0.0, 1.0);
      if (share <= 0) continue;

      final spot = spots[i];
      final center = Offset(
        pitch.left + spot.dx * pitch.width,
        pitch.top + spot.dy * pitch.height,
      );
      canvas.drawCircle(
        center,
        radius * share,
        Paint()..color = mark.withValues(alpha: .22 * share),
      );
      canvas.drawCircle(
        center,
        radius * share,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = mark.withValues(alpha: .95 * share),
      );
    }
  }

  @override
  bool shouldRepaint(_InkPitchPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.spots != spots ||
      oldDelegate.line != line ||
      oldDelegate.mark != mark;
}
