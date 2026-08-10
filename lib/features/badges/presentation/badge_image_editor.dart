import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Bouton d'administration qui remplace uniquement l'image centrale d'un badge.
/// Le fond, le titre, la description, la couleur et le barème restent inchangés.
class BadgeImageEditorButton extends ConsumerStatefulWidget {
  const BadgeImageEditorButton({
    super.key,
    required this.badge,
  });

  final BadgeDef badge;

  @override
  ConsumerState<BadgeImageEditorButton> createState() =>
      _BadgeImageEditorButtonState();
}

class _BadgeImageEditorButtonState
    extends ConsumerState<BadgeImageEditorButton> {
  bool _busy = false;

  Future<void> _replaceImage() async {
    if (_busy) return;

    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final edited = await _editBadgeImage(
      context,
      bytes,
      badgeColor: parseBadgeColor(widget.badge.color) ?? kDefaultBadgeColor,
    );
    if (edited == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(badgeAdminRepositoryProvider).replaceBadgeImage(
            badgeCode: widget.badge.code,
            bytes: edited,
          );

      // Le même visuel peut être présent dans l'armoire, le catalogue admin et
      // à côté des noms : on invalide les trois caches immédiatement.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Remplacer l’image',
      onPressed: _busy ? null : _replaceImage,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_photo_alternate_outlined),
    );
  }
}

Future<Uint8List?> _editBadgeImage(
  BuildContext context,
  Uint8List bytes, {
  required Color badgeColor,
}) {
  return showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BadgeImageEditorDialog(
      bytes: bytes,
      badgeColor: badgeColor,
    ),
  );
}

class _BadgeImageEditorDialog extends StatefulWidget {
  const _BadgeImageEditorDialog({
    required this.bytes,
    required this.badgeColor,
  });

  final Uint8List bytes;
  final Color badgeColor;

  @override
  State<_BadgeImageEditorDialog> createState() =>
      _BadgeImageEditorDialogState();
}

class _BadgeImageEditorDialogState extends State<_BadgeImageEditorDialog> {
  static const double _cropSize = 200;
  static const double _outputPixelRatio = 4;

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
    try {
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
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context, null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette image ne peut pas être ouverte.')),
      );
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: _outputPixelRatio);
      final byteData = await image?.toByteData(format: ui.ImageByteFormat.png);
      image?.dispose();
      if (!mounted) return;
      Navigator.pop(context, byteData?.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de préparer cette image.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_cropSize * 0.26);
    return AlertDialog(
      title: const Text('Image du badge'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Déplace l’image avec un doigt. Pince pour zoomer ou dézoomer. '
            'Les zones transparentes restent transparentes.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              width: _cropSize,
              height: _cropSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Aperçu du fond du badge. Il est volontairement en dehors
                  // du RepaintBoundary : il n'est jamais incorporé au PNG.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(widget.badgeColor, Colors.white, 0.22)!,
                          Color.lerp(widget.badgeColor, Colors.black, 0.12)!,
                        ],
                      ),
                    ),
                  ),
                  if (!_ready)
                    const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    RepaintBoundary(
                      key: _boundaryKey,
                      child: ClipRect(
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          constrained: false,
                          boundaryMargin:
                              const EdgeInsets.all(_cropSize * 1.75),
                          minScale: 0.25,
                          maxScale: 5,
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Le fond coloré ci-dessus sert uniquement d’aperçu.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, null),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: !_ready || _busy ? null : _confirm,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: const Text('Enregistrer l’image'),
        ),
      ],
    );
  }
}
