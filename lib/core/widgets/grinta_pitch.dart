import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Terrain de football : composant unique et partagé.
///
/// La fiche match, le Live, la composition admin, le pré-coup d'envoi et les
/// archives affichent tous le même terrain. Ce fichier en est la seule
/// définition : pelouse, tracés, cages, maillots, plaques de nom et postes
/// libres.
///
/// Les positions des joueurs viennent du modèle de formation existant ; elles
/// ne sont jamais recalculées ici.

/// Dimensions des vignettes, dérivées de la largeur du terrain.
///
/// Le cahier fixe un disque de 34 px sur un terrain de 380 px de large. La
/// taille suit ensuite la largeur réelle, bornée pour rester lisible aussi
/// bien sur un petit téléphone que sur une tablette.
class GrintaPitchMetrics {
  const GrintaPitchMetrics._(this.jerseyDiameter);

  factory GrintaPitchMetrics.forPitch(double pitchWidth) {
    final diameter =
        (pitchWidth * _referenceDiameter / _referenceWidth).clamp(28.0, 44.0);
    return GrintaPitchMetrics._(diameter.toDouble());
  }

  static const double _referenceWidth = 380;
  static const double _referenceDiameter = 34;

  /// Rapport entre la largeur d'une vignette et celle du terrain.
  ///
  /// Le Tableau Blanc s'en sert pour partager la largeur disponible entre le
  /// banc et le terrain sans que les deux divergent.
  static const double slotWidthRatio =
      _referenceDiameter * _plateRatio / _referenceWidth;

  /// Largeur de la plaque de nom, en proportion du disque.
  static const double _plateRatio = 1.45;

  /// Diamètre du disque du maillot.
  final double jerseyDiameter;

  /// Hauteur de la plaque de nom posée sous le maillot.
  double get namePlateHeight => nameFontSize * 1.25 + 8;

  /// Le disque reste petit, mais la zone tactile de la vignette ne descend
  /// jamais sous 44 px : c'est la cible minimale de l'application.
  double get slotWidth => math.max(44, jerseyDiameter * _plateRatio);

  double get slotHeight => jerseyDiameter + 4 + namePlateHeight;

  /// Numéro ou initiales, en Barlow Condensed.
  double get numberFontSize => jerseyDiameter * .41;

  /// Nom court, en monospace sur sa plaque sombre.
  double get nameFontSize => (jerseyDiameter * .25).clamp(8.5, 11.0).toDouble();

  /// Libellé du poste d'un emplacement libre.
  double get slotLabelFontSize => jerseyDiameter * .3;
}

/// Pelouse, tracés et cages, avec les vignettes posées par-dessus.
///
/// [builder] reçoit la taille réelle du terrain : c'est elle qui permet de
/// convertir les positions en pourcentages du modèle de formation en pixels.
class GrintaPitchSurface extends StatelessWidget {
  const GrintaPitchSurface({
    required this.builder,
    this.highlighted = false,
    this.formationLabel,
    this.surfaceKey,
    this.overlay,
    super.key,
  });

  /// Proportions du terrain, inchangées.
  static const double aspectRatio = .68;
  static const double maxWidth = 540;

  final List<Widget> Function(BuildContext context, Size size) builder;

  /// Vrai pendant qu'une vignette survole le terrain en glisser-déposer.
  final bool highlighted;

  /// Dispositif affiché en bas à gauche (« 4-4-2 », « 3-5-2 »…).
  final String? formationLabel;

  /// Posée sur le conteneur du terrain, pour convertir un point de dépôt.
  final Key? surfaceKey;

  /// Contenu centré affiché au-dessus de la pelouse (consigne, message vide).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedContainer(
              key: surfaceKey,
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                border: Border.all(
                  color: highlighted ? AppTheme.accent : AppTheme.outlineStrong,
                  width: highlighted ? 2 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl - 1),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _GrintaPitchPainter()),
                      ),
                    ),
                    ...builder(context, constraints.biggest),
                    if (formationLabel case final label?)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _FormationPlaque(label: label),
                      ),
                    if (overlay case final content?) Center(child: content),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormationPlaque extends StatelessWidget {
  const _FormationPlaque({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.label(
          color: AppTheme.textSecondary,
          fontSize: 9.5,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Disque du maillot : numéro, initiales ou photo du joueur.
class GrintaPitchJersey extends StatelessWidget {
  const GrintaPitchJersey({
    required this.diameter,
    required this.label,
    super.key,
    this.photo,
    this.highlighted = false,
  });

  /// Dégradé vertical du maillot.
  static const Color jerseyTop = Color(0xFF2A5FA6);
  static const Color jerseyBottom = Color(0xFF12365F);

  final double diameter;

  /// Numéro de maillot, ou initiales quand le numéro n'existe pas.
  final String label;

  /// Photo du joueur : elle remplace le numéro dans le disque.
  final Widget? photo;

  /// Gardien de but, ou joueur mis en avant : l'anneau passe au jaune club.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [jerseyTop, jerseyBottom],
        ),
        border: Border.all(
          color: highlighted
              ? AppTheme.accent
              : Colors.white.withValues(alpha: .85),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: photo ??
          Center(
            child: Text(
              label,
              maxLines: 1,
              style: AppTypography.number(
                color: Colors.white,
                fontSize: diameter * .41,
              ),
            ),
          ),
    );
  }
}

/// Plaque sombre posée sous un maillot : sans elle, un nom clair se perd
/// dans le vert de la pelouse.
class GrintaPitchNamePlate extends StatelessWidget {
  const GrintaPitchNamePlate({
    required this.name,
    required this.fontSize,
    super.key,
  });

  final String name;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTypography.label(
          color: AppTheme.textPrimary,
          fontSize: fontSize,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

/// Emplacement encore vide : le poste réel est rappelé dans le disque, et la
/// plaque indique qu'il est à pourvoir.
class GrintaPitchEmptySlot extends StatelessWidget {
  const GrintaPitchEmptySlot({
    required this.metrics,
    required this.positionLabel,
    super.key,
    this.highlighted = false,
  });

  final GrintaPitchMetrics metrics;
  final String positionLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: metrics.jerseyDiameter,
          child: CustomPaint(
            painter: _DashedRingPainter(highlighted: highlighted),
            child: Center(
              child: Text(
                positionLabel.toUpperCase(),
                maxLines: 1,
                style: AppTypography.label(
                  color: Colors.white,
                  fontSize: metrics.slotLabelFontSize,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        GrintaPitchNamePlate(
          name: 'LIBRE',
          fontSize: metrics.nameFontSize,
        ),
      ],
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.highlighted});

  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = highlighted
            ? AppTheme.accent.withValues(alpha: .3)
            : AppTheme.background.withValues(alpha: .28),
    );

    final stroke = Paint()
      ..color = highlighted ? AppTheme.accent : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlighted ? 2 : 1.4
      ..strokeCap = StrokeCap.round;

    const dashes = 16;
    const sweep = math.pi * 2 / dashes;
    final rect = Rect.fromCircle(center: center, radius: radius - 1);
    for (var index = 0; index < dashes; index++) {
      canvas.drawArc(rect, index * sweep, sweep * .55, false, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) =>
      oldDelegate.highlighted != highlighted;
}

// ---------------------------------------------------------------------------
// Pelouse, tracés et cages
// ---------------------------------------------------------------------------

class _GrintaPitchPainter extends CustomPainter {
  const _GrintaPitchPainter();

  static const Color _grass = Color(0xFF1E6B3E);
  static const Color _lightBand = Color(0x0EFFFFFF);
  static const Color _darkBand = Color(0x0E000000);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    _paintGrass(canvas, size, full);
    _paintMarkings(canvas, size);
  }

  void _paintGrass(Canvas canvas, Size size, Rect full) {
    canvas.drawRect(full, Paint()..color = _grass);

    // Huit bandes de tonte horizontales alternées.
    const bands = 8;
    final bandHeight = size.height / bands;
    for (var index = 0; index < bands; index++) {
      canvas.drawRect(
        Rect.fromLTWH(0, index * bandHeight, size.width, bandHeight),
        Paint()..color = index.isEven ? _lightBand : _darkBand,
      );
    }

    // Halo clair en haut du terrain.
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          radius: .5,
          colors: [
            Colors.white.withValues(alpha: .1),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(size.width / 2, 0),
            width: size.width * 2.4,
            height: size.height * 1.4,
          ),
        ),
    );

    // Ombre interne sur les quatre bords.
    final depth = size.width * .184;
    final shadow = Colors.black.withValues(alpha: .45);
    final clear = Colors.black.withValues(alpha: 0);
    void edge(Rect rect, Alignment begin, Alignment end) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: begin,
            end: end,
            colors: [shadow, clear],
          ).createShader(rect),
      );
    }

    edge(
      Rect.fromLTWH(0, 0, size.width, depth),
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    edge(
      Rect.fromLTWH(0, size.height - depth, size.width, depth),
      Alignment.bottomCenter,
      Alignment.topCenter,
    );
    edge(
      Rect.fromLTWH(0, 0, depth, size.height),
      Alignment.centerLeft,
      Alignment.centerRight,
    );
    edge(
      Rect.fromLTWH(size.width - depth, 0, depth, size.height),
      Alignment.centerRight,
      Alignment.centerLeft,
    );
  }

  void _paintMarkings(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = Colors.white.withValues(alpha: .6);

    final rect = Rect.fromLTRB(
      size.width * .045,
      size.height * .034,
      size.width * .955,
      size.height * .966,
    );

    canvas
      ..drawRect(rect, line)
      ..drawLine(
        Offset(rect.left, rect.center.dy),
        Offset(rect.right, rect.center.dy),
        line,
      )
      ..drawCircle(rect.center, size.width * .1368, line)
      ..drawCircle(rect.center, size.width * .0092, fill);

    final penaltyWidth = rect.width * .56;
    final penaltyHeight = rect.height * .15;
    final goalAreaWidth = rect.width * .28;
    final goalAreaHeight = rect.height * .064;
    final spotRadius = size.width * .0079;
    final arcWidth = size.width * .205;
    final arcHeight = size.height * .0465;

    for (final top in [true, false]) {
      final goalLine = top ? rect.top : rect.bottom;
      final direction = top ? 1.0 : -1.0;
      final penaltyEdge = goalLine + penaltyHeight * direction;

      canvas
        ..drawRect(
          Rect.fromLTRB(
            rect.center.dx - penaltyWidth / 2,
            math.min(goalLine, penaltyEdge),
            rect.center.dx + penaltyWidth / 2,
            math.max(goalLine, penaltyEdge),
          ),
          line,
        )
        ..drawRect(
          Rect.fromLTRB(
            rect.center.dx - goalAreaWidth / 2,
            math.min(goalLine, goalLine + goalAreaHeight * direction),
            rect.center.dx + goalAreaWidth / 2,
            math.max(goalLine, goalLine + goalAreaHeight * direction),
          ),
          line,
        )
        ..drawCircle(
          Offset(rect.center.dx, goalLine + rect.height * .115 * direction),
          spotRadius,
          fill,
        )
        // L'arc de penalty ne montre que la part qui déborde de la surface,
        // vers le milieu du terrain.
        ..drawArc(
          Rect.fromCenter(
            center: Offset(rect.center.dx, penaltyEdge),
            width: arcWidth,
            height: arcHeight * 2,
          ),
          top ? 0 : math.pi,
          math.pi,
          false,
          line,
        );

      // Cage : elle déborde hors du cadre, filet en rayures verticales.
      final goalWidth = rect.width * .22;
      final goalDepth = size.height * .016;
      final goal = Rect.fromLTRB(
        rect.center.dx - goalWidth / 2,
        top ? goalLine - goalDepth : goalLine,
        rect.center.dx + goalWidth / 2,
        top ? goalLine : goalLine + goalDepth,
      );
      canvas.drawRect(goal, line);
      final net = Paint()
        ..color = Colors.white.withValues(alpha: .32)
        ..strokeWidth = 1;
      for (var x = goal.left + 5; x < goal.right; x += 5) {
        canvas.drawLine(Offset(x, goal.top), Offset(x, goal.bottom), net);
      }
    }

    // Corners : un quart de cercle dans chaque angle.
    final cornerRadius = size.width * .0395;
    final corner = Paint()
      ..color = Colors.white.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    void quarter(Offset center, double startAngle) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: cornerRadius),
        startAngle,
        math.pi / 2,
        false,
        corner,
      );
    }

    quarter(rect.topLeft, 0);
    quarter(rect.topRight, math.pi / 2);
    quarter(rect.bottomRight, math.pi);
    quarter(rect.bottomLeft, -math.pi / 2);
  }

  @override
  bool shouldRepaint(covariant _GrintaPitchPainter oldDelegate) => false;
}
