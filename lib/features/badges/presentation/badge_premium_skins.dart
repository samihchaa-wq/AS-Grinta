import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 14 traitements visuels, associés aux couleurs historiques du catalogue.
/// Aucune écriture SQL : le code du badge et son attribution restent intacts.
enum BadgePremiumSkin {
  steel,
  bronze,
  silver,
  gold,
  cyan,
  blue,
  navy,
  obsidian,
  orange,
  ruby,
  garnet,
  diamond,
  emerald,
  violet,
}

/// Les teintes historiques sont volontairement conservées en entrée.
/// Les anciennes bases violet de carrière deviennent bleu foncé ; l'orange
/// des badges custom/mystère devient violet, et les faits de jeu deviennent
/// émeraude. La base Supabase ne change pas.
BadgePremiumSkin? badgePremiumSkinFor(String? color) {
  switch (color?.trim().toUpperCase()) {
    case '#6E7A86':
    case '#7A858D':
      return BadgePremiumSkin.steel;
    case '#B87333':
    case '#CD7F32':
      return BadgePremiumSkin.bronze;
    case '#C4CBD4':
    case '#C0C0C0':
      return BadgePremiumSkin.silver;
    case '#E3B23C':
    case '#D4AF37':
      return BadgePremiumSkin.gold;
    case '#4FA9E8':
      return BadgePremiumSkin.cyan;
    case '#1E3A8A':
      return BadgePremiumSkin.blue;
    case '#7C3AED':
      return BadgePremiumSkin.navy;
    case '#1C1C24':
      return BadgePremiumSkin.obsidian;
    case '#F1706E':
      return BadgePremiumSkin.orange;
    case '#E23B36':
      return BadgePremiumSkin.ruby;
    case '#9E1B1B':
      return BadgePremiumSkin.garnet;
    case '#5FC9D9':
    case '#B9F2FF':
      return BadgePremiumSkin.diamond;
    case '#F2811D':
      return BadgePremiumSkin.emerald;
    case '#F97316':
      return BadgePremiumSkin.violet;
    default:
      return null;
  }
}

Color badgePremiumAccent(BadgePremiumSkin skin) => switch (skin) {
      BadgePremiumSkin.steel => const Color(0xFFA8C1D4),
      BadgePremiumSkin.bronze => const Color(0xFFFFB56A),
      BadgePremiumSkin.silver => const Color(0xFFEAF4FF),
      BadgePremiumSkin.gold => const Color(0xFFFFD850),
      BadgePremiumSkin.cyan => const Color(0xFF3AFAFF),
      BadgePremiumSkin.blue => const Color(0xFF47AFFF),
      BadgePremiumSkin.navy => const Color(0xFF2072FF),
      BadgePremiumSkin.obsidian => const Color(0xFFF1C56D),
      BadgePremiumSkin.orange => const Color(0xFFFFA43C),
      BadgePremiumSkin.ruby => const Color(0xFFFF4761),
      BadgePremiumSkin.garnet => const Color(0xFFF13D87),
      BadgePremiumSkin.diamond => const Color(0xFFC2F7FF),
      BadgePremiumSkin.emerald => const Color(0xFF47FFB5),
      BadgePremiumSkin.violet => const Color(0xFFCD66FF),
    };

Color badgePremiumDark(BadgePremiumSkin skin) => switch (skin) {
      BadgePremiumSkin.steel => const Color(0xFF101B26),
      BadgePremiumSkin.bronze => const Color(0xFF32150E),
      BadgePremiumSkin.silver => const Color(0xFF303C4F),
      BadgePremiumSkin.gold => const Color(0xFF51300A),
      BadgePremiumSkin.cyan => const Color(0xFF02395F),
      BadgePremiumSkin.blue => const Color(0xFF05256A),
      BadgePremiumSkin.navy => const Color(0xFF041237),
      BadgePremiumSkin.obsidian => const Color(0xFF080B12),
      BadgePremiumSkin.orange => const Color(0xFF63210B),
      BadgePremiumSkin.ruby => const Color(0xFF5B0517),
      BadgePremiumSkin.garnet => const Color(0xFF300418),
      BadgePremiumSkin.diamond => const Color(0xFF07579A),
      BadgePremiumSkin.emerald => const Color(0xFF034731),
      BadgePremiumSkin.violet => const Color(0xFF270D54),
    };

/// Dessin statique et léger (aucune animation permanente) : les badges
/// continuent à se rendre correctement même sans accès réseau.
/// L'illustration du joueur reste rendue au-dessus de cette texture.
class BadgePremiumTexturePainter extends CustomPainter {
  const BadgePremiumTexturePainter({
    required this.skin,
    this.footer = false,
  });

  final BadgePremiumSkin skin;
  final bool footer;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final area = const Rect.fromLTWH(0, 0, 100, 100);
    final dark = badgePremiumDark(skin);
    final light = badgePremiumAccent(skin);
    final middle = Color.lerp(dark, light, footer ? .18 : .47)!;
    canvas.drawRect(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [dark, middle, dark],
          stops: const [0, .54, 1],
        ).createShader(area),
    );

    if (footer) {
      // Le texte dynamique conserve une zone sombre, avec de légers éclats.
      _line(canvas, -5, 4, 105, 4, light.withValues(alpha: .65), .8);
      _line(canvas, -8, 90, 100, 28, light.withValues(alpha: .12), 9);
      _line(canvas, -8, 90, 100, 28, light.withValues(alpha: .29), .7);
      canvas.restore();
      return;
    }

    switch (skin) {
      case BadgePremiumSkin.steel:
      case BadgePremiumSkin.bronze:
      case BadgePremiumSkin.silver:
      case BadgePremiumSkin.gold:
        _metal(canvas, light);
        break;
      case BadgePremiumSkin.cyan:
      case BadgePremiumSkin.navy:
        _hexes(canvas, light);
        break;
      case BadgePremiumSkin.blue:
        _metal(canvas, light);
        _waves(canvas, light);
        break;
      case BadgePremiumSkin.obsidian:
        _cracks(canvas, light);
        break;
      case BadgePremiumSkin.orange:
        _goal(canvas, light);
        break;
      case BadgePremiumSkin.ruby:
      case BadgePremiumSkin.diamond:
      case BadgePremiumSkin.emerald:
        _facets(canvas, light);
        break;
      case BadgePremiumSkin.garnet:
        _metal(canvas, light);
        _line(canvas, 0, 90, 100, 10, light.withValues(alpha: .84), 1.4);
        break;
      case BadgePremiumSkin.violet:
        _vortex(canvas, light);
        break;
    }
    // Reflets lumineux aux coins. La transparence évite de masquer le joueur.
    _line(canvas, 0, 8, 57, -4, light.withValues(alpha: .52), 2);
    _line(canvas, 42, 104, 101, 76, light.withValues(alpha: .55), 2);
    canvas.restore();
  }

  void _line(Canvas c, double x1, double y1, double x2, double y2, Color color,
      double stroke) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
  }

  void _metal(Canvas c, Color accent) {
    for (var i = 0; i < 11; i++) {
      final shift = i * 12.0;
      _line(
          c,
          -30 + shift,
          100,
          38 + shift,
          0,
          accent.withValues(alpha: i.isEven ? .19 : .10),
          i % 3 == 0 ? 4.2 : .7);
    }
    final ribbon = Path()
      ..moveTo(-15, 61)
      ..cubicTo(18, 34, 50, 43, 118, -4)
      ..lineTo(116, 12)
      ..cubicTo(57, 62, 21, 56, -10, 80)
      ..close();
    c.drawPath(ribbon, Paint()..color = accent.withValues(alpha: .22));
    _line(c, -7, 65, 104, 2, accent.withValues(alpha: .8), .9);
  }

  void _hexes(Canvas c, Color accent) {
    final p = Paint()
      ..color = accent.withValues(alpha: .23)
      ..strokeWidth = .9
      ..style = PaintingStyle.stroke;
    for (var row = -1; row < 7; row++) {
      for (var col = -1; col < 6; col++) {
        final x = col * 22.0 + (row.isEven ? 0 : 11);
        final y = row * 18.0;
        final h = Path();
        for (var i = 0; i < 6; i++) {
          final t = math.pi * (i / 3 + 1 / 6);
          final point = Offset(x + 12 * math.cos(t), y + 12 * math.sin(t));
          if (i == 0) {
            h.moveTo(point.dx, point.dy);
          } else {
            h.lineTo(point.dx, point.dy);
          }
        }
        h.close();
        c.drawPath(h, p);
      }
    }
    _line(c, 8, 84, 91, 10, accent.withValues(alpha: .62), 2);
  }

  void _waves(Canvas c, Color accent) {
    for (var i = 0; i < 3; i++) {
      final shift = i * 33.0;
      final path = Path()
        ..moveTo(-15, shift + 10)
        ..cubicTo(29, shift - 15, 48, shift + 29, 110, shift - 6);
      c.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: .37)
            ..strokeWidth = 3.2
            ..style = PaintingStyle.stroke);
    }
  }

  void _cracks(Canvas c, Color accent) {
    for (var i = 0; i < 5; i++) {
      final y = i * 23.0;
      final crack = Path()
        ..moveTo(-5, y + 17)
        ..lineTo(18, y + 6)
        ..lineTo(38, y + 12)
        ..lineTo(59, y - 4)
        ..lineTo(83, y + 8)
        ..lineTo(108, y - 13);
      c.drawPath(
          crack,
          Paint()
            ..color = accent.withValues(alpha: .67)
            ..strokeWidth = i.isEven ? 1.1 : .48
            ..style = PaintingStyle.stroke);
    }
  }

  void _goal(Canvas c, Color accent) {
    // Filés de frappe + perspective d'un filet de but, pas de décoration florale.
    for (var i = 0; i < 8; i++) {
      final dy = i * 12.0;
      _line(c, -8, dy + 25, 104, dy - 35, accent.withValues(alpha: .35),
          i.isEven ? 1.4 : .65);
    }
    for (var i = 0; i < 6; i++) {
      final x = 57 + i * 10.0;
      _line(c, x, 12, 84 + (x - 57) * .27, 105, accent.withValues(alpha: .18),
          .65);
    }
  }

  void _facets(Canvas c, Color accent) {
    const nodes = [
      Offset(-8, -3),
      Offset(52, 0),
      Offset(109, -5),
      Offset(11, 49),
      Offset(64, 39),
      Offset(105, 52),
      Offset(-8, 108),
      Offset(43, 89),
      Offset(110, 106),
    ];
    const tris = [
      [0, 1, 3],
      [1, 3, 4],
      [1, 2, 4],
      [2, 4, 5],
      [3, 4, 7],
      [3, 6, 7],
      [4, 5, 8],
      [4, 7, 8],
    ];
    for (var i = 0; i < tris.length; i++) {
      final tri = Path()
        ..moveTo(nodes[tris[i][0]].dx, nodes[tris[i][0]].dy)
        ..lineTo(nodes[tris[i][1]].dx, nodes[tris[i][1]].dy)
        ..lineTo(nodes[tris[i][2]].dx, nodes[tris[i][2]].dy)
        ..close();
      c.drawPath(
          tri, Paint()..color = accent.withValues(alpha: i.isEven ? .17 : .33));
      c.drawPath(
          tri,
          Paint()
            ..color = accent.withValues(alpha: .37)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .55);
    }
  }

  void _vortex(Canvas c, Color accent) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = accent.withValues(alpha: .58);
    for (var i = 0; i < 5; i++) {
      final r = 13.0 + i * 12.0;
      final box = Rect.fromCircle(center: const Offset(53, 49), radius: r);
      c.drawArc(box, i * .6, math.pi * 1.22, false, p);
    }
    for (var i = 0; i < 20; i++) {
      final x = (i * 37 % 95).toDouble();
      final y = (i * 53 % 95).toDouble();
      c.drawCircle(Offset(x, y), i.isEven ? .9 : .45,
          Paint()..color = accent.withValues(alpha: .68));
    }
  }

  @override
  bool shouldRepaint(BadgePremiumTexturePainter old) =>
      skin != old.skin || footer != old.footer;
}

/// Brillance du cadre, par-dessus les photos JPEG historiques (qui peuvent
/// contenir une couleur de fond opaque). Ne recadre ni ne recolore le visage.
class BadgePremiumFramePainter extends CustomPainter {
  const BadgePremiumFramePainter(this.skin);
  final BadgePremiumSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final radius = Radius.circular(size.width * .16);
    final color = badgePremiumAccent(skin);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = color.withValues(alpha: .83)
        ..strokeWidth = math.max(1, size.width * .017)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(BadgePremiumFramePainter old) => skin != old.skin;
}
