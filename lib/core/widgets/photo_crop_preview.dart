import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:as_grinta/core/storage/avatar_image.dart';
import 'package:as_grinta/core/widgets/match_contribution_icons.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Ouvre l'éditeur utilisé pour les photos de profil : déplacement libre,
/// pinch-to-zoom / dézoom et export JPEG, ou PNG si la photo a des zones
/// transparentes.
///
/// Un patron est posé sur l'aperçu (ovale du visage, épaules, couronne de
/// l'Homme du match à sa place sur le terrain) pour cadrer tous les joueurs
/// de la même façon. Il n'est jamais enregistré dans l'image.
///
/// L'export est calculé directement depuis l'image source et la matrice de
/// transformation. On ne capture pas le widget à l'écran : cela évite les
/// échecs de RenderRepaintBoundary sur Flutter Web / iOS PWA et garantit un
/// rendu identique à l'aperçu.
Future<Uint8List?> cropProfilePhoto(
  BuildContext context,
  Uint8List bytes, {
  String title = 'Recadrer la photo',
  String instructions = 'Déplace et pince pour zoomer : le visage dans '
      'l’ovale, du haut du front au menton.',
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

  /// Écart entre le bord du cadre coloré et la photo : la marge intérieure
  /// de 6 plus le filet de 1.
  static const double _frameInset = 7;

  /// Le rendu est calculé à la taille de stockage, pas à un multiple arbitraire
  /// de l'aperçu : c'est ce qui décide du poids réel de la photo à télécharger.
  static const double _exportScale = avatarStorageSide / _cropSize;

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
    // Pas de fond peint : une photo détourée garde sa transparence, comme une
    // zone laissée découverte par le cadrage (voir encodeAvatar).
    canvas.transform(_transformationController.value.storage);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _childWidth, _childHeight),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );

    final picture = recorder.endRecording();
    const side = avatarStorageSide;
    final output = await picture.toImage(side, side);
    // dart:ui ne sait encoder que du PNG, sans perte : les avatars pesaient
    // 171 à 250 ko pièce, soit ~2,5 Mo pour une composition de onze joueurs.
    // On récupère donc les pixels bruts et on les encode en JPEG, sauf photo
    // transparente (voir encodeAvatar).
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
    return encodeAvatar(unpremultiplyAlpha(raw));
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
    final crownTop = _frameInset + PhotoCrown.topOffset(_cropSize);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Une seule consigne, sans note en dessous : avec la place de la
          // couronne, la fenêtre doit encore tenir sur un petit écran.
          Text(
            '${widget.instructions} Ovale, couronne et fond ne sont pas '
            'enregistrés.',
            textAlign: TextAlign.center,
          ),
          // La couronne dépasse au-dessus de l'aperçu, comme sur le terrain :
          // son dessin monte à environ 22 % du côté de la photo au-dessus
          // d'elle (le haut de la boîte de l'emoji, plus haut, est vide). Sa
          // place est réservée, sans plus : un petit écran doit tout afficher.
          const SizedBox(height: 6 + _cropSize * .22 - _frameInset),
          Stack(
            clipBehavior: Clip.none,
            children: [
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
                              transformationController:
                                  _transformationController,
                              constrained: false,
                              boundaryMargin:
                                  const EdgeInsets.all(_cropSize * 4),
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
              // Le patron laisse passer les gestes jusqu'à la photo.
              Positioned(
                top: crownTop,
                left: 0,
                right: 0,
                child: const IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: .8,
                      child: PhotoCrown(photoSize: _cropSize),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _frameInset,
                top: _frameInset,
                width: _cropSize,
                height: _cropSize,
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_cropSize * 0.25),
                    child: const CustomPaint(painter: _FramingGuidePainter()),
                  ),
                ),
              ),
            ],
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

/// Patron de cadrage, en pointillés : un ovale pour le visage, du haut du
/// front (13 % du côté de la photo) au menton (55 %), et la ligne des
/// épaules.
///
/// Sur le terrain, la couronne descend jusqu'à 20 % de la photo : sur un
/// visage cadré dans l'ovale, elle couvre le haut du front, comme portée.
/// Le visage occupe à peu près la même place que sur la plupart des photos
/// déjà en ligne, assez grand pour qu'on reconnaisse le joueur.
class _FramingGuidePainter extends CustomPainter {
  const _FramingGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final face = Path()
      ..addOval(Rect.fromLTRB(w * .33, h * .13, w * .67, h * .55));
    final shoulders = Path()
      ..moveTo(0, h * .84)
      ..cubicTo(w * .06, h * .74, w * .20, h * .69, w * .39, h * .655)
      ..moveTo(w, h * .84)
      ..cubicTo(w * .94, h * .74, w * .80, h * .69, w * .61, h * .655);
    final dashes = _dashed(face)..addPath(_dashed(shoulders), Offset.zero);
    // Un liseré sombre sous le trait blanc : le patron reste visible sur un
    // maillot clair comme sur un fond sombre.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = const Color(0x59000000);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5
      ..color = const Color(0xE6FFFFFF);
    canvas
      ..drawPath(dashes, halo)
      ..drawPath(dashes, line);
  }

  static Path _dashed(Path source) {
    final dashes = Path();
    for (final metric in source.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 10) {
        dashes.addPath(metric.extractPath(start, start + 6), Offset.zero);
      }
    }
    return dashes;
  }

  @override
  bool shouldRepaint(_FramingGuidePainter oldDelegate) => false;
}
