import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/photo_crop_preview.dart';
import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Action d'administration pour remplacer uniquement le visuel central d'un
/// badge. Elle utilise volontairement le même éditeur que la photo de profil :
/// galerie -> déplacement -> pinch zoom/dézoom -> validation -> sauvegarde.
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

  Future<void> _replaceImage() async {
    if (_busy) return;

    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 100,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final badgeColor =
        parseBadgeColor(widget.badge.color) ?? kDefaultBadgeColor;
    final cropped = await cropProfilePhoto(
      context,
      bytes,
      title: 'Recadrer l’image du badge',
      instructions:
          'Déplace l’image avec un doigt et pince pour zoomer ou dézoomer. '
          'Le fond coloré sert seulement d’aperçu : les zones transparentes '
          'restent transparentes.',
      confirmLabel: 'Utiliser cette image',
      previewColor: badgeColor,
      previewBorderColor:
          Color.lerp(badgeColor, Colors.white, 0.35) ?? badgeColor,
    );
    if (cropped == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(badgeAdminRepositoryProvider).replaceBadgeImage(
            badgeCode: widget.badge.code,
            bytes: cropped,
          );

      ref.invalidate(badgeCatalogProvider);
      ref.invalidate(myArmoireProvider);
      ref.invalidate(featuredBadgesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image du badge « ${widget.badge.name} » mise à jour.',
          ),
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
    if (widget.compact) {
      return IconButton.filledTonal(
        tooltip: 'Changer l’image',
        onPressed: _busy ? null : _replaceImage,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.photo_camera_rounded),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: _busy ? null : _replaceImage,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.photo_camera_rounded),
      label: const Text('Changer l’image'),
    );
  }
}
