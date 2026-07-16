import 'dart:math' as math;

import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _actualBlue = Color(0xFF397CFF);
const _personalOrange = Color(0xFFFF9D2E);
const _medianPurple = Color(0xFFA33CFF);
const _referenceWidth = 1180.0;
const _referenceHeight = 430.0;

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
  });

  final PlayerGauge gauge;
  final int scaleMax;
  final int? personalPrediction;

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
            top: 46,
            width: 1076,
            height: 140,
            child: _PlayerIdentity(
              name: gauge.playerName,
              profileId: gauge.profileId,
              isGoalkeeper: gauge.isGoalkeeper,
            ),
          ),
          Positioned(
            left: 42,
            right: 42,
            top: 210,
            height: 208,
            child: _ReferenceGaugeLine(
              actual: gauge.actual,
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

class _PlayerIdentity extends ConsumerWidget {
  const _PlayerIdentity({
    required this.name,
    required this.profileId,
    required this.isGoalkeeper,
  });

  final String name;
  final String? profileId;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = profileId == null
        ? const <FeaturedBadge>[]
        : ref.watch(featuredBadgesProvider).maybeWhen(
              data: (map) => map[profileId] ?? const <FeaturedBadge>[],
              orElse: () => const <FeaturedBadge>[],
            );

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
        Flexible(
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
        for (final badge in badges.take(2)) ...[
          const SizedBox(width: 18),
          _GaugeBadgeChip(badge: badge, size: 72),
        ],
      ],
    );
  }
}

/// Un badge arboré, rendu à la taille de la carte de référence.
class _GaugeBadgeChip extends StatelessWidget {
  const _GaugeBadgeChip({required this.badge, required this.size});

  final FeaturedBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (badge.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          badge.imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Text(badge.emoji, style: TextStyle(fontSize: size)),
        ),
      );
    }
    return Text(badge.emoji, style: TextStyle(fontSize: size));
  }
}

class _ReferenceGaugeLine extends StatelessWidget {
  const _ReferenceGaugeLine({
    required this.actual,
    required this.personalPrediction,
    required this.scaleMax,
    required this.isGoalkeeper,
  });

  final int actual;
  final int? personalPrediction;
  final int scaleMax;
  final bool isGoalkeeper;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const edge = 22.0;
        const trackTop = 74.0;
        const trackHeight = 28.0;
        const labelTop = 150.0;
        assert(scaleMax > 0);
        final largest = math.max(
          actual.toDouble(),
          personalPrediction?.toDouble() ?? 0,
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
            // Ton prono : le chiffre sous le trait orange.
            if (personalPrediction != null)
              _GaugeValueLabel(
                x: xFor(personalPrediction!),
                top: labelTop,
                value: personalPrediction!.toString(),
                color: _personalOrange,
              ),
            Positioned(
              left: actualX - 39,
              top: trackTop - 25,
              child: _CurrentValueToken(isGoalkeeper: isGoalkeeper),
            ),
            // Buts / clean sheets actuels : le chiffre sous le ballon.
            _GaugeValueLabel(
              x: actualX,
              top: labelTop,
              value: actual.toString(),
              color: _actualBlue,
            ),
          ],
        );
      },
    );
  }
}

/// Un chiffre centré sous un repère de la jauge (ballon ou trait orange).
class _GaugeValueLabel extends StatelessWidget {
  const _GaugeValueLabel({
    required this.x,
    required this.top,
    required this.value,
    required this.color,
  });

  final double x;
  final double top;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - 100,
      top: top,
      width: 200,
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 54,
          height: 1,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(color: color.withValues(alpha: .28), blurRadius: 12),
          ],
        ),
      ),
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
