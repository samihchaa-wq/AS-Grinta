part of 'composition_presentation.dart';

class _PageCoverPainter extends CustomPainter {
  const _PageCoverPainter({
    required this.page,
    required this.area,
    required this.areaRect,
  });

  /// Opacité du voile sur la page, et sur le bloc terrain + remplaçants.
  final double page;
  final double area;
  final Rect? areaRect;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final paint = Paint();
    final hole = areaRect;
    if (hole == null) {
      paint.color = AppTheme.background.withValues(alpha: page.clamp(0, 1));
      canvas.drawRect(screen, paint);
      return;
    }
    paint.color = AppTheme.background.withValues(alpha: page.clamp(0, 1));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(screen),
        Path()..addRect(hole),
      ),
      paint,
    );
    paint.color = AppTheme.background.withValues(alpha: area.clamp(0, 1));
    canvas.drawRect(hole, paint);
  }

  @override
  bool shouldRepaint(_PageCoverPainter old) =>
      old.page != page || old.area != area || old.areaRect != areaRect;
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

/// Disposition des grandes photos dans l'écran d'une ligne.
class _PanelLayout {
  _PanelLayout(this.line) {
    final perRow = line.rows.fold<int>(0, (m, r) => math.max(m, r.length));
    final rows = line.rows.length;
    final byWidth = (330 - (perRow - 1) * 10) / (_tileWidth * perRow);
    final byHeight = (400 - 78 - (rows - 1) * 8) / (_tileHeight * rows);
    final cap = perRow <= 1 && rows <= 1 ? 2.2 : 1.8;
    scale = [byWidth, byHeight, cap].reduce(math.min);
    block = rows * _tileHeight * scale + (rows - 1) * 8;
  }

  final PresentationLine line;
  late final double scale;
  late final double block;

  double get height => block + 78;

  Offset center(int row, int column, int count) {
    final top = _panelCenterY - 18 - block / 2;
    return Offset(
      presentationStageSize.width / 2 +
          (column - (count - 1) / 2) * (_tileWidth * scale + 10),
      top + row * (_tileHeight * scale + 8) + _tileHeight / 2 * scale,
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
    scale = math.min(1.0, (spacing - 4) / _tileWidth);
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

/// La vignette de l'écran Composition (même case, même photo sans contour,
/// prénom dessous). Sans photo : une silhouette neutre, qui laisse
/// la place aux initiales de l'appli quand [silhouette] retombe à 0.
class _PresentationTile extends StatelessWidget {
  const _PresentationTile({required this.face, this.silhouette = 1});

  final _Face face;
  final double silhouette;

  @override
  Widget build(BuildContext context) {
    const photoSize = CompositionPlayerTile.photoSize;
    final avatar = PlayerAvatar(
      photoUrl: face.photoUrl,
      name: face.name,
      lastName: face.lastName,
      isGoalkeeper: face.isGoalkeeper,
      size: photoSize,
    );
    return SizedBox(
      width: _tileWidth,
      height: _tileHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 62,
            height: photoSize + 12,
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
                              dimension: photoSize,
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
