import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem_body.dart';
import 'package:as_grinta/features/badges/presentation/badge_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Action d'administration pour recadrer ou remplacer uniquement le visuel
/// central d'un badge.
class BadgeImageEditorButton extends ConsumerStatefulWidget {
  const BadgeImageEditorButton({
    super.key,
    required this.badge,
    this.compact = false,
  });

  final BadgeDef badge;
  final bool compact;

  @override
  ConsumerState<BadgeImageEditorButton> createState() =>
      _BadgeImageEditorButtonState();
}

class _BadgeImageEditorButtonState
    extends ConsumerState<BadgeImageEditorButton> {
  bool _busy = false;

  Future<void> _editImage() async {
    if (_busy) return;

    setState(() => _busy = true);
    final badgeColor =
        parseBadgeColor(widget.badge.color) ?? kDefaultBadgeColor;
    final repository = ref.read(badgeAdminRepositoryProvider);
    final imageUrl = widget.badge.imageUrl?.trim();

    Uint8List? initialBytes;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        initialBytes = await repository.downloadBadgeImage(imageUrl);
      } catch (error) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible de charger l’image actuelle : ${humanizeError(error)}',
            ),
          ),
        );
        return;
      }
    }

    if (!mounted) return;

    Uint8List? edited;
    try {
      edited = await showDialog<Uint8List?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BadgeCropDialog(
          badgeColor: badgeColor,
          initialBytes: initialBytes,
        ),
      );
    } finally {
      if (mounted && edited == null) setState(() => _busy = false);
    }

    if (edited == null || !mounted) return;

    try {
      await repository.replaceBadgeImage(
        badgeCode: widget.badge.code,
        bytes: edited,
      );

      ref.invalidate(badgeCatalogProvider);
      ref.invalidate(myArmoireProvider);
      ref.invalidate(featuredBadgesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image du badge « ${widget.badge.name} » mise à jour.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.badge.imageUrl?.trim().isNotEmpty == true;
    final tooltip = hasImage ? 'Recadrer l’image' : 'Ajouter une image';
    final icon = hasImage ? Icons.crop_rounded : Icons.photo_camera_rounded;

    if (widget.compact) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: _busy ? null : _editImage,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: _busy ? null : _editImage,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(tooltip),
    );
  }
}

class _BadgeCropDialog extends StatefulWidget {
  const _BadgeCropDialog({required this.badgeColor, this.initialBytes});

  final Color badgeColor;
  final Uint8List? initialBytes;

  @override
  State<_BadgeCropDialog> createState() => _BadgeCropDialogState();
}

class _BadgeCropDialogState extends State<_BadgeCropDialog> {
  static const double _size = 220;
  static const int _exportWidth = 1000;
  static const double _exportScale = _exportWidth / _size;

  final TransformationController _controller = TransformationController();
  Uint8List? _bytes;
  bool _picking = false;
  bool _saving = false;
  String? _imageError;

  ui.Rect get _visibleRect {
    final visibleHeight = _size * kBadgeIllustrationRatio;
    return ui.Rect.fromLTWH(
      0,
      (_size - visibleHeight) / 2,
      _size,
      visibleHeight,
    );
  }

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_picking || _saving) return;
    setState(() => _picking = true);
    try {
      final bytes = await pickBadgeImageBytes();
      if (bytes == null || bytes.isEmpty || !mounted) return;

      setState(() {
        _bytes = bytes;
        _imageError = null;
        _controller.value = Matrix4.identity();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lire cette image.')),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<Uint8List> _renderPng() async {
    final bytes = _bytes;
    if (bytes == null) throw StateError('Aucune image sélectionnée.');

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

    final containScale = math.min(_size / source.width, _size / source.height);
    final drawWidth = source.width * containScale;
    final drawHeight = source.height * containScale;
    final left = (_size - drawWidth) / 2;
    final top = (_size - drawHeight) / 2;
    final visibleRect = _visibleRect;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(_exportScale, _exportScale);
    canvas.clipRect(
      ui.Rect.fromLTWH(0, 0, visibleRect.width, visibleRect.height),
    );
    canvas.translate(-visibleRect.left, -visibleRect.top);
    canvas.transform(_controller.value.storage);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(left, top, drawWidth, drawHeight),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final output = await picture.toImage(
      _exportWidth,
      (_exportWidth * kBadgeIllustrationRatio).round(),
    );
    final data = await output.toByteData(format: ui.ImageByteFormat.png);

    output.dispose();
    source.dispose();
    codec.dispose();

    if (data == null) {
      throw StateError('Impossible de générer le PNG du badge.');
    }
    return data.buffer.asUint8List();
  }

  Future<void> _confirm() async {
    if (_saving || _picking || _bytes == null || _imageError != null) return;
    setState(() => _saving = true);
    try {
      final result = await _renderPng();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cette image ne peut pas être préparée. Choisis un PNG ou un JPEG.',
          ),
        ),
      );
    }
  }

  void _reset() {
    _controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final border =
        Color.lerp(widget.badgeColor, Colors.white, .38) ?? widget.badgeColor;
    final bytes = _bytes;

    return AlertDialog(
      title: Text(widget.initialBytes == null ? 'Image du badge' : 'Recadrer'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Le cadre blanc montre exactement ce qui sera visible sur la carte. '
            'Les axes indiquent le centre. Déplace l’image avec un doigt et '
            'pince avec deux doigts pour zoomer ou dézoomer.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: widget.badgeColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: border, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: _size,
                height: _size,
                child: bytes == null
                    ? Center(
                        child: FilledButton.icon(
                          onPressed: _picking ? null : _pickImage,
                          icon: _picking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.photo_library_rounded),
                          label: const Text('Choisir une image'),
                        ),
                      )
                    : _imageError != null
                        ? Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child:
                                Text(_imageError!, textAlign: TextAlign.center),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRect(
                                child: InteractiveViewer(
                                  transformationController: _controller,
                                  boundaryMargin:
                                      const EdgeInsets.all(_size * 4),
                                  minScale: .08,
                                  maxScale: 10,
                                  panEnabled: true,
                                  scaleEnabled: true,
                                  constrained: true,
                                  child: SizedBox(
                                    width: _size,
                                    height: _size,
                                    child: Image.memory(
                                      bytes,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, __, ___) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted && _imageError == null) {
                                            setState(() {
                                              _imageError =
                                                  'Impossible d’afficher cette image. '
                                                  'Choisis un PNG ou un JPEG.';
                                            });
                                          }
                                        });
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const IgnorePointer(
                                child: CustomPaint(
                                  painter: _BadgeCropGuidePainter(),
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (bytes != null)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _saving || _picking ? null : _pickImage,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Changer d’image'),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _reset,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réinitialiser'),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _saving || _picking ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _saving || _picking || bytes == null || _imageError != null
              ? null
              : _confirm,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _BadgeCropGuidePainter extends CustomPainter {
  const _BadgeCropGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final visibleHeight = size.width * kBadgeIllustrationRatio;
    final top = (size.height - visibleHeight) / 2;
    final frame = Rect.fromLTWH(0, top, size.width, visibleHeight);

    final shade = Paint()..color = const Color(0x66000000);
    if (frame.top > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, frame.top),
        shade,
      );
    }
    if (frame.bottom < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          frame.bottom,
          size.width,
          size.height - frame.bottom,
        ),
        shade,
      );
    }

    final framePaint = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(frame.deflate(1), framePaint);

    final axisPaint = Paint()
      ..color = const Color(0xBFFFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(frame.center.dx, frame.top),
      Offset(frame.center.dx, frame.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(frame.left, frame.center.dy),
      Offset(frame.right, frame.center.dy),
      axisPaint,
    );

    canvas.drawCircle(
      frame.center,
      3,
      Paint()
        ..color = const Color(0xF2FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BadgeCropGuidePainter oldDelegate) => false;
}
