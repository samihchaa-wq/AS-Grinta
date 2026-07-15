import 'dart:math' as math;

import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';

const _actualBlue = Color(0xFF397CFF);
const _personalOrange = Color(0xFFFF9D2E);
const _medianPurple = Color(0xFFA33CFF);
const _referenceWidth = 1180.0;
const _referenceHeight = 500.0;

class ReferencePlayerGaugeCard extends StatelessWidget {
  const ReferencePlayerGaugeCard({
    super.key,
    required this.gauge,
    required this.scaleMax,
    required this.personalPrediction,
    required this.onTap,
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final int? personalPrediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final median = gauge.predictions.isEmpty ? null : gauge.median.round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AspectRatio(
        aspectRatio: _referenceWidth / _referenceHeight,
        child: Semantics(
          button: true,
          label: 'Pronostics de ${gauge.playerName}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: _referenceWidth,
                height: _referenceHeight,
                child: _ReferenceCardCanvas(
                  gauge: gauge,
                  scaleMax: scaleMax,
                  personalPrediction: personalPrediction,
                  median: median,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceCardCanvas extends StatelessWidget {
  const _ReferenceCardCanvas({
    required this.gauge,
    required this.scaleMax,
    required this.personalPrediction,
    required this.median,
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final int? personalPrediction;
  final int? median;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080C1F),
        borderRadius: BorderRadius.circular(46),
        border: Border.all(color: const Color(0xFF242849), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B43FF).withValues(alpha: .13),
            blurRadius: 42,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 52,
            top: 48,
            width: 290,
            height: 150,
            child: _PlayerIdentity(
              name: gauge.playerName,
              isGoalkeeper: gauge.isGoalkeeper,
            ),
          ),
          const _TopDivider(left: 362),
          const _TopDivider(left: 620),
          const _TopDivider(left: 882),
          Positioned(
            left: 372,
            top: 63,
            width: 238,
            height: 135,
            child: _Metric(
              label: gauge.isGoalkeeper ? 'Clean sheets :' : 'Buts actuel :',
              value: gauge.actual.toString(),
              color: _actualBlue,
            ),
          ),
          Positioned(
            left: 630,
            top: 63,
            width: 242,
            height: 135,
            child: _Metric(
              label: 'Ton prono :',
              value: personalPrediction?.toString() ?? '—',
              color: _personalOrange,
            ),
          ),
          Positioned(
            left: 892,
            top: 63,
            width: 238,
            height: 135,
            child: _Metric(
              label: 'Médiane :',
              value: median?.toString() ?? '—',
              color: _medianPurple,
            ),
          ),
          Positioned(
            left: 42,
            right: 42,
            top: 236,
            height: 172,
            child: _ReferenceGaugeLine(
              actual: gauge.actual,
              median: median,
              personalPrediction: personalPrediction,
              scaleMax: scaleMax,
              isGoalkeeper: gauge.isGoalkeeper,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopDivider extends StatelessWidget {
  const _TopDivider({required this.left});

  final double left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: 72,
      child: Container(
        width: 2,
        height: 126,
        color: const Color(0xFF252947),
      ),
    );
  }
}

class _PlayerIdentity extends StatelessWidget {
  const _PlayerIdentity({
    required this.name,
    required this.isGoalkeeper,
  });

  final String name;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF11172D),
            border: Border.all(
              color: _medianPurple.withValues(alpha: .30),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _medianPurple.withValues(alpha: .12),
                blurRadius: 24,
              ),
            ],
          ),
          child: Icon(
            isGoalkeeper ? Icons.sports_handball_outlined : Icons.sports_soccer,
            color: _medianPurple,
            size: 62,
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              name,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 58,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFC7C8D7),
            fontSize: 38,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 58,
            height: .9,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: color.withValues(alpha: .20),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReferenceGaugeLine extends StatelessWidget {
  const _ReferenceGaugeLine({
    required this.actual,
    required this.median,
    required this.personalPrediction,
    required this.scaleMax,
    required this.isGoalkeeper,
  });

  final int actual;
  final int? median;
  final int? personalPrediction;
  final int scaleMax;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const edge = 22.0;
        const trackTop = 70.0;
        const trackHeight = 28.0;
        assert(scaleMax > 0);
        final largest = math.max(
          actual.toDouble(),
          math.max(
            median?.toDouble() ?? 0,
            personalPrediction?.toDouble() ?? 0,
          ),
        );
        final visualMax = math.max(1.0, largest);
        final usable = math.max(1.0, constraints.maxWidth - edge * 2);

        double xFor(num value) {
          final ratio = (value.toDouble() / visualMax).clamp(0.0, 1.0);
          return edge + usable * ratio * .90;
        }

        final actualX = xFor(actual);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: edge,
              right: edge,
              top: trackTop,
              child: Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF20253F),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: const Color(0xFF3B4060),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4B43FF).withValues(alpha: .08),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: edge,
              top: trackTop,
              width: math.max(28.0, actualX - edge),
              child: Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF315CFF),
                      Color(0xFF5133FF),
                      Color(0xFFB22BFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6338FF).withValues(alpha: .72),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            for (var index = 1; index < 20; index++)
              Positioned(
                left: edge + usable * index / 20,
                top: trackTop + 16,
                child: Container(
                  width: 2,
                  height: index % 5 == 0 ? 17 : 12,
                  color: Colors.white.withValues(alpha: .17),
                ),
              ),
            if (personalPrediction != null)
              _VerticalMarker(
                x: xFor(personalPrediction!),
                color: _personalOrange,
              ),
            if (median != null)
              _VerticalMarker(
                x: xFor(median!),
                color: _medianPurple,
              ),
            Positioned(
              left: actualX - 39,
              top: trackTop - 25,
              child: _CurrentValueToken(isGoalkeeper: isGoalkeeper),
            ),
          ],
        );
      },
    );
  }
}

class _CurrentValueToken extends StatelessWidget {
  const _CurrentValueToken({required this.isGoalkeeper});

  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF7F7FB),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: _medianPurple.withValues(alpha: .82),
            blurRadius: 22,
          ),
        ],
      ),
      child: isGoalkeeper
          ? const Icon(
              Icons.sports_handball_outlined,
              color: Color(0xFF15172B),
              size: 48,
            )
          : const Padding(
              padding: EdgeInsets.all(8),
              child: CustomPaint(
                painter: _FootballPainter(),
                size: Size.square(60),
              ),
            ),
    );
  }
}

class _VerticalMarker extends StatelessWidget {
  const _VerticalMarker({required this.x, required this.color});

  final double x;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - 9,
      top: 18,
      child: SizedBox(
        width: 18,
        height: 126,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 0,
              bottom: 15,
              child: Container(
                width: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .72),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: color, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .72),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FootballPainter extends CustomPainter {
  const _FootballPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius - 1));
    final white = Paint()..color = const Color(0xFFF8F8FC);
    final black = Paint()..color = const Color(0xFF15172B);
    final seam = Paint()
      ..color = const Color(0xFF5D6070)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas.drawPath(circle, white);
    canvas.save();
    canvas.clipPath(circle);

    final centerPatch = _polygon(center, radius * .25, 5, -math.pi / 2);
    canvas.drawPath(centerPatch, black);

    for (var index = 0; index < 5; index++) {
      final angle = -math.pi / 2 + index * math.pi * 2 / 5;
      final patchCenter = center +
          Offset(
            math.cos(angle) * radius * .77,
            math.sin(angle) * radius * .77,
          );
      final patch = _polygon(
        patchCenter,
        radius * .27,
        5,
        angle + math.pi,
      );
      canvas.drawPath(patch, black);
      canvas.drawLine(
        center +
            Offset(
              math.cos(angle) * radius * .23,
              math.sin(angle) * radius * .23,
            ),
        patchCenter -
            Offset(
              math.cos(angle) * radius * .21,
              math.sin(angle) * radius * .21,
            ),
        seam,
      );
    }

    for (var index = 0; index < 5; index++) {
      final angle = -math.pi / 2 + (index + .5) * math.pi * 2 / 5;
      final start = center +
          Offset(
            math.cos(angle) * radius * .42,
            math.sin(angle) * radius * .42,
          );
      final end = center +
          Offset(
            math.cos(angle) * radius * .95,
            math.sin(angle) * radius * .95,
          );
      canvas.drawLine(start, end, seam);
    }

    canvas.restore();
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = const Color(0xFFB7B8C5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  Path _polygon(
    Offset center,
    double radius,
    int sides,
    double rotation,
  ) {
    final path = Path();
    for (var index = 0; index < sides; index++) {
      final angle = rotation + index * math.pi * 2 / sides;
      final point = center +
          Offset(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
          );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _FootballPainter oldDelegate) => false;
}
