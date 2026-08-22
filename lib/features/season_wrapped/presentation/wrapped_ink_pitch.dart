import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
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

/// Un point du terrain pour représenter chaque poste.
///
/// Un poste couvre parfois plusieurs emplacements symétriques — deux couloirs
/// pour un arrière latéral. En marquer un seul évite d'écrire deux fois le
/// même pourcentage sur le terrain.
const Map<String, Offset> wrappedPositionAnchors = <String, Offset>{
  'Gardien': Offset(.50, .90),
  'Arrière latéral': Offset(.13, .68),
  'Défenseur central': Offset(.50, .74),
  'Milieu défensif': Offset(.50, .56),
  'Milieu': Offset(.50, .40),
  'Milieu offensif': Offset(.50, .24),
  'Ailier': Offset(.13, .18),
  'Attaquant': Offset(.50, .08),
};

/// Les emplacements du terrain qui composent un poste.
List<Offset> wrappedPositionSpots(String? family) {
  if (family == null) return const [];
  return [
    for (final slot in matchSheetSlots)
      if (wrappedPositionFamilies[slot.label] == family) slot.position,
  ];
}

/// Le terrain réduit à ses lignes, avec la part de titularisations à chaque
/// poste occupé.
class WrappedInkPitch extends StatelessWidget {
  const WrappedInkPitch({
    super.key,
    required this.skin,
    this.positions = const [],
    this.progress = 1,
  });

  final WrappedSkin skin;

  /// Les postes occupés et leur part, du plus joué au moins joué.
  final List<SeasonWrappedPosition> positions;

  /// Avancement de l'apparition des marques, de 0 à 1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: CustomPaint(
        painter: _InkPitchPainter(
          positions: positions,
          progress: progress,
          line: skin.text,
          mark: skin.figure,
          markText: skin.background.last,
        ),
      ),
    );
  }
}

class _InkPitchPainter extends CustomPainter {
  const _InkPitchPainter({
    required this.positions,
    required this.progress,
    required this.line,
    required this.mark,
    required this.markText,
  });

  final List<SeasonWrappedPosition> positions;
  final double progress;
  final Color line;
  final Color mark;
  final Color markText;

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

    if (positions.isEmpty || progress <= 0) return;

    // Le poste le plus joué porte le plus gros disque, sans jamais devenir
    // illisible pour les postes occupés une fois ou deux.
    final biggest = positions
        .map((position) => position.share)
        .fold<int>(1, (a, b) => a > b ? a : b);
    final maxRadius = pitch.shortestSide * .095;
    final minRadius = pitch.shortestSide * .062;

    for (var i = 0; i < positions.length; i += 1) {
      final share = ((progress * positions.length) - i).clamp(0.0, 1.0);
      if (share <= 0) continue;

      final entry = positions[i];
      final anchor = wrappedPositionAnchors[entry.position];
      if (anchor == null) continue;

      final center = Offset(
        pitch.left + anchor.dx * pitch.width,
        pitch.top + anchor.dy * pitch.height,
      );
      final ratio = biggest == 0 ? 1.0 : entry.share / biggest;
      final radius = (minRadius + (maxRadius - minRadius) * ratio) * share;

      canvas.drawCircle(center, radius, Paint()..color = mark);
      _paintShare(canvas, center, radius, entry.share, share);
    }
  }

  void _paintShare(
    Canvas canvas,
    Offset center,
    double radius,
    int share,
    double reveal,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: '$share%',
        style: TextStyle(
          fontFamily: WrappedType.display,
          fontSize: radius * .78,
          height: 1,
          fontWeight: FontWeight.w700,
          color: markText.withValues(alpha: reveal),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_InkPitchPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.positions != positions ||
      oldDelegate.line != line ||
      oldDelegate.mark != mark;
}
