import 'dart:ui' as ui;

import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_share_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Bilan personnel de la saison qui vient de se terminer.
///
/// L'écran n'est atteignable que pendant l'intersaison. Les chiffres sont
/// figés au moment de la clôture : ils ne bougent plus.
class SeasonWrappedPage extends ConsumerWidget {
  const SeasonWrappedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wrapped = ref.watch(mySeasonWrappedProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Ma saison')),
      body: wrapped.when(
        loading: () => const GrintaLoader.page(
          message: 'Préparation de ton bilan',
        ),
        error: (_, __) => const GrintaEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Bilan indisponible',
          message: 'Ton bilan n’a pas pu être chargé. Réessaie plus tard.',
        ),
        data: (data) {
          if (data == null) {
            return const GrintaEmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Pas encore de bilan',
              message: 'Ton bilan apparaîtra à la fin de la saison.',
            );
          }
          return _WrappedBody(wrapped: data);
        },
      ),
    );
  }
}

class _WrappedBody extends ConsumerStatefulWidget {
  const _WrappedBody({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  ConsumerState<_WrappedBody> createState() => _WrappedBodyState();
}

class _WrappedBodyState extends ConsumerState<_WrappedBody> {
  /// La feuille en cours de capture. Elle est dessinée hors écran le temps
  /// d'une image, photographiée, puis oubliée.
  SeasonWrappedSheet? _sheetBeingCaptured;
  String? _nameBeingCaptured;
  final GlobalKey _captureKey = GlobalKey();
  bool _isSharing = false;

  Future<void> _share(SeasonWrappedSheet sheet) async {
    if (_isSharing) return;
    // Le nom n'est lu qu'ici : l'affichage du bilan ne doit dépendre que du
    // bilan lui-même.
    setState(() {
      _isSharing = true;
      _sheetBeingCaptured = sheet;
      _nameBeingCaptured =
          ref.read(authControllerProvider).profile?.displayName;
    });

    try {
      final image = await _capture();
      if (image == null) throw StateError('capture vide');
      await Share.shareXFiles(
        [
          XFile.fromData(
            image,
            mimeType: 'image/png',
            name: 'as-grinta-${widget.wrapped.seasonName}.png',
          ),
        ],
        fileNameOverrides: ['as-grinta-${widget.wrapped.seasonName}.png'],
      );
    } catch (error, stackTrace) {
      debugPrint('Partage du bilan impossible : $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L’image n’a pas pu être préparée.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
          _sheetBeingCaptured = null;
          _nameBeingCaptured = null;
        });
      }
    }
  }

  /// Attend que la feuille hors écran soit réellement peinte avant de la
  /// photographier : sans cette attente, la capture arrive trop tôt et rend
  /// une image vide.
  Future<Uint8List?> _capture() async {
    RenderRepaintBoundary? boundary;
    for (var attempt = 0; attempt < 5; attempt += 1) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null && !boundary.debugNeedsPaint) break;
      boundary = null;
    }
    if (boundary == null) return null;

    final image = await boundary.toImage(
      pixelRatio: kSeasonWrappedSharePixelRatio,
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheets = widget.wrapped.sheets;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          itemCount: sheets.length + 1,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.sectionGap),
          itemBuilder: (context, index) {
            if (index == 0) return _WrappedHeader(wrapped: widget.wrapped);
            final sheet = sheets[index - 1];
            return _SheetCard(
              sheet: sheet,
              isSharing: _isSharing,
              onShare: () => _share(sheet),
            );
          },
        ),
        // Hors champ : la feuille en cours de capture, peinte mais invisible.
        if (_sheetBeingCaptured != null)
          Positioned(
            left: -kSeasonWrappedShareWidth * 4,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                key: _captureKey,
                child: SeasonWrappedShareSheet(
                  sheet: _sheetBeingCaptured!,
                  seasonName: widget.wrapped.seasonName,
                  playerName: _nameBeingCaptured,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WrappedHeader extends StatelessWidget {
  const _WrappedHeader({required this.wrapped});

  final SeasonWrapped wrapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saison ${wrapped.seasonName}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.microGap),
        Text(
          'Ton bilan, figé à la clôture de la saison. Les rangs te situent '
          'parmi les ${wrapped.rosterSize} joueurs ayant disputé au moins '
          'un match.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({
    required this.sheet,
    required this.isSharing,
    required this.onShare,
  });

  final SeasonWrappedSheet sheet;
  final bool isSharing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sheet.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.contentGap),
            for (final stat in sheet.stats) ...[
              _StatLine(stat: stat),
              const SizedBox(height: AppSpacing.contentGap),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: isSharing ? null : onShare,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Partager'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.stat});

  final SeasonWrappedStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(stat.value, style: theme.textTheme.titleLarge),
              if (stat.note != null)
                Text(
                  stat.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (stat.isRanked) SeasonWrappedRankChip(rank: stat.rank!),
      ],
    );
  }
}
