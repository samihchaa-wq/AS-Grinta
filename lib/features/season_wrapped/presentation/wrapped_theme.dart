import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Le motif de fond d'un écran. Il occupe la surface que le contenu laisse
/// libre : c'est lui qui empêche les écrans de paraître vides.
enum WrappedMotif {
  /// Bandes obliques, comme un maillot.
  stripes,

  /// Trame de points, comme une impression de presse.
  halftone,

  /// Rayons partant d'un coin : le motif le plus festif.
  rays,

  /// Quadrillage de terrain.
  grid,
}

/// L'habillage d'un écran : fond, couleur des chiffres, motif.
///
/// Huit écrans du même bleu se ressembleraient tous. La rotation des
/// habillages donne au bilan son rythme — et l'inversion jaune sur bleu
/// marque les moments forts.
class WrappedSkin {
  const WrappedSkin({
    required this.background,
    required this.figure,
    required this.text,
    required this.muted,
    required this.badge,
    required this.badgeText,
    required this.motif,
    required this.motifColor,
  });

  final List<Color> background;
  final Color figure;
  final Color text;
  final Color muted;
  final Color badge;
  final Color badgeText;
  final WrappedMotif motif;
  final Color motifColor;

  bool get isLight => figure.computeLuminance() < .4;

  static const WrappedSkin night = WrappedSkin(
    background: [Color(0xFF061A32), AppTheme.background],
    figure: AppTheme.accent,
    text: AppTheme.textPrimary,
    muted: AppTheme.textFaint,
    badge: AppTheme.accent,
    badgeText: AppTheme.background,
    motif: WrappedMotif.halftone,
    motifColor: Color(0x22FBE80C),
  );

  static const WrappedSkin royal = WrappedSkin(
    background: [AppTheme.surfaceHero, Color(0xFF0E2A52)],
    figure: AppTheme.textPrimary,
    text: AppTheme.textPrimary,
    muted: Color(0xFFB9CBE4),
    badge: AppTheme.accent,
    badgeText: AppTheme.background,
    motif: WrappedMotif.stripes,
    motifColor: Color(0x1AFFFFFF),
  );

  /// L'inversion : fond jaune, encre bleu nuit. Réservée aux écrans qu'on
  /// veut faire claquer.
  static const WrappedSkin flash = WrappedSkin(
    background: [AppTheme.accent, Color(0xFFF5C400)],
    figure: AppTheme.background,
    text: AppTheme.background,
    muted: Color(0xCC041224),
    badge: AppTheme.background,
    badgeText: AppTheme.accent,
    motif: WrappedMotif.rays,
    motifColor: Color(0x0F041224),
  );

  static const WrappedSkin deep = WrappedSkin(
    background: [Color(0xFF02101F), Color(0xFF071F3B)],
    figure: AppTheme.reward,
    text: AppTheme.textPrimary,
    muted: AppTheme.textFaint,
    badge: AppTheme.reward,
    badgeText: AppTheme.background,
    motif: WrappedMotif.grid,
    motifColor: Color(0x1AFFD84A),
  );

  /// L'ordre de passage des habillages sur les sept écrans.
  static const List<WrappedSkin> sequence = [
    night,
    royal,
    night,
    deep,
    flash,
    royal,
    flash,
  ];
}

/// Typographie du bilan : une seule condensée, déclinée.
abstract final class WrappedType {
  static const String display = 'Oswald';

  static TextStyle label(Color color, {double size = 13}) => TextStyle(
        fontFamily: display,
        fontSize: size,
        height: 1.2,
        letterSpacing: 2.2,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle title(Color color, {double size = 40}) => TextStyle(
        fontFamily: display,
        fontSize: size,
        height: 1,
        letterSpacing: -.2,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle figure(Color color, {double size = 180}) => TextStyle(
        fontFamily: display,
        fontSize: size,
        height: .82,
        letterSpacing: -3,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle body(Color color, {double size = 15}) => TextStyle(
        fontFamily: display,
        fontSize: size,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: color,
      );
}

/// Le fond d'un écran : dégradé et motif.
class WrappedBackdrop extends StatelessWidget {
  const WrappedBackdrop({super.key, required this.skin, required this.child});

  final WrappedSkin skin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: skin.background,
        ),
      ),
      child: CustomPaint(
        painter: _MotifPainter(motif: skin.motif, color: skin.motifColor),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Un voile en bas de page : sans lui, la légende se confond avec
            // le motif du fond.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 240,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        skin.background.last.withValues(alpha: 0),
                        skin.background.last.withValues(alpha: .55),
                        skin.background.last.withValues(alpha: .82),
                      ],
                      stops: const [0, .55, 1],
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _MotifPainter extends CustomPainter {
  const _MotifPainter({required this.motif, required this.color});

  final WrappedMotif motif;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (motif) {
      case WrappedMotif.stripes:
        final paint = Paint()
          ..color = color
          ..strokeWidth = 26;
        for (var x = -size.height; x < size.width; x += 74) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            paint,
          );
        }
      case WrappedMotif.halftone:
        final paint = Paint()..color = color;
        const step = 26.0;
        for (var y = step; y < size.height; y += step) {
          for (var x = step; x < size.width; x += step) {
            // Les points grossissent vers le bas : la trame respire.
            final scale = .6 + (y / size.height) * 1.6;
            canvas.drawCircle(Offset(x, y), scale, paint);
          }
        }
      case WrappedMotif.rays:
        final paint = Paint()..color = color;
        final origin = Offset(size.width * .5, size.height * 1.05);
        const count = 18;
        for (var i = 0; i < count; i += 1) {
          final start = math.pi + (i * math.pi / count);
          final end = start + math.pi / (count * 2.2);
          final path = Path()
            ..moveTo(origin.dx, origin.dy)
            ..lineTo(
              origin.dx + math.cos(start) * size.height * 2,
              origin.dy + math.sin(start) * size.height * 2,
            )
            ..lineTo(
              origin.dx + math.cos(end) * size.height * 2,
              origin.dy + math.sin(end) * size.height * 2,
            )
            ..close();
          canvas.drawPath(path, paint);
        }
      case WrappedMotif.grid:
        final paint = Paint()
          ..color = color
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
        const step = 44.0;
        for (var x = 0.0; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 0.0; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
    }
  }

  @override
  bool shouldRepaint(_MotifPainter oldDelegate) =>
      oldDelegate.motif != motif || oldDelegate.color != color;
}

class WrappedRankBadge extends StatelessWidget {
  const WrappedRankBadge({
    super.key,
    required this.rank,
    required this.skin,
    this.size = 18,
  });

  final int rank;
  final WrappedSkin skin;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * .8, vertical: size * .3),
      decoration: BoxDecoration(
        color: skin.badge,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        wrappedOrdinal(rank).toUpperCase(),
        style: TextStyle(
          fontFamily: WrappedType.display,
          fontSize: size,
          height: 1.15,
          fontWeight: FontWeight.w500,
          letterSpacing: .6,
          color: skin.badgeText,
        ),
      ),
    );
  }
}

/// « 1er », puis « 2e », « 3e »…
String wrappedOrdinal(int rank) => rank == 1 ? '1er' : '${rank}e';
