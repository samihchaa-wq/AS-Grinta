import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Ouvre un éditeur de recadrage : l'utilisateur peut déplacer et zoomer sa
/// photo dans le carré qui apparaîtra sur la compo (mêmes coins arrondis,
/// même fond terrain pour juger d'un éventuel fond transparent).
///
/// Renvoie les octets de la photo recadrée, ou `null` si l'utilisateur
/// annule.
Future<Uint8List?> cropProfilePhoto(
  BuildContext context,
  Uint8List bytes,
) {
  return showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PhotoCropDialog(bytes: bytes),
  );
}

class _PhotoCropDialog extends StatefulWidget {
  const _PhotoCropDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PhotoCropDialog> createState() => _PhotoCropDialogState();
}

class _PhotoCropDialogState extends State<_PhotoCropDialog> {
  static const double _cropSize = 160;

  final _boundaryKey = GlobalKey();
  final _transformationController = TransformationController();
  double _childWidth = _cropSize;
  double _childHeight = _cropSize;
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final coverScale = math.max(
      _cropSize / image.width,
      _cropSize / image.height,
    );
    final childWidth = image.width * coverScale;
    final childHeight = image.height * coverScale;
    image.dispose();
    if (!mounted) return;
    setState(() {
      _childWidth = childWidth;
      _childHeight = childHeight;
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(
          -(childWidth - _cropSize) / 2,
          -(childHeight - _cropSize) / 2,
          0,
          1,
        );
      _ready = true;
    });
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 3);
      final byteData = await image?.toByteData(format: ui.ImageByteFormat.png);
      image?.dispose();
      if (!mounted) return;
      Navigator.pop(context, byteData?.buffer.asUint8List());
    } catch (_) {
      if (mounted) Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recadrer la photo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Déplace et pince pour zoomer, afin de choisir ce qui '
            'apparaîtra sur le terrain.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF174936),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF6DAD8B)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_cropSize * 0.28),
              child: SizedBox(
                width: _cropSize,
                height: _cropSize,
                child: !_ready
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : RepaintBoundary(
                        key: _boundaryKey,
                        child: ClipRect(
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            constrained: false,
                            boundaryMargin: EdgeInsets.zero,
                            minScale: 1,
                            maxScale: 4,
                            child: Image.memory(
                              widget.bytes,
                              width: _childWidth,
                              height: _childHeight,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, null),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: !_ready || _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Utiliser cette photo'),
        ),
      ],
    );
  }
}
