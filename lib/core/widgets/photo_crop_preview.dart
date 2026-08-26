import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Ouvre l'éditeur utilisé pour les photos de profil : déplacement libre,
/// pinch-to-zoom / dézoom et export JPEG sur fond opaque.
///
/// L'export est calculé directement depuis l'image source et la matrice de
/// transformation. On ne capture pas le widget à l'écran : cela évite les
/// échecs de RenderRepaintBoundary sur Flutter Web / iOS PWA et garantit un
/// rendu identique à l'aperçu.
Future<Uint8List?> cropProfilePhoto(
  BuildContext context,
  Uint8List bytes, {
  String title = 'Recadrer la photo',
  String instructions = 'Déplace et pince pour zoomer, afin de choisir ce qui apparaîtra sur le terrain.',
  String confirmLabel = 'Utiliser cette photo',
  Color previewColor = const Color(0xFF174936),
  Color previewBorderColor = const Color(0xFF6DAD8B),
}) {
  return showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PhotoCropDialog(
      bytes: bytes,
      title: title,
      instructions: instructions,
      confirmLabel: confirmLabel,
      previewColor: previewColor,
      previewBorderColor: previewBorderColor,
    ),
  );
}

class _PhotoCropDialog extends StatefulWidget {
  const _PhotoCropDialog({
    required this.bytes,
    required this.title,
    required this.instructions,
    required this.confirmLabel,
    required this.previewColor,
    required this.previewBorderColor,
  });

  final Uint8List bytes;
  final String title;
  final String instructions;
  final String confirmLabel;
  final Color previewColor;
  final Color previewBorderColor;

  @override
  State<_PhotoCropDialog> createState() => _PhotoCropDialogState();
}

class _PhotoCropDialogState extends State<_PhotoCropDialog> {
  static const double _cropSize = 180;
  static const double _exportScale = 4;

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
    codec.dispose();
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

  Future<Uint8List> _renderCrop() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(_exportScale, _exportScale);
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, _cropSize, _cropSize));
    // Le JPEG n'a pas de couche alpha : sans ce fond opaque, une zone laissée
    // découverte par le cadrage ressortirait en noir.
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, _cropSize, _cropSize),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.transform(_transformationController.value.storage);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _childWidth, _childHeight),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final side = (_cropSize * _exportScale).round();
    final output = await picture.toImage(side, side);
    // dart:ui ne sait encoder que du PNG, sans perte : les avatars pesaient
    // 171 à 250 ko pièce, soit ~2,5 Mo pour une composition de onze joueurs.
    // On récupère donc les pixels bruts et on les encode en JPEG.
    final data = await output.toByteData(format: ui.ImageByteFormat.rawRgba);

    output.dispose();
    source.dispose();
    codec.dispose();

    if (data == null) {
      throw StateError('Impossible de générer la photo recadrée.');
    }

    final raw = img.Image.fromBytes(
      width: side,
      height: side,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.encodeJpg(raw, quality: 85);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final jpeg = await _renderCrop();
      if (!mounted) return;
      Navigator.pop(context, jpeg);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de préparer cette image. Réessaie.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.instructions, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.previewColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.previewBorderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_cropSize * 0.25),
              child: SizedBox(
                width: _cropSize,
                height: _cropSize,
                child: !_ready
                    ? const ColoredBox(color: Color(0x1FFFFFFF))
                    : ClipRect(
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(_cropSize * 4),
                          minScale: 0.05,
                          maxScale: 8,
                          panEnabled: true,
                          scaleEnabled: true,
                          child: Image.memory(
                            widget.bytes,
                            width: _childWidth,
                            height: _childHeight,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Le cadre coloré n’est pas enregistré dans l’image.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
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
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
