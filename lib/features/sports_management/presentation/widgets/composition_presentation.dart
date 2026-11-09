import 'dart:async';
import 'dart:math' as math;

import 'package:as_grinta/core/storage/profile_photo_urls.dart';
import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_detail_header_card.dart';
import 'package:as_grinta/features/sports_management/domain/composition_presentation_plan.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_presentation_camera.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/football_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/stadium_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

part 'composition_presentation_stage.dart';
part 'composition_presentation_elements.dart';

/// Le coach présenté à la fin de la vidéo, quand il s'est dit présent.
class CompositionPresentationCoach {
  const CompositionPresentationCoach({
    required this.id,
    required this.name,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? photoUrl;
}

/// Tout ce que la vidéo de la composition affiche.
class CompositionPresentationData {
  const CompositionPresentationData({
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    required this.field,
    this.bench = const [],
    this.coach,
    this.kickoffAt,
    this.matchType,
    this.typeLabel,
    this.address,
    this.formationCode,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;

  /// Titulaires, déjà alignés sur le dispositif comme sur l'écran
  /// Composition : la vidéo les pose exactement là où l'écran les montre.
  final List<MatchCompositionEntry> field;
  final List<MatchCompositionEntry> bench;
  final CompositionPresentationCoach? coach;
  final DateTime? kickoffAt;
  final String? matchType;

  /// « Amical », « Championnat · J4 »…
  final String? typeLabel;
  final String? address;
  final String? formationCode;

  /// Le lieu tel qu'on le dit : le nom du stade, sans la rue ni la ville.
  String? get venue {
    final value = address?.split(' - ').first.trim();
    return value == null || value.isEmpty ? null : value;
  }

  CompositionPresentationPlan get plan => CompositionPresentationPlan.build(
        field: [
          for (final entry in field)
            if (!entry.isVacant)
              PresentationPerson(
                id: entry.participantId,
                name: entry.displayName,
                position: entry.x == null || entry.y == null
                    ? null
                    : Offset(entry.x!, entry.y!),
                isGoalkeeper: entry.isGoalkeeper,
              ),
        ],
        bench: [
          for (final entry in bench)
            PresentationPerson(
                id: entry.participantId, name: entry.displayName),
        ],
        coach: coach == null
            ? null
            : PresentationPerson(id: _coachId, name: coach!.name),
      );

  static const _coachId = '#coach';
}

/// Signal donné au décor : la présentation tourne ([playing]), où elle en est
/// ([elapsed]), et repart du début à chaque nouvelle prise ([take]). Le décor
/// appelle [onReady] dès qu'il peut s'afficher, ou qu'il a renoncé à charger
/// la vidéo, et décrit son état par [onStatus].
class PresentationCue {
  const PresentationCue({
    required this.playing,
    required this.take,
    required this.elapsed,
    required this.onReady,
    this.onStatus,
  });

  final bool playing;
  final int take;
  final double Function() elapsed;
  final VoidCallback onReady;
  final ValueChanged<String>? onStatus;
}

/// Le décor derrière les joueurs : la vidéo du stade, ou un simple fond dans
/// les tests.
typedef PresentationBackgroundBuilder = Widget Function(
  BuildContext context,
  PresentationCue cue,
);

Widget stadiumVideoBackground(BuildContext context, PresentationCue cue) =>
    StadiumVideo(
      video: 'assets/composition/stade.mp4',
      lightVideo: 'assets/composition/stade-720.mp4',
      poster: 'assets/composition/stade.jpg',
      playing: cue.playing,
      take: cue.take,
      elapsed: cue.elapsed,
      onReady: cue.onReady,
      onStatus: cue.onStatus,
    );

/// Repères de la vraie page sur laquelle la vidéo se pose, à placer sur son
/// [CompositionPitchWithBench] : [pitch] sur le terrain (`pitchKey`), [area]
/// sur le bloc terrain + remplaçants (`key`).
///
/// Sans eux, la vidéo dessine sa propre image de l'écran Composition et se
/// termine dessus, avec « Revoir » et « Fermer ». Avec eux, elle se pose sur
/// la page elle-même, laissée visible dessous, puis se referme d'elle-même :
/// on retombe exactement sur ce qu'on avait, et on peut s'en servir.
class CompositionLanding {
  final GlobalKey pitch = GlobalKey(debugLabel: 'compo-landing-pitch');
  final GlobalKey area = GlobalKey(debugLabel: 'compo-landing-area');

  bool get isOnScreen {
    final box = pitch.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize;
  }
}

/// Décor imposé par les tests, qui n'ont pas de lecteur vidéo.
@visibleForTesting
PresentationBackgroundBuilder? debugPresentationBackground;

/// Ouvre la vidéo de la composition en plein écran. Elle se termine sur
/// l'écran Composition, avec « Revoir » et « Fermer ».
///
/// Appelée pendant un appui (sans attente avant), elle débloque la vidéo du
/// stade ; sinon, l'appelant appelle [primeStadiumVideo] au moment de l'appui.
Future<void> showCompositionPresentation(
  BuildContext context, {
  required CompositionPresentationData data,
  PresentationBackgroundBuilder background = stadiumVideoBackground,
  bool preview = false,
  CompositionLanding? landing,
  bool returnToPage = false,
}) {
  primeStadiumVideo();
  // La page d'arrivée doit être affichée pour qu'on s'y pose. Sans terrain où
  // se poser, [returnToPage] rend quand même la page : la vidéo s'efface
  // au-dessus d'elle. Sinon, la vidéo garde son propre écran de fin.
  final landsOnPage = landing != null && landing.isOnScreen;
  final onPage = landsOnPage || returnToPage;
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      // Posée sur la vraie page : celle-ci reste dessinée dessous.
      opaque: !onPage,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) =>
          CompositionPresentationPage(
        data: data,
        background: debugPresentationBackground ?? background,
        preview: preview,
        landing: landsOnPage ? landing : null,
        endsOnPage: onPage,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class CompositionPresentationPage extends StatefulWidget {
  const CompositionPresentationPage({
    super.key,
    required this.data,
    this.background = stadiumVideoBackground,
    this.preview = false,
    this.landing,
    this.endsOnPage = false,
  });

  final CompositionPresentationData data;
  final PresentationBackgroundBuilder background;

  /// Aperçu de l'admin : la fin rappelle que personne n'a été prévenu et
  /// donne l'état de la vidéo du stade. Un joueur ne voit ni l'un ni l'autre.
  final bool preview;

  /// Le terrain de la vraie page, affichée sous la vidéo, où les photos se
  /// posent (voir [CompositionLanding]).
  final CompositionLanding? landing;

  /// La vidéo se termine sur la page affichée dessous et se referme
  /// d'elle-même. Sans [landing], le terrain se pose au milieu de l'écran
  /// puis s'efface sur la page (l'éditeur d'une compo en cours, dont le
  /// terrain n'a pas la même forme). `false` : la vidéo a son propre écran
  /// de fin, avec « Revoir » et « Fermer ».
  final bool endsOnPage;

  @override
  State<CompositionPresentationPage> createState() =>
      _CompositionPresentationPageState();
}

class _CompositionPresentationPageState
    extends State<CompositionPresentationPage>
    with SingleTickerProviderStateMixin {
  late final CompositionPresentationPlan _plan = widget.data.plan;
  late final Map<String, _Face> _faces = _buildFaces();
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  final _rootKey = GlobalKey();
  final _pitchKey = GlobalKey();

  bool _backgroundReady = false;
  bool _preloading = false;
  bool _photosReady = false;
  bool _started = false;
  int _take = 0;
  Timer? _giveUp;

  /// Ce qui est arrivé à la vidéo du stade, affiché à la fin de l'aperçu.
  String? _videoStatus;

  /// Terrain de l'écran d'arrivée, dans le repère de la page, et largeur de
  /// son gabarit avant réduction (340 avec un banc, sa vraie largeur sinon).
  Rect? _pitchRect;
  double _pitchLayoutWidth = presentationPitchWidth;

  /// Bloc terrain + remplaçants de la vraie page, dans le repère de la page.
  Rect? _areaRect;

  /// Fermeture une fois posée sur la vraie page.
  Timer? _autoClose;

  bool get _onPage => widget.endsOnPage;

  bool get _finished => _time.value >= _plan.duration;

  /// Posée sur la vraie page, la vidéo s'arrête dès que la scène s'est
  /// effacée ([_Frame.stageOpacity]) : la page est alors entièrement là.
  double get _endTime => _onPage ? _plan.flatAt + 0.5 : _plan.duration;

  @override
  void initState() {
    super.initState();
    // Ni la vidéo ni les photos ne doivent faire attendre plus de quelques
    // secondes : passé ce délai, la présentation part avec ce qu'elle a.
    _giveUp = Timer(const Duration(seconds: 6), () {
      _backgroundReady = true;
      _photosReady = true;
      _maybeStart();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloading) return;
    _preloading = true;
    unawaited(_preloadPhotos());
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _autoClose?.cancel();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  Map<String, _Face> _buildFaces() {
    final data = widget.data;
    return {
      for (final entry in [...data.field, ...data.bench])
        entry.participantId: _Face(
          name: entry.displayName,
          lastName: entry.lastInitial,
          photoUrl: entry.photoUrl,
          isGoalkeeper: entry.isGoalkeeper,
        ),
      if (data.coach != null)
        CompositionPresentationData._coachId: _Face(
          name: data.coach!.name,
          photoUrl: data.coach!.photoUrl,
        ),
    };
  }

  /// Signe et télécharge les photos avant le départ, pour qu'aucune
  /// n'apparaisse en retard pendant la vidéo.
  Future<void> _preloadPhotos() async {
    final urls = {
      for (final face in _faces.values)
        if (face.hasPhoto) face.photoUrl!.trim(),
    };
    Future<void> load(String url) async {
      final signed = await ProfilePhotoUrlCache.instance.resolve(url);
      if (signed == null || !mounted) return;
      await precacheImage(
        // Même image que celle de la vignette, pour qu'elle soit reprise
        // telle quelle du cache.
        NetworkImage(
          signed,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        ),
        context,
        onError: (_, __) {},
      );
    }

    try {
      await Future.wait([for (final url in urls) load(url)])
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Une photo en retard ou en échec n'empêche pas la vidéo de partir.
    }
    _photosReady = true;
    _maybeStart();
  }

  void _onBackgroundReady() {
    if (_backgroundReady) return;
    _backgroundReady = true;
    _maybeStart();
  }

  void _maybeStart() {
    if (!mounted || _started || !_backgroundReady || !_photosReady) return;
    _giveUp?.cancel();
    setState(() => _started = true);
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    // Play every phase at half speed, including intro and final camera move.
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond / 2;
    // La page dessous peut encore bouger (chargement, défilement) : la
    // vidéo suit la place réelle de son terrain.
    if (_onPage) _measurePitch();
    if (t >= _endTime) {
      _ticker.stop();
      _time.value = _plan.duration;
      setState(() {});
      _closeOnPage();
      return;
    }
    _time.value = t;
  }

  void _skip() {
    _ticker.stop();
    _time.value = _plan.duration;
    setState(() {});
    _closeOnPage();
  }

  /// Posée sur la vraie page, la vidéo s'efface : on rend la main tout de
  /// suite, pour qu'on ne reste pas devant une page qu'on ne peut pas toucher.
  void _closeOnPage() {
    if (!_onPage) return;
    _autoClose?.cancel();
    _autoClose = Timer(const Duration(milliseconds: 250), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _replay() {
    _ticker.stop();
    _time.value = 0;
    setState(() => _take++);
    _ticker.start();
  }

  void _measurePitch() {
    final root = _rootKey.currentContext?.findRenderObject();
    final landing = widget.landing;
    // Sur la page sans terrain où se poser : le terrain se pose au milieu.
    if (_onPage && landing == null) return;
    final pitch =
        (landing?.pitch ?? _pitchKey).currentContext?.findRenderObject();
    if (root is! RenderBox || pitch is! RenderBox) return;
    if (!root.hasSize || !root.attached) return;
    if (!pitch.hasSize || !pitch.attached) return;
    // La vraie page est sous la vidéo, pas dedans : on passe par l'écran.
    Rect boxRect(RenderBox box) => Rect.fromPoints(
          root.globalToLocal(box.localToGlobal(Offset.zero)),
          root.globalToLocal(
            box.localToGlobal(box.size.bottomRight(Offset.zero)),
          ),
        );
    final rect = boxRect(pitch);
    final area = landing?.area.currentContext?.findRenderObject();
    final areaRect = area is RenderBox && area.attached && area.hasSize
        ? boxRect(area)
        : null;
    if (rect == _pitchRect &&
        areaRect == _areaRect &&
        pitch.size.width == _pitchLayoutWidth) {
      return;
    }
    _pitchRect = rect;
    _areaRect = areaRect;
    _pitchLayoutWidth = pitch.size.width;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePitch());
    // Un lecteur plein écran qu'on referme, comme une boîte de dialogue :
    // pas de page à part entière, donc pas de barre ni d'écusson d'accueil.
    // Posée sur la vraie page, celle-ci reste affichée dessous : elle est
    // tue pour les lecteurs d'écran (VoiceOver) tant que la vidéo est là.
    return BlockSemantics(
      child: _buildPlayer(context),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    return Material(
      color: _onPage ? Colors.transparent : AppTheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stage = _StageFit(constraints.biggest);
          final background = widget.background(
            context,
            PresentationCue(
              playing: _started,
              take: _take,
              elapsed: () => _time.value,
              onReady: _onBackgroundReady,
              onStatus: (status) {
                if (!mounted || status == _videoStatus) return;
                setState(() => _videoStatus = status);
              },
            ),
          );
          return ValueListenableBuilder<double>(
            valueListenable: _time,
            builder: (context, t, _) {
              final frame = _Frame(
                plan: _plan,
                t: _started ? t : 0,
                stage: stage,
                pitchRect: _pitchRect,
                pitchLayoutWidth: _pitchLayoutWidth,
                safeArea: MediaQuery.paddingOf(context),
              );
              return Stack(
                key: _rootKey,
                children: [
                  Positioned.fill(
                    child: _onPage ? _pageCover(frame) : _arrival(frame),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _StageLayer(
                        frame: frame,
                        data: widget.data,
                        faces: _faces,
                        background: background,
                      ),
                    ),
                  ),
                  if (!_started)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: AppTheme.background,
                        child: Center(
                          child: GrintaLoader.inline(
                            message: 'Préparation de la vidéo…',
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(child: _controls(context)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Le voile qui cache la vraie page pendant la vidéo, puis la découvre :
  /// la page autour du terrain apparaît avec [_Frame.chrome], le terrain et
  /// les remplaçants seulement quand les photos s'y posent
  /// ([_Frame.handoff]), pour ne jamais voir deux fois les joueurs.
  Widget _pageCover(_Frame frame) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PageCoverPainter(
          page: 1 - frame.chrome,
          area: 1 - frame.handoff,
          areaRect: _areaRect ?? _pitchRect,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// L'écran Composition sur lequel la vidéo se pose. Il est en place dès le
  /// début, invisible, pour qu'on connaisse l'emplacement exact du terrain.
  Widget _arrival(_Frame frame) {
    final data = widget.data;
    final kickoffAt = data.kickoffAt;
    final chrome = frame.chrome;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        physics: _finished ? null : const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          64,
          AppSpacing.screenGutter,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kickoffAt != null) ...[
                  Opacity(
                    opacity: chrome,
                    child: MatchDetailHeaderCard(
                      homeName: data.homeName,
                      awayName: data.awayName,
                      grintaIsHome: data.grintaIsHome,
                      kickoffAt: kickoffAt,
                      matchType: data.matchType,
                      typeLabel: data.typeLabel,
                      address: data.address,
                      compact: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: chrome,
                        child: const Card(
                          margin: EdgeInsets.zero,
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Opacity(
                            opacity: chrome,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.groups_2_outlined),
                                    const SizedBox(
                                        width: AppSpacing.contentGap),
                                    Expanded(
                                      child: Text(
                                        'Composition',
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    if (data.formationCode != null)
                                      Text(
                                        data.formationCode!,
                                        style: textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.microGap),
                                Text(
                                  'Composition publiée',
                                  style: textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sectionGap),
                                Text(
                                  'Remplaçants (${data.bench.length})',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.contentGap),
                          Opacity(
                            opacity: frame.handoff,
                            child: CompositionPitchWithBench(
                              field: data.field,
                              bench: data.bench,
                              maxWidth: 420,
                              pitchKey: _pitchKey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    // Sur la vraie page, plus de bouton dès qu'elle commence à apparaître :
    // il couvrirait son en-tête, et la vidéo se referme d'elle-même.
    if (_onPage && _time.value >= _plan.moveStart + 1.0) {
      return const SizedBox.shrink();
    }
    if (!_finished) {
      return SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _started
                ? _PillButton(label: 'Passer', onPressed: _skip)
                : _PillButton(
                    label: 'Fermer',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
          ),
        ),
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: !widget.preview
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        onTap: _videoStatus == null ? null : _showVideoStatus,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aperçu : personne n’a été prévenu.',
                              maxLines: 2,
                              style: TextStyle(
                                color: AppTheme.textFaint,
                                fontSize: 13,
                              ),
                            ),
                            if (_videoStatus != null)
                              Text(
                                _videoStatus!.split('\n').first,
                                maxLines: 2,
                                style: const TextStyle(
                                  color: AppTheme.textFaint,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _replay,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Revoir'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Détail de la vidéo du stade, pour une capture d'écran.
  void _showVideoStatus() {
    final status = _videoStatus;
    if (status == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vidéo du stade'),
        content: SelectableText(status.replaceAll(' · ', '\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
