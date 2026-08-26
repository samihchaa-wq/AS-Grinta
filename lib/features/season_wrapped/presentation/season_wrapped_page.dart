import 'dart:ui' as ui;

import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/data/wrapped_music.dart';
import 'package:as_grinta/features/season_wrapped/presentation/season_wrapped_share_sheet.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_motion.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_slides.dart';
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
  const SeasonWrappedPage({super.key, this.preview = false});

  /// Aperçu administrateur : des chiffres d'exemple, annoncés comme tels.
  /// Il ne consulte pas la base, et fonctionne donc avant même que le calcul
  /// des bilans soit déployé.
  final bool preview;

  /// Une saison commence en juillet.
  static String currentSeasonName(DateTime now) {
    final start = now.month >= 7 ? now.year : now.year - 1;
    return '$start-${start + 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (preview) {
      final seasonName =
          ref.watch(seasonWrappedStateProvider).valueOrNull?.seasonName ??
              currentSeasonName(DateTime.now());
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: _WrappedStory(
          wrapped: demoSeasonWrapped(seasonName),
          preview: true,
        ),
      );
    }

    final wrapped = ref.watch(mySeasonWrappedProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: wrapped.when(
        loading: () => const Center(
          child: GrintaLoader.page(message: 'Préparation de ton bilan'),
        ),
        error: (_, __) => const _WrappedMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Bilan indisponible',
          message: 'Ton bilan n’a pas pu être chargé. Réessaie plus tard.',
        ),
        data: (data) {
          if (data == null) {
            return const _WrappedMessage(
              icon: Icons.description_outlined,
              title: 'Pas encore de bilan',
              message: 'Ton bilan apparaîtra à la fin de la saison.',
            );
          }
          return _WrappedStory(wrapped: data);
        },
      ),
    );
  }
}

class _WrappedMessage extends StatelessWidget {
  const _WrappedMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return WrappedBackdrop(
      skin: WrappedSkin.night,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: GrintaEmptyState(
                icon: icon,
                title: title,
                message: message,
              ),
            ),
            const _CloseButton(),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: IconButton(
        tooltip: 'Fermer',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close, color: AppTheme.textPrimary),
      ),
    );
  }
}

class _WrappedStory extends ConsumerStatefulWidget {
  const _WrappedStory({required this.wrapped, this.preview = false});

  final SeasonWrapped wrapped;
  final bool preview;

  @override
  ConsumerState<_WrappedStory> createState() => _WrappedStoryState();
}

class _WrappedStoryState extends ConsumerState<_WrappedStory>
    with SingleTickerProviderStateMixin {
  /// L'ouverture se lit plus longtemps que les autres : le texte s'y écrit
  /// à la machine. La dernière page ne défile pas — on y reste.
  static const Duration _openingDuration = Duration(milliseconds: 6800);
  static const Duration _slideDuration = Duration(milliseconds: 5600);

  late final AnimationController _progress = AnimationController(vsync: this)
    ..addStatusListener(_onSegmentFinished);

  // Résolue à l'ouverture, pas à la volée : la fermeture de l'écran doit
  // pouvoir arrêter la musique alors que le fournisseur n'est plus joignable.
  late final WrappedMusic _music;
  final GlobalKey _captureKey = GlobalKey();

  int _index = 0;
  bool _muted = false;

  /// `true` pendant un appui maintenu ou un partage. Sans ce drapeau, chaque
  /// appui simple demandait une reprise de la musique — et le lecteur web
  /// repartait alors du début.
  bool _suspended = false;
  bool _isSharing = false;
  Widget? _sheetBeingCaptured;
  String? _capturedName;

  int get _slideCount => 11;
  bool get _isLastSlide => _index == _slideCount - 1;

  @override
  void initState() {
    super.initState();
    _music = ref.read(wrappedMusicProvider);
    _startSegment();
    WrappedMusic.readMuted().then((muted) {
      if (!mounted) return;
      setState(() => _muted = muted);
      if (!muted) _music.start();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _music.dispose();
    super.dispose();
  }

  void _startSegment() {
    if (_isLastSlide) {
      _progress.stop();
      _progress.value = 1;
      return;
    }
    _progress
      ..duration = _index == 0 ? _openingDuration : _slideDuration
      ..forward(from: 0);
  }

  void _onSegmentFinished(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_isLastSlide) {
      _goTo(_index + 1);
    }
  }

  void _goTo(int next) {
    if (next < 0 || next >= _slideCount) return;
    setState(() => _index = next);
    _startSegment();
  }

  void _pause() {
    if (_suspended) return;
    _suspended = true;
    _progress.stop();
    if (!_muted) _music.pause();
  }

  void _resume() {
    if (!_suspended) return;
    _suspended = false;
    if (!_isLastSlide) _progress.forward();
    if (!_muted) _music.resume();
  }

  Future<void> _toggleMute() async {
    final muted = !_muted;
    setState(() => _muted = muted);
    await WrappedMusic.writeMuted(muted);
    if (muted) {
      await _music.pause();
    } else {
      await _music.resume();
    }
  }

  /// Photographie une feuille dessinée hors écran, puis ouvre le partage du
  /// système — enregistrer l'image, l'envoyer, la publier.
  Future<void> _shareSheet(Widget sheet) async {
    if (_isSharing) return;
    _pause();
    setState(() {
      _isSharing = true;
      _sheetBeingCaptured = sheet;
      _capturedName = ref.read(wrappedPlayerNameProvider);
    });

    try {
      final image = await _capture();
      if (image == null) throw StateError('capture vide');
      final name = 'as-grinta-${widget.wrapped.seasonName}.png';
      await Share.shareXFiles(
        [XFile.fromData(image, mimeType: 'image/png', name: name)],
        fileNameOverrides: [name],
      );
    } catch (error, stackTrace) {
      debugPrint('Partage du bilan impossible : $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('L’image n’a pas pu être préparée.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
          _sheetBeingCaptured = null;
          _capturedName = null;
        });
        _resume();
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

  Future<void> _openThemeSharing() async {
    _pause();
    final playerName = ref.read(wrappedPlayerNameProvider);
    final chosen = await showModalBottomSheet<SeasonWrappedSheet>(
      context: context,
      backgroundColor: AppTheme.background,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PARTAGER UNE PARTIE',
                  style: WrappedType.label(AppTheme.textFaint, size: 12),
                ),
              ),
            ),
            for (final sheet in widget.wrapped.sheets)
              ListTile(
                title: Text(
                  sheet.title.toUpperCase(),
                  style: WrappedType.title(AppTheme.textPrimary, size: 22),
                ),
                subtitle: Text(
                  sheet.stats.map((stat) => stat.label).join(' · '),
                  style: WrappedType.body(AppTheme.textFaint, size: 12),
                ),
                trailing: const Icon(
                  Icons.ios_share,
                  color: AppTheme.accent,
                  size: 20,
                ),
                onTap: () => Navigator.of(context).pop(sheet),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (chosen == null) {
      _resume();
      return;
    }
    await _shareSheet(
      SeasonWrappedShareSheet(
        sheet: chosen,
        seasonName: widget.wrapped.seasonName,
        playerName: playerName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerName = ref.watch(wrappedPlayerNameProvider);
    final skin = WrappedSkin.sequence[_index];
    final slides = buildWrappedSlides(
      wrapped: widget.wrapped,
      playerName: playerName,
      onShare: () => _shareSheet(
        SeasonWrappedFullShareSheet(
          wrapped: widget.wrapped,
          playerName: playerName,
        ),
      ),
      onShareByTheme: _openThemeSharing,
      preview: widget.preview,
    );

    return Stack(
      children: [
        // Le contenu de l'écran courant seulement : une page voisine
        // préchargée jouerait ses animations hors champ.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: wrappedReducedMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 320),
            child: KeyedSubtree(
              key: ValueKey<int>(_index),
              child: slides[_index],
            ),
          ),
        ),
        Positioned.fill(child: _buildGestureLayer()),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              children: [
                _ProgressBar(
                  count: _slideCount,
                  index: _index,
                  animation: _progress,
                  color: skin.text,
                ),
                _StoryControls(
                  color: skin.text,
                  preview: widget.preview,
                  muted: _muted,
                  onToggleMute: _toggleMute,
                  onClose: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
        if (_sheetBeingCaptured != null)
          Positioned(
            left: -kSeasonWrappedShareWidth * 4,
            top: 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                key: _captureKey,
                child: _CaptureHost(
                  playerName: _capturedName,
                  child: _sheetBeingCaptured!,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGestureLayer() {
    // La zone basse est laissée libre : c'est là que se trouvent les boutons
    // de la dernière page.
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _goTo(_index - 1),
            onLongPressStart: (_) => _pause(),
            onLongPressEnd: (_) => _resume(),
            onLongPressCancel: _resume,
          ),
        ),
        Expanded(
          flex: 2,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _isLastSlide ? null : () => _goTo(_index + 1),
            onLongPressStart: (_) => _pause(),
            onLongPressEnd: (_) => _resume(),
            onLongPressCancel: _resume,
          ),
        ),
      ],
    );
  }
}

/// Enveloppe la feuille capturée : la police et la direction du texte
/// doivent être fixées, l'image ne dépend pas du thème de l'appareil.
class _CaptureHost extends StatelessWidget {
  const _CaptureHost({required this.child, required this.playerName});

  final Widget child;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Material(color: AppTheme.background, child: child),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.count,
    required this.index,
    required this.animation,
    required this.color,
  });

  final int count;
  final int index;
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          for (var i = 0; i < count; i += 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final value = i < index
                            ? 1.0
                            : i == index
                                ? animation.value
                                : 0.0;
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 3,
                          backgroundColor: color.withValues(alpha: .28),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoryControls extends StatelessWidget {
  const _StoryControls({
    required this.color,
    required this.preview,
    required this.muted,
    required this.onToggleMute,
    required this.onClose,
  });

  final Color color;
  final bool preview;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          if (preview)
            // Des chiffres d'exemple ne doivent jamais pouvoir passer pour
            // un vrai bilan : l'aperçu le dit sur chaque écran.
            Container(
              key: const ValueKey('wrapped-preview-badge'),
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.admin,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'APERÇU · CHIFFRES D’EXEMPLE',
                style: WrappedType.label(AppTheme.textPrimary, size: 10),
              ),
            ),
          const Spacer(),
          IconButton(
            key: const ValueKey('wrapped-mute-button'),
            tooltip: muted ? 'Remettre la musique' : 'Couper la musique',
            onPressed: onToggleMute,
            iconSize: 20,
            color: color,
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
          ),
          IconButton(
            key: const ValueKey('wrapped-close-button'),
            tooltip: 'Fermer',
            onPressed: onClose,
            iconSize: 20,
            color: color,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
