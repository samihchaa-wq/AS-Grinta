import 'dart:convert';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fond visuel unique affiché derrière l'intégralité de l'application.
class GrintaBackground extends StatefulWidget {
  const GrintaBackground({required this.child, super.key});

  final Widget child;

  @override
  State<GrintaBackground> createState() => _GrintaBackgroundState();
}

class _GrintaBackgroundState extends State<GrintaBackground> {
  static const _backgroundAsset =
      'assets/images/module_backgrounds/as_grinta_global_small.webp.b64';

  MemoryImage? _background;

  @override
  void initState() {
    super.initState();
    _loadBackground();
  }

  Future<void> _loadBackground() async {
    try {
      final encoded = await rootBundle.loadString(_backgroundAsset);
      final image = MemoryImage(base64Decode(encoded));
      if (!mounted) return;
      setState(() => _background = image);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) precacheImage(image, context);
      });
    } catch (error, stackTrace) {
      AppLogger.error('ui.global_background', error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final background = _background;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppTheme.background),
        if (background != null)
          RepaintBoundary(
            child: Image(
              image: background,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.expand(),
            ),
          ),
        if (background != null) const ColoredBox(color: Color(0x24000000)),
        widget.child,
      ],
    );
  }
}
