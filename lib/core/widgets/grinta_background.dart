import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Fond visuel unique affiché derrière l'intégralité de l'application.
class GrintaBackground extends StatelessWidget {
  const GrintaBackground({required this.child, super.key});

  static const _backgroundAsset =
      'assets/images/module_backgrounds/as_grinta_global_hd.png';

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppTheme.background),
        RepaintBoundary(
          child: Image.asset(
            _backgroundAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            isAntiAlias: false,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),
        ),
        child,
      ],
    );
  }
}
