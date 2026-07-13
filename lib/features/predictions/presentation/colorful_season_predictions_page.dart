import 'dart:math' as math;

import 'package:as_grinta/features/predictions/presentation/enhanced_season_predictions_page.dart';
import 'package:flutter/material.dart';

/// Habillage visuel des pronostics de saison avec lignes multicolores.
class ColorfulSeasonPredictionsPage extends StatelessWidget {
  const ColorfulSeasonPredictionsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF020A18)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: CustomPaint(painter: _SeasonLinesPainter())),
          Theme(
            data: baseTheme.copyWith(
              scaffoldBackgroundColor: Colors.transparent,
              dividerTheme: DividerThemeData(
                color: Colors.white.withValues(alpha: .12),
                thickness: 1,
                space: 1,
              ),
            ),
            child: EnhancedSeasonPredictionsPage(embedded: embedded),
          ),
        ],
      ),
    );
  }
}

class _SeasonLinesPainter extends CustomPainter {
  const _SeasonLinesPainter();

  static const _colors = <Color>[
    Color(0xFF7C3CFF),
    Color(0xFF1DCBFF),
    Color(0xFF39E784),
    Color(0xFFFFBE3D),
    Color(0xFFFF6A26),
    Color(0xFFFF4FCB),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final diagonalLength =
        math.sqrt(size.width * size.width + size.height * size.height);

    for (var index = 0; index < 18; index++) {
      final color = _colors[index % _colors.length];
      final y = size.height * (index / 17);
      final paint = Paint()
        ..color = color.withValues(alpha: index.isEven ? .12 : .075)
        ..strokeWidth = index % 3 == 0 ? 2.4 : 1.2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(-size.width * .2, y),
        Offset(diagonalLength * .45, y - size.width * .28),
        paint,
      );
    }

    for (var index = 0; index < 8; index++) {
      final color = _colors[(index + 2) % _colors.length];
      final x = size.width * ((index + 1) / 9);
      final paint = Paint()
        ..color = color.withValues(alpha: .055)
        ..strokeWidth = 1.1;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.width * .18, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
