part of 'composition_presentation.dart';

const double _panelCenterY = 418;

/// Case d'un joueur, identique à celle de l'écran Composition.
const double _tileWidth = CompositionPitch.markerWidth;
const double _tileHeight = CompositionPitch.markerHeight;
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
    final backgroundOpacity =
        1 - _sstep(plan.moveStart + 0.2, plan.flatAt - 0.5, t);
    // Au départ, la vidéo reste pleinement affichée : un iPhone ne lance pas
    // une vidéo invisible. C'est un voile posé dessus qui s'efface.
    final veil = 1 - _sstep(0, 0.6, t);
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
                  Opacity(
                    opacity: veil,
                    child: const ColoredBox(color: AppTheme.background),
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
                    ..translateByDouble(
                        -_tileWidth / 2, -_tileHeight / 2, 0, 1),
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
    const markerWidth = _tileWidth, markerHeight = _tileHeight;
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
