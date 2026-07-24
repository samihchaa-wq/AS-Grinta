import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late ThemeData _transparentTheme;

  Uri get _uri => Uri.parse(widget.location);

  int get _selectedIndex {
    final path = _uri.path;
    if (path == '/stats' || path == '/statistics') return 1;
    if (path == '/pronos') {
      final category = _uri.queryParameters['category'];
      if (category == 'general' || category == 'scorers') return 1;
    }
    return 0;
  }

  _ModuleBackgroundKind? get _moduleBackground {
    final path = _uri.path;
    if (path == '/matches' || path.startsWith('/matches/')) {
      return _ModuleBackgroundKind.matches;
    }
    if (path == '/stats' || path == '/statistics') {
      return _ModuleBackgroundKind.stats;
    }
    if (path == '/more' || path == '/profile' || path == '/notifications') {
      return _ModuleBackgroundKind.settings;
    }
    if (path == '/armoire' || path == '/admin/badges') {
      return _ModuleBackgroundKind.badges;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transparentTheme = Theme.of(
      context,
    ).copyWith(scaffoldBackgroundColor: Colors.transparent);
  }

  @override
  Widget build(BuildContext context) {
    final viewingAsUser = ref.watch(viewAsUserProvider);
    final background = _moduleBackground;
    final moduleContent = background == null
        ? widget.child
        : _ModuleBackground(kind: background, child: widget.child);

    return Scaffold(
      body: Column(
        children: [
          if (viewingAsUser)
            _PreviewBanner(
              onExit: () => ref.read(viewAsUserProvider.notifier).state = false,
            ),
          Expanded(
            child: Theme(data: _transparentTheme, child: moduleContent),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: _selectedIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          final destination = index == 0 ? '/matches' : '/stats';
          if (widget.location != destination) context.go(destination);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer_rounded),
            label: 'Matchs',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}

enum _ModuleBackgroundKind { matches, stats, settings, badges }

class _ModuleBackground extends StatelessWidget {
  const _ModuleBackground({required this.kind, required this.child});

  final _ModuleBackgroundKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ModuleBackgroundPainter(kind),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x18000000)),
            child,
          ],
        ),
      ),
    );
  }
}

class _ModuleBackgroundPainter extends CustomPainter {
  const _ModuleBackgroundPainter(this.kind);

  final _ModuleBackgroundKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case _ModuleBackgroundKind.matches:
        _paintMatches(canvas, size);
        break;
      case _ModuleBackgroundKind.stats:
        _paintStats(canvas, size);
        break;
      case _ModuleBackgroundKind.settings:
        _paintSettings(canvas, size);
        break;
      case _ModuleBackgroundKind.badges:
        _paintBadges(canvas, size);
        break;
    }
  }

  void _background(Canvas canvas, Size size, List<Color> colors) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(rect),
    );
  }

  void _paintMatches(Canvas canvas, Size size) {
    _background(
      canvas,
      size,
      const [Color(0xFF075DF2), Color(0xFF002BBE), Color(0xFF00127E)],
    );
    final contour = Paint()
      ..color = const Color(0xFFA5E5FF).withOpacity(0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i < 16; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(-size.width * 0.1, size.height * (0.06 + i * 0.012))
          ..cubicTo(
            size.width * 0.2,
            size.height * (0.01 + i * 0.016),
            size.width * 0.5,
            size.height * (0.18 + i * 0.004),
            size.width,
            size.height * (0.07 + i * 0.014),
          ),
        contour,
      );
    }
    _leopard(canvas, size, Offset(size.width * 0.82, size.height * 0.04));
    _leopard(canvas, size, Offset(-size.width * 0.05, size.height * 0.62));
    _spray(
      canvas,
      size,
      Offset(-size.width * 0.08, size.height * 0.14),
      Offset(size.width * 0.22, size.height * 0.42),
    );
    _spray(
      canvas,
      size,
      Offset(size.width * 0.7, size.height * 0.84),
      Offset(size.width * 1.08, size.height),
    );
  }

  void _leopard(Canvas canvas, Size size, Offset origin) {
    final scale = size.width / 390;
    final outer = Paint()..color = const Color(0xFF36D894).withOpacity(0.38);
    final inner = Paint()..color = const Color(0xFF0639BE).withOpacity(0.8);
    for (var i = 0; i < 25; i++) {
      final center = origin +
          Offset(
            ((i % 5) * 29 + math.sin(i * 2.1) * 6) * scale,
            ((i ~/ 5) * 30 + math.cos(i) * 5) * scale,
          );
      final rect = Rect.fromCenter(
        center: center,
        width: (20 + i % 3 * 5) * scale,
        height: (15 + (i + 1) % 3 * 4) * scale,
      );
      canvas.drawOval(rect, outer);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: rect.width * 0.54,
          height: rect.height * 0.54,
        ),
        inner,
      );
    }
  }

  void _spray(Canvas canvas, Size size, Offset start, Offset end) {
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFF83FF1F).withOpacity(0.25)
        ..strokeWidth = size.width * 0.05
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    final paint = Paint()..color = const Color(0xFF9CFF36).withOpacity(0.75);
    for (var i = 0; i < 90; i++) {
      final t = ((i * 47) % 97) / 97;
      final spread = (((i * 29) % 41) - 20) * size.width / 390;
      canvas.drawCircle(
        Offset.lerp(start, end, t)! + Offset(spread, spread * 0.42),
        0.5 + i % 4 * 0.35,
        paint,
      );
    }
  }

  void _paintStats(Canvas canvas, Size size) {
    _background(
      canvas,
      size,
      const [Color(0xFF02050A), Color(0xFF101A28), Color(0xFF02050A)],
    );
    for (final top in [true, false]) {
      final y = top ? size.height * 0.08 : size.height * 0.92;
      final direction = top ? 1.0 : -1.0;
      for (var i = 0; i < 3; i++) {
        final shift = i * 10 * direction;
        final path = Path()
          ..moveTo(size.width * 0.07, y - shift)
          ..lineTo(size.width * 0.5, y + size.width * 0.18 * direction - shift)
          ..lineTo(size.width * 0.93, y - shift);
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFF6500)
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == 1 ? 2.6 : 1.4,
        );
      }
    }
    _hexagons(canvas, size, left: true);
    _hexagons(canvas, size, left: false);
  }

  void _hexagons(Canvas canvas, Size size, {required bool left}) {
    final paint = Paint()
      ..color = const Color(0xFF788695).withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final startX = left ? -12.0 : size.width * 0.8;
    for (var row = 0; row < 22; row++) {
      for (var col = 0; col < 7; col++) {
        final center = Offset(
          startX + col * 13 + (row.isOdd ? 6.5 : 0),
          size.height * 0.18 + row * 11.2,
        );
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final point = center +
              Offset(math.cos(math.pi / 3 * i), math.sin(math.pi / 3 * i)) * 7;
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path..close(), paint);
      }
    }
  }

  void _paintSettings(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.08, -0.25),
          radius: 1.15,
          colors: [Color(0xFF2B3948), Color(0xFF121C29), Color(0xFF07101B)],
        ).createShader(rect),
    );
    _hud(canvas, size, Offset(size.width * 0.94, size.height * 0.06), true);
    _hud(canvas, size, Offset(size.width * 0.04, size.height * 0.93), false);
    final line = Paint()
      ..color = const Color(0xFF7CCEFF).withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.19)
        ..lineTo(size.width * 0.12, size.height * 0.19)
        ..lineTo(size.width * 0.2, size.height * 0.13)
        ..lineTo(size.width * 0.34, size.height * 0.13),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height * 0.83)
        ..lineTo(size.width * 0.82, size.height * 0.83)
        ..lineTo(size.width * 0.73, size.height * 0.9)
        ..lineTo(size.width * 0.5, size.height * 0.9),
      line,
    );
  }

  void _hud(Canvas canvas, Size size, Offset center, bool top) {
    final paint = Paint()
      ..color = const Color(0xFF6FD5FF).withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var i = 0; i < 7; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: size.width * (0.08 + i * 0.036)),
        top ? math.pi * 0.48 : math.pi * 1.48,
        math.pi * 0.82,
        false,
        paint,
      );
    }
  }

  void _paintBadges(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.05, -0.2),
          radius: 1.15,
          colors: [Color(0xFF17154F), Color(0xFF080827), Color(0xFF020312)],
        ).createShader(rect),
    );
    for (final top in [true, false]) {
      final y = top ? size.height * 0.02 : size.height * 0.98;
      for (final center in [Offset(0, y), Offset(size.width, y)]) {
        for (var i = 0; i < 5; i++) {
          canvas.drawArc(
            Rect.fromCircle(
              center: center,
              radius: size.width * (0.12 + i * 0.045),
            ),
            center.dx == 0 ? -math.pi * 0.5 : math.pi,
            math.pi * 1.05,
            false,
            Paint()
              ..color = (i.isEven
                      ? const Color(0xFFFFC24A)
                      : const Color(0xFF7B38FF))
                  .withOpacity(0.55 - i * 0.055)
              ..style = PaintingStyle.stroke
              ..strokeWidth = i == 0 ? 4 : 1.5,
          );
        }
      }
    }
    final star = Paint()..color = const Color(0xFFFFC85C).withOpacity(0.72);
    for (var i = 0; i < 75; i++) {
      canvas.drawCircle(
        Offset(
          ((i * 67) % 101) / 101 * size.width,
          ((i * 43) % 103) / 103 * size.height,
        ),
        i % 13 == 0 ? 2.1 : 0.65 + i % 3 * 0.3,
        star,
      );
    }
    _laurel(canvas, size, left: true);
    _laurel(canvas, size, left: false);
  }

  void _laurel(Canvas canvas, Size size, {required bool left}) {
    final x = left ? size.width * 0.04 : size.width * 0.96;
    final direction = left ? 1.0 : -1.0;
    final gold = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFE098), Color(0xFFB56C12), Color(0xFFFFD369)],
      ).createShader(Offset.zero & size);
    for (var i = 0; i < 9; i++) {
      final t = i / 9;
      final center = Offset(
        x + direction * size.width * (0.018 + t * 0.045),
        size.height * (0.59 - t * 0.19),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(direction * (-0.65 + t * 0.18));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * 0.045,
          height: size.width * 0.018,
        ),
        gold,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ModuleBackgroundPainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Aperçu utilisateur',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: onExit,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Revenir en admin',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
