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
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

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

/// Signal donné au décor : la présentation tourne ([playing]), et repart du
/// début à chaque nouvelle prise ([take]). Le décor appelle [onReady] dès
/// qu'il peut s'afficher, ou qu'il a renoncé à charger la vidéo.
class PresentationCue {
  const PresentationCue({
    required this.playing,
    required this.take,
    required this.onReady,
  });

  final bool playing;
  final int take;
  final VoidCallback onReady;
}

/// Le décor derrière les joueurs : la vidéo du stade, ou un simple fond dans
/// les tests.
typedef PresentationBackgroundBuilder = Widget Function(
  BuildContext context,
  PresentationCue cue,
);

Widget stadiumVideoBackground(BuildContext context, PresentationCue cue) =>
    _StadiumVideo(cue: cue);

/// Décor imposé par les tests, qui n'ont pas de lecteur vidéo.
@visibleForTesting
PresentationBackgroundBuilder? debugPresentationBackground;

/// Ouvre la vidéo de la composition en plein écran. Elle se termine sur
/// l'écran Composition, avec « Revoir » et « Fermer ».
Future<void> showCompositionPresentation(
  BuildContext context, {
  required CompositionPresentationData data,
  PresentationBackgroundBuilder background = stadiumVideoBackground,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) =>
          CompositionPresentationPage(
        data: data,
        background: debugPresentationBackground ?? background,
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
  });

  final CompositionPresentationData data;
  final PresentationBackgroundBuilder background;

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

  /// Terrain de l'écran d'arrivée, dans le repère de la page, et largeur de
  /// son gabarit avant réduction (340 avec un banc, sa vraie largeur sinon).
  Rect? _pitchRect;
  double _pitchLayoutWidth = presentationPitchWidth;

  bool get _finished => _time.value >= _plan.duration;

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
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (t >= _plan.duration) {
      _ticker.stop();
      _time.value = _plan.duration;
      setState(() {});
      return;
    }
    _time.value = t;
  }

  void _skip() {
    _ticker.stop();
    _time.value = _plan.duration;
    setState(() {});
  }

  void _replay() {
    _ticker.stop();
    _time.value = 0;
    setState(() => _take++);
    _ticker.start();
  }

  void _measurePitch() {
    final root = _rootKey.currentContext?.findRenderObject();
    final pitch = _pitchKey.currentContext?.findRenderObject();
    if (root is! RenderBox || pitch is! RenderBox) return;
    if (!root.hasSize || !pitch.hasSize || !pitch.attached) return;
    final topLeft = pitch.localToGlobal(Offset.zero, ancestor: root);
    final bottomRight = pitch.localToGlobal(
      pitch.size.bottomRight(Offset.zero),
      ancestor: root,
    );
    final rect = Rect.fromPoints(topLeft, bottomRight);
    if (rect == _pitchRect && pitch.size.width == _pitchLayoutWidth) return;
    _pitchRect = rect;
    _pitchLayoutWidth = pitch.size.width;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePitch());
    // Un lecteur plein écran qu'on referme, comme une boîte de dialogue :
    // pas de page à part entière, donc pas de barre ni d'écusson d'accueil.
    return Material(
      color: AppTheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stage = _StageFit(constraints.biggest);
          final background = widget.background(
            context,
            PresentationCue(
              playing: _started,
              take: _take,
              onReady: _onBackgroundReady,
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
                  Positioned.fill(child: _arrival(frame)),
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
              const Expanded(
                child: Text(
                  'Aperçu : personne n’a été prévenu.',
                  maxLines: 2,
                  style: TextStyle(color: AppTheme.textFaint, fontSize: 13),
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
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8C041224),
      shape: const StadiumBorder(
        side: BorderSide(color: Color(0x47EEF3FB)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mise en page de la scène
// ---------------------------------------------------------------------------

/// Place de la scène de 390 × 844 dans l'écran : elle le remplit, quitte à
/// rogner un peu le haut et le bas, sans jamais trop déborder.
class _StageFit {
  _StageFit(this.screen) {
    final contain = math.min(
      screen.width / presentationStageSize.width,
      screen.height / presentationStageSize.height,
    );
    final cover = math.max(
      screen.width / presentationStageSize.width,
      screen.height / presentationStageSize.height,
    );
    scale = math.min(cover, contain * 1.1);
    origin = Offset(
      (screen.width - presentationStageSize.width * scale) / 2,
      (screen.height - presentationStageSize.height * scale) / 2,
    );
  }

  final Size screen;
  late final double scale;
  late final Offset origin;

  Rect toStage(Rect rect) => Rect.fromLTWH(
        (rect.left - origin.dx) / scale,
        (rect.top - origin.dy) / scale,
        rect.width / scale,
        rect.height / scale,
      );
}

/// Tout ce qui dépend de l'instant [t] : caméra, avancement de chaque étape.
class _Frame {
  _Frame({
    required this.plan,
    required this.t,
    required this.stage,
    required Rect? pitchRect,
    required this.pitchLayoutWidth,
    required this.safeArea,
  }) : landing = stage.toStage(pitchRect ?? _fallbackPitch(stage)) {
    move = _sstep(plan.moveStart, plan.flatAt, t);
    camera = move <= 0
        ? PresentationCamera.stadium()
        : PresentationCamera.between(landing, move);
  }

  final CompositionPresentationPlan plan;
  final double t;
  final _StageFit stage;

  /// Terrain de l'écran d'arrivée, dans le repère de la scène.
  final Rect landing;
  final double pitchLayoutWidth;

  /// Marges de l'écran réservées au système (encoche, barre d'état…).
  final EdgeInsets safeArea;
  late final double move;
  late final PresentationCamera camera;

  /// Avant la première mesure : un terrain de 340 de large au milieu.
  static Rect _fallbackPitch(_StageFit stage) => Rect.fromCenter(
        center: stage.screen.center(Offset.zero),
        width: 340,
        height: 500,
      );

  /// Apparition de l'écran Composition autour du terrain.
  double get chrome => _easeOut((t - (plan.moveStart + 1.0)) / 0.7);

  /// Le vrai terrain prend le relais de celui de la vidéo.
  double get handoff => _sstep(plan.flatAt - 0.3, plan.flatAt + 0.1, t);

  /// La scène s'efface une fois posée sur le vrai terrain.
  double get stageOpacity => 1 - _sstep(plan.flatAt, plan.flatAt + 0.45, t);

  /// Échelle de projection du terrain d'arrivée (pixels de scène par unité).
  double get landingScale => landing.width / presentationPitchWidth;

  /// Haut du bandeau « AS Grinta » : à la hauteur du bouton « Passer », sous
  /// la barre d'état, quelle que soit la part de la scène rognée en haut.
  double get bugTop => (safeArea.top + 29 - stage.origin.dy) / stage.scale - 13;

  /// Ligne des remplaçants et du coach : en bas de l'image, sans jamais
  /// passer sous le bord de l'écran.
  double get stripY => math.min(
        778,
        (stage.screen.height - safeArea.bottom - stage.origin.dy) /
                stage.scale -
            50,
      );
}

// ---------------------------------------------------------------------------
// La scène : stade, terrain, écrans de ligne, photos
// ---------------------------------------------------------------------------

const double _panelCenterY = 418;
const double _coachX = 330;

class _StageLayer extends StatelessWidget {
  const _StageLayer({
    required this.frame,
    required this.data,
    required this.faces,
    required this.background,
  });

  final _Frame frame;
  final CompositionPresentationData data;
  final Map<String, _Face> faces;
  final Widget background;

  @override
  Widget build(BuildContext context) {
    final t = frame.t;
    final plan = frame.plan;
    final stageOpacity = frame.stageOpacity;
    final backgroundOpacity = _sstep(0, 0.6, t) *
        (1 - _sstep(plan.moveStart + 0.2, plan.flatAt - 0.5, t));
    final pitchOpacity =
        _sstep(plan.moveStart, plan.moveStart + 0.5, t) * stageOpacity;

    final layers = <(double, Widget)>[];
    if (pitchOpacity > 0) {
      layers.add((0, _pitch(pitchOpacity)));
    }
    layers.addAll(_benchBar());
    layers.addAll(_panel());
    for (final line in plan.lines) {
      layers.addAll(_people(line));
    }
    layers.sort((a, b) => a.$1.compareTo(b.$1));

    return Stack(
      children: [
        // Le stade, mis à l'échelle de la scène.
        Positioned.fill(
          child: Opacity(
            opacity: backgroundOpacity.clamp(0.0, 1.0),
            child: _staged(
              Stack(
                fit: StackFit.expand,
                children: [
                  Transform.scale(
                    scale: 1 + 0.12 * frame.move,
                    child: background,
                  ),
                  // Sur un écran plus large que la scène, le stade se fond
                  // dans le fond de l'écran au lieu de s'arrêter net.
                  if (frame.stage.origin.dx > 0.5)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.background,
                            Color(0x00041224),
                            Color(0x00041224),
                            AppTheme.background,
                          ],
                          stops: [0, .07, .93, 1],
                        ),
                      ),
                    ),
                ],
              ),
              clip: true,
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: stageOpacity,
            child: _staged(
              Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (_, widget) in layers) widget,
                  ..._intro(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pose [child] (dessiné pour 390 × 844) à la place de la scène.
  Widget _staged(Widget child, {bool clip = false}) {
    final stage = frame.stage;
    final placed = Transform(
      transform: Matrix4.identity()
        ..translateByDouble(stage.origin.dx, stage.origin.dy, 0, 1)
        ..scaleByDouble(stage.scale, stage.scale, 1, 1),
      child: SizedBox.fromSize(
        size: presentationStageSize,
        child: clip ? ClipRect(child: child) : child,
      ),
    );
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: placed,
    );
  }

  /// Le terrain de l'appli, posé en perspective exacte sur la pelouse filmée,
  /// puis redressé jusqu'au terrain de l'écran Composition.
  Widget _pitch(double opacity) {
    // Dessiné à la taille qu'il aura à l'écran d'arrivée, pour que bordure et
    // arrondi tombent juste au moment du relais.
    final size = frame.landing.size * frame.stage.scale;
    return Positioned(
      left: 0,
      top: 0,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          transform: frame.camera.pitchMatrix(size),
          child: SizedBox.fromSize(
            size: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF124529),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF6DAD8B), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: const CustomPaint(painter: FootballPitchPainter()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- accroche

  List<Widget> _intro() {
    final t = frame.t;
    final plan = frame.plan;
    final widgets = <Widget>[];
    final scrim = _sstep(0.3, 1.3, t) * (1 - _sstep(2.2, 2.8, t));
    if (scrim > 0) {
      widgets.add(
        Positioned.fill(
          child: Opacity(
            opacity: scrim,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 0.26),
                  radius: 0.9,
                  colors: [
                    Color(0xCC020812),
                    Color(0x6B020812),
                    Color(0x00020812),
                  ],
                  stops: [0, .55, .8],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final out = _sstep(2.2, 2.7, t);
    if (t > 0.3 && out < 1) {
      widgets.add(
        Positioned(
          left: 20,
          right: 20,
          top: 330 - 16 * out,
          child: Opacity(opacity: 1 - out, child: _title(t)),
        ),
      );
    }
    final bug = _sstep(2.5, 3.0, t) *
        (1 - _sstep(plan.moveStart, plan.moveStart + 0.5, t));
    if (bug > 0) {
      widgets
        ..add(
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 150,
            child: Opacity(
              opacity: bug,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xC7020812),
                      Color(0x61020812),
                      Color(0x00020812),
                    ],
                    stops: [0, .55, 1],
                  ),
                ),
              ),
            ),
          ),
        )
        ..add(
          Positioned(
            left: 18 - 14 * (1 - _sstep(2.5, 3.0, t)),
            top: frame.bugTop,
            child: Opacity(opacity: bug, child: _bug()),
          ),
        );
    }
    return widgets;
  }

  Widget _title(double t) {
    final crest = _easeOut((t - 0.35) / 0.6);
    final kick = _easeOut((t - 0.6) / 0.5);
    final teamA = _easeOut((t - 0.75) / 0.55);
    final teamB = _easeOut((t - 0.9) / 0.55);
    final versus = _easeOutBack((t - 1.0) / 0.4);
    final rule = _easeOut((t - 1.15) / 0.7);
    final meta = _easeOut((t - 1.3) / 0.45);
    final kickoffAt = data.kickoffAt;
    final firstLine = [
      if (kickoffAt != null)
        '${AppFormats.weekdayShort(kickoffAt)}. '
            '${kickoffAt.toLocal().day} '
            '${AppFormats.monthShort(kickoffAt)}.',
      if (kickoffAt != null) AppFormats.hourMinute(kickoffAt),
      if (data.typeLabel != null) data.typeLabel!,
    ];
    final venue = data.venue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: crest,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - crest)),
            child: Transform.scale(
              scale: 0.92 + 0.08 * crest,
              child: Image.asset(
                'assets/images/as_grinta_logo.webp',
                width: 84,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Opacity(
          opacity: kick,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - kick)),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoldRule(width: 34),
                SizedBox(width: 12),
                Text(
                  'COMPOSITION',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    letterSpacing: 6,
                    color: AppTheme.accent,
                    shadows: [Shadow(color: Color(0xCC000000), blurRadius: 10)],
                  ),
                ),
                SizedBox(width: 6),
                _GoldRule(width: 34, flipped: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TeamName(name: data.homeName, reveal: teamA),
        const SizedBox(height: 8),
        Opacity(
          opacity: (versus * 2).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: math.max(0.01, versus),
            child: const _AccentChip(label: 'VS'),
          ),
        ),
        const SizedBox(height: 8),
        _TeamName(name: data.awayName, reveal: teamB),
        const SizedBox(height: 12),
        Container(
          width: 240 * rule,
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x00FBE80C), AppTheme.accent, Color(0x00FBE80C)],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: meta,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - meta)),
            child: Column(
              children: [
                if (firstLine.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final (index, part) in firstLine.indexed) ...[
                          if (index > 0)
                            const TextSpan(
                              text: '  /  ',
                              style: TextStyle(color: AppTheme.accent),
                            ),
                          TextSpan(text: part.toUpperCase()),
                        ],
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: _metaStyle,
                  ),
                if (venue != null)
                  Text(
                    venue.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: _metaStyle.copyWith(color: AppTheme.textSecondary),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _metaStyle = TextStyle(
    fontFamily: 'Oswald',
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.6,
    letterSpacing: 3,
    color: Colors.white,
    shadows: [Shadow(color: Color(0xE6000000), blurRadius: 10)],
  );

  Widget _bug() {
    const shadow = [Shadow(color: Color(0xCC000000), blurRadius: 6)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/as_grinta_logo.webp', width: 22),
        const SizedBox(width: 8),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AS GRINTA',
              style: TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                height: 1,
                letterSpacing: 2,
                color: Colors.white,
                shadows: shadow,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'LE ONZE DE DÉPART',
              style: TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w400,
                fontSize: 10,
                height: 1,
                letterSpacing: 2.4,
                color: AppTheme.accent,
                shadows: shadow,
              ),
            ),
          ],
        ),
        if (data.formationCode != null) ...[
          const SizedBox(width: 8),
          _AccentChip(label: data.formationCode!),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- écrans

  PresentationLine? get _currentLine {
    PresentationLine? current;
    for (final line in frame.plan.lines) {
      if (frame.t >= line.start - 0.01 &&
          frame.t < line.start + CompositionPresentationPlan.flyDelay + 0.45) {
        current = line;
      }
    }
    return current;
  }

  List<(double, Widget)> _panel() {
    final line = _currentLine;
    if (line == null) return const [];
    final a = frame.t - line.start;
    const fly = CompositionPresentationPlan.flyDelay;
    final appear = _easeOut(a / 0.35);
    final leave = _sstep(fly, fly + 0.32, a);
    final layout = _PanelLayout(line);
    final height = layout.height;
    final labelIn = _easeOut((a - 0.12) / 0.35);
    final labelOut = _sstep(fly + 0.05, fly + 0.34, a);
    return [
      (
        2400,
        Positioned.fill(
          child: Opacity(
            opacity: (0.75 * appear * (1 - leave)).clamp(0.0, 1.0),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.85,
                  colors: [
                    Color(0xB8020812),
                    Color(0x40020812),
                    Color(0x00020812),
                  ],
                  stops: [0, .7, 1],
                ),
              ),
            ),
          ),
        ),
      ),
      (
        2500,
        Positioned(
          left: 20,
          width: 350,
          top: _panelCenterY - height / 2 + 10,
          height: height,
          child: Opacity(
            opacity: (appear * (1 - leave)).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.94 + 0.06 * appear + 0.03 * leave,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xE6122E54), Color(0xF2061428)],
                  ),
                  border: Border.all(color: const Color(0x666E93F6)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8C000000),
                      blurRadius: 60,
                      offset: Offset(0, 26),
                    ),
                  ],
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: (labelIn * (1 - labelOut)).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - labelIn)),
                            child: Text(
                              line.label.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'Oswald',
                                fontWeight: FontWeight.w400,
                                fontSize: 23,
                                height: 1,
                                letterSpacing: 5,
                                color: AppTheme.accent,
                                shadows: [
                                  Shadow(
                                    color: Color(0x99000000),
                                    blurRadius: 12,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Opacity(
                          opacity: 1 - labelOut,
                          child: Transform.scale(
                            scaleX: _easeOut((a - 0.25) / 0.45),
                            child: const _GoldRule(width: 74, height: 2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Bandeau du bas où se rangent les remplaçants et le coach.
  List<(double, Widget)> _benchBar() {
    final plan = frame.plan;
    final t = frame.t;
    final leave = 1 - _sstep(plan.moveStart, plan.moveStart + 0.5, t);
    final labels = <Widget>[];
    for (final line in plan.lines) {
      if (line.kind.isOnField) continue;
      final shown = _sstep(
            line.start + CompositionPresentationPlan.flyDelay + 0.3,
            line.start + CompositionPresentationPlan.flyDelay + 0.8,
            t,
          ) *
          leave;
      if (shown <= 0) continue;
      final x = line.kind == PresentationLineKind.coach
          ? _coachX
          : _BenchStrip(plan).center;
      labels.add(
        Positioned(
          left: x - 100,
          width: 200,
          top: frame.stripY - 60,
          child: Opacity(
            opacity: shown,
            child: Text(
              line.kind.labelFor(line.people.length).toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w400,
                fontSize: 11,
                height: 1,
                letterSpacing: 3.3,
                color: AppTheme.accent,
              ),
            ),
          ),
        ),
      );
    }
    if (labels.isEmpty) return const [];
    final bench = plan.lines.firstWhere((line) => !line.kind.isOnField);
    final bar = _sstep(
          bench.start + CompositionPresentationPlan.flyDelay + 0.3,
          bench.start + CompositionPresentationPlan.flyDelay + 0.8,
          t,
        ) *
        leave;
    return [
      (
        100,
        Positioned(
          left: 0,
          right: 0,
          top: frame.stripY - 62,
          bottom: -200,
          child: Opacity(
            opacity: bar,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00041224),
                    Color(0xC7041224),
                    Color(0xEB041224)
                  ],
                  stops: [0, .34, 1],
                ),
              ),
            ),
          ),
        ),
      ),
      for (final label in labels) (2550, label),
    ];
  }

  // ------------------------------------------------------------- photos

  List<(double, Widget)> _people(PresentationLine line) {
    final t = frame.t;
    final plan = frame.plan;
    final a = t - line.start;
    if (a < 0.08) return const [];
    const fly = CompositionPresentationPlan.flyDelay;
    const flyDuration = CompositionPresentationPlan.flyDuration;
    final layout = _PanelLayout(line);
    final strip = _BenchStrip(plan);
    final result = <(double, Widget)>[];
    var slot = 0;
    for (final (rowIndex, row) in line.rows.indexed) {
      for (final (column, person) in row.indexed) {
        final index = slot++;
        if (a < 0.08 + index * 0.07) continue;
        final face = faces[person.id];
        if (face == null) continue;
        final panelPoint = layout.center(rowIndex, column, row.length);
        final appear = _easeOut((a - 0.08 - index * 0.07) / 0.32);
        final flight = _inOut((a - fly - index * 0.05) / flyDuration);
        final land =
            ((a - fly - index * 0.05 - flyDuration) / 0.28).clamp(0.0, 1.0);
        final settle = 1 + 0.07 * math.sin(land * math.pi) * (1 - land);
        final panelScale = layout.scale * (0.86 + 0.14 * appear);

        Offset target;
        double targetScale;
        double z;
        var opacity = 1.0;
        if (line.kind.isOnField) {
          final spot = _fieldSpot(person);
          if (spot == null) continue;
          target = spot.offset;
          targetScale = spot.scale;
          z = 1000 + spot.scale * 1000;
        } else {
          target = line.kind == PresentationLineKind.coach
              ? Offset(_coachX, frame.stripY)
              : Offset(strip.x(index), frame.stripY);
          targetScale =
              line.kind == PresentationLineKind.coach ? 1 : strip.scale;
          z = 2600;
          // Remplaçants et coach quittent le bandeau pendant la bascule :
          // l'écran d'arrivée montre le banc à sa place, et pas le coach.
          final leave = _sstep(plan.moveStart, plan.moveStart + 0.35, t);
          opacity = 1 - leave;
          target = target.translate(0, 10 * leave);
        }

        Offset position;
        double scale;
        if (flight >= 1) {
          position = target;
          scale = targetScale * settle;
        } else {
          position = Offset(
            panelPoint.dx + (target.dx - panelPoint.dx) * flight,
            panelPoint.dy +
                (target.dy - panelPoint.dy) * flight -
                math.sin(flight * math.pi) * 26,
          );
          scale = panelScale + (targetScale - panelScale) * flight;
          opacity = appear;
          z = flight > 0 ? 3000 : 3500;
        }
        if (opacity <= 0) continue;
        // Sur l'écran d'arrivée, un joueur sans photo a ses initiales : la
        // silhouette de la vidéo s'efface pendant la bascule.
        final silhouette =
            1 - _sstep(plan.moveStart + 0.3, plan.moveStart + 1.1, t);
        result.add(
          (
            z,
            Positioned(
              left: 0,
              top: 0,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform(
                  transform: Matrix4.identity()
                    ..translateByDouble(position.dx, position.dy, 0, 1)
                    ..scaleByDouble(scale, scale, 1, 1)
                    ..translateByDouble(-32, -42, 0, 1),
                  child: _PresentationTile(
                    face: face,
                    silhouette: line.kind.isOnField ? silhouette : 1,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return result;
  }

  /// Place d'un titulaire : la position de sa vignette sur l'écran
  /// Composition, projetée par la caméra, et sa taille à cet endroit.
  ({Offset offset, double scale})? _fieldSpot(PresentationPerson person) {
    final position = person.position ?? const Offset(.5, .5);
    final width = frame.pitchLayoutWidth;
    final height = width / .68;
    const markerWidth = 64.0, markerHeight = 84.0;
    final x = position.dx.clamp(0.08, 0.92);
    final y = position.dy.clamp(0.06, 0.94);
    final left = (x * width - markerWidth / 2).clamp(0.0, width - markerWidth);
    final top =
        (y * height - markerHeight / 2).clamp(0.0, height - markerHeight);
    final ground = PresentationCamera.groundPoint(
      Offset(left + markerWidth / 2, top + markerHeight / 2),
      Size(width, height),
    );
    final projected = frame.camera.project(ground.$1, ground.$2, ground.$3);
    if (projected == null) return null;
    // Perspective adoucie : au fond du terrain, les vignettes rétrécissent
    // moins que la pelouse, pour rester lisibles.
    final ratio = math.max(projected.scale / frame.landingScale, 1e-3);
    final landed = frame.landing.width / width;
    return (
      offset: projected.offset,
      scale: landed * math.min(math.sqrt(ratio), 2.2),
    );
  }
}

/// Disposition des grandes photos dans l'écran d'une ligne.
class _PanelLayout {
  _PanelLayout(this.line) {
    final perRow = line.rows.fold<int>(0, (m, r) => math.max(m, r.length));
    final rows = line.rows.length;
    final byWidth = (330 - (perRow - 1) * 10) / (64 * perRow);
    final byHeight = (400 - 78 - (rows - 1) * 8) / (84 * rows);
    final cap = perRow <= 1 && rows <= 1 ? 2.4 : 1.9;
    scale = [byWidth, byHeight, cap].reduce(math.min);
    block = rows * 84 * scale + (rows - 1) * 8;
  }

  final PresentationLine line;
  late final double scale;
  late final double block;

  double get height => block + 78;

  Offset center(int row, int column, int count) {
    final top = _panelCenterY - 18 - block / 2;
    return Offset(
      presentationStageSize.width / 2 +
          (column - (count - 1) / 2) * (64 * scale + 10),
      top + row * (84 * scale + 8) + 42 * scale,
    );
  }
}

/// Rangée des remplaçants en bas de l'image, à gauche du coach s'il est là.
class _BenchStrip {
  _BenchStrip(CompositionPresentationPlan plan) {
    final hasCoach =
        plan.lines.any((line) => line.kind == PresentationLineKind.coach);
    final bench = plan.lines
        .where((line) => line.kind == PresentationLineKind.bench)
        .fold<int>(0, (sum, line) => sum + line.people.length);
    final left = 16.0, right = hasCoach ? 286.0 : 374.0;
    center = (left + right) / 2;
    count = math.max(bench, 1);
    spacing = math.min(74.0, (right - left) / count);
    scale = math.min(1.0, (spacing - 4) / 64);
  }

  late final double center;
  late final int count;
  late final double spacing;
  late final double scale;

  double x(int index) => center + (index - (count - 1) / 2) * spacing;
}

// ---------------------------------------------------------------------------
// Vignettes
// ---------------------------------------------------------------------------

class _Face {
  const _Face({
    required this.name,
    this.lastName,
    this.photoUrl,
    this.isGoalkeeper = false,
  });

  final String name;
  final String? lastName;
  final String? photoUrl;
  final bool isGoalkeeper;

  bool get hasPhoto => photoUrl?.trim().isNotEmpty ?? false;
}

/// La vignette de l'écran Composition (case de 64 × 84, photo de 52 sans
/// contour, prénom dessous). Sans photo : une silhouette neutre, qui laisse
/// la place aux initiales de l'appli quand [silhouette] retombe à 0.
class _PresentationTile extends StatelessWidget {
  const _PresentationTile({required this.face, this.silhouette = 1});

  final _Face face;
  final double silhouette;

  @override
  Widget build(BuildContext context) {
    final avatar = PlayerAvatar(
      photoUrl: face.photoUrl,
      name: face.name,
      lastName: face.lastName,
      isGoalkeeper: face.isGoalkeeper,
    );
    return SizedBox(
      width: 64,
      height: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 64,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: face.hasPhoto
                  ? avatar
                  : Stack(
                      children: [
                        if (silhouette < 1) avatar,
                        if (silhouette > 0)
                          Opacity(
                            opacity: silhouette.clamp(0.0, 1.0),
                            child: const SizedBox.square(
                              dimension: 52,
                              child: CustomPaint(painter: _SilhouettePainter()),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 2),
          PitchPlayerName(label: face.name.trim()),
        ],
      ),
    );
  }
}

/// Silhouette neutre détourée, pour un joueur sans photo.
class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFC9D5E4), Color(0xFF8B9DB4)],
    ).createShader(Offset.zero & size);
    final fill = Paint()..shader = shader;
    final body = Path()
      ..moveTo(10 * s, 100 * s)
      ..cubicTo(12 * s, 80 * s, 26 * s, 71 * s, 40 * s, 68 * s)
      ..lineTo(60 * s, 68 * s)
      ..cubicTo(74 * s, 71 * s, 88 * s, 80 * s, 90 * s, 100 * s)
      ..close();
    final neck = Path()
      ..moveTo(42 * s, 54 * s)
      ..lineTo(58 * s, 54 * s)
      ..lineTo(58.5 * s, 70 * s)
      ..quadraticBezierTo(50 * s, 75 * s, 41.5 * s, 70 * s)
      ..close();
    canvas
      ..drawPath(body, fill)
      ..drawPath(neck, Paint()..color = const Color(0xFF9FB0C5))
      ..drawOval(
        Rect.fromCenter(
          center: Offset(50 * s, 38 * s),
          width: 30 * s,
          height: 37 * s,
        ),
        fill,
      );
  }

  @override
  bool shouldRepaint(_SilhouettePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Petits éléments graphiques de l'accroche
// ---------------------------------------------------------------------------

class _TeamName extends StatelessWidget {
  const _TeamName({required this.name, required this.reveal});

  final String name;
  final double reveal;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: FractionalTranslation(
          translation: Offset(0, 1.05 * (1 - reveal)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w400,
                fontSize: 32,
                height: 1,
                letterSpacing: .6,
                color: Colors.white,
                shadows: [Shadow(color: Color(0xBF000000), blurRadius: 22)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentChip extends StatelessWidget {
  const _AccentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _SlantClipper(),
      child: ColoredBox(
        color: AppTheme.accent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 4, 7, 3),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Oswald',
              fontWeight: FontWeight.w400,
              fontSize: 12,
              height: 1,
              letterSpacing: 1.4,
              color: AppTheme.background,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlantClipper extends CustomClipper<Path> {
  const _SlantClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(4, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 4, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_SlantClipper oldClipper) => false;
}

class _GoldRule extends StatelessWidget {
  const _GoldRule({required this.width, this.height = 1, this.flipped = false});

  final double width;
  final double height;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: LinearGradient(
          colors: height > 1
              ? const [Color(0x00FBE80C), AppTheme.accent, Color(0x00FBE80C)]
              : flipped
                  ? const [AppTheme.accent, Color(0x00FBE80C)]
                  : const [Color(0x00FBE80C), AppTheme.accent],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Décor : la vidéo du stade
// ---------------------------------------------------------------------------

/// La vidéo muette du stade, avec son image fixe en attendant (ou à la
/// place, si le téléphone refuse de la lire).
class _StadiumVideo extends StatefulWidget {
  const _StadiumVideo({required this.cue});

  final PresentationCue cue;

  @override
  State<_StadiumVideo> createState() => _StadiumVideoState();
}

class _StadiumVideoState extends State<_StadiumVideo> {
  static const _video = 'assets/composition/stade.mp4';
  static const _poster = 'assets/composition/stade.jpg';

  late final VideoPlayerController _controller = VideoPlayerController.asset(
    _video,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize().timeout(const Duration(seconds: 5));
      // Muette : c'est aussi ce qui permet au navigateur de la lancer seul.
      await _controller.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.cue.playing) unawaited(_controller.play());
    } catch (_) {
      // Pas de vidéo : l'image fixe du stade reste en fond.
    }
    if (mounted) widget.cue.onReady();
  }

  @override
  void didUpdateWidget(_StadiumVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    if (widget.cue.take != oldWidget.cue.take) {
      unawaited(_controller.seekTo(Duration.zero));
      unawaited(_controller.play());
    } else if (widget.cue.playing && !oldWidget.cue.playing) {
      unawaited(_controller.play());
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _controller.value.size;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Image.asset(_poster, fit: BoxFit.cover, gaplessPlayback: true),
        if (_ready && !size.isEmpty)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox.fromSize(
              size: size,
              child: VideoPlayer(_controller),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Courbes
// ---------------------------------------------------------------------------

double _sstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _easeOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return 1 - math.pow(1 - t, 3).toDouble();
}

double _easeOutBack(double x, [double s = 1.9]) {
  final t = x.clamp(0.0, 1.0) - 1;
  return 1 + (s + 1) * t * t * t + s * t * t;
}

double _inOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}
