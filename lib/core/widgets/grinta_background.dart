import 'dart:convert';
import 'dart:typed_data';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fond visuel global affiché derrière l'intégralité de l'application.
class GrintaBackground extends StatefulWidget {
  const GrintaBackground({required this.child, super.key});

  final Widget child;

  @override
  State<GrintaBackground> createState() => _GrintaBackgroundState();
}

class _GrintaBackgroundState extends State<GrintaBackground> {
  static const _hdBackgroundAsset =
      'assets/images/module_backgrounds/as_grinta_global_hd.png';
  static const _fallbackBackgroundAsset =
      'assets/images/module_backgrounds/as_grinta_global_small.webp.b64';

  MemoryImage? _background;

  @override
  void initState() {
    super.initState();
    _loadBackground();
  }

  Future<void> _loadBackground() async {
    try {
      final bytes = await _loadPreferredBytes();
      final image = MemoryImage(bytes);

      if (!mounted) return;
      setState(() => _background = image);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) precacheImage(image, context);
      });
    } catch (error, stackTrace) {
      AppLogger.error('ui.global_background', error, stackTrace);
    }
  }

  Future<Uint8List> _loadPreferredBytes() async {
    try {
      final data = await rootBundle.load(_hdBackgroundAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (error, stackTrace) {
      AppLogger.error('ui.global_background_hd', error, stackTrace);
      final encoded = await rootBundle.loadString(_fallbackBackgroundAsset);
      return base64Decode(encoded.trim());
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
          Positioned.fill(
            child: RepaintBoundary(
              child: Image(
                image: background,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
            ),
          ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x52030A18),
                    Color(0x76030A18),
                    Color(0x96030A18),
                  ],
                  stops: [0, .48, 1],
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
