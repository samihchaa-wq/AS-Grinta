import 'package:as_grinta/features/badges/presentation/badge_descriptor.dart';
import 'package:flutter/material.dart';

/// Proportions des zones de l'emblème, rapportées à sa largeur.
const kBadgeIllustrationRatio = 0.97;
const _valueRatio = 0.21;
const _lineRatio = 0.15;

/// Hauteur du socle sous l'illustration. Elle est la même pour tous les
/// emblèmes : celle d'un badge complet (nombre, critère, temporalité). Un
/// badge sans nombre donne cette place à son titre, qui peut alors passer à la
/// ligne au lieu d'être rétréci.
const _socleRatio = _valueRatio + 2 * _lineRatio;

/// Taille d'une étoile de palmarès, rapportée à la largeur de l'emblème.
const kBadgeEmblemStarRatio = 0.2;

/// Ce que les étoiles débordent au-dessus du rectangle : la moitié de leur
/// hauteur, l'autre moitié mordant sur l'illustration.
const kBadgeEmblemStarOverhangRatio = kBadgeEmblemStarRatio / 2;

/// Hauteur totale de l'emblème pour une largeur de 1, débord des étoiles
/// compris.
///
/// Le rectangle a toujours la même hauteur, avec ou sans nombre : seules les
/// étoiles de palmarès ajoutent leur débord au-dessus.
double badgeEmblemHeightRatio({bool hasStar = false}) {
  return (hasStar ? kBadgeEmblemStarOverhangRatio : 0) +
      kBadgeIllustrationRatio +
      _socleRatio;
}

Color _shiftBadgeTone(Color color, double lightnessDelta) {
  final hsl = HSLColor.fromColor(color);
  final shifted = hsl.lightness + lightnessDelta;
  final lightness = shifted.clamp(0.0, 1.0).toDouble();
  return hsl.withLightness(lightness).toColor();
}

/// Contraste minimal entre le texte blanc du socle et le socle lui-même.
const _minSocleContrast = 3.5;

double _contrastWithWhite(Color color) =>
    1.05 / (color.computeLuminance() + 0.05);

/// La teinte du socle : la couleur de l'emblème, nettement assombrie.
///
/// Une couleur très claire, comme le bleu diamant des titres de fin de
/// saison, laisserait un socle trop pâle pour son texte blanc : il est alors
/// foncé par petits pas, dans la même teinte, jusqu'à être lisible. Les
/// autres couleurs ne bougent pas.
Color _socleTone(Color base) {
  var tone = _shiftBadgeTone(base, -0.24);
  while (_contrastWithWhite(tone) < _minSocleContrast) {
    tone = _shiftBadgeTone(tone, -0.02);
  }
  return tone;
}

/// Le corps de l'emblème : un seul rectangle, découpé en zones jointives.
///
/// L'illustration et le socle texte restent dans la même famille de couleur,
/// avec un socle très nettement plus sombre pour distinguer immédiatement les
/// deux parties. Le texte est peint en blanc avec un contour noir afin de
/// rester lisible quelle que soit la couleur choisie pour l'emblème.
class BadgeEmblemBody extends StatelessWidget {
  const BadgeEmblemBody({
    super.key,
    required this.child,
    required this.size,
    required this.base,
    required this.descriptor,
    this.value,
  });

  final Widget child;
  final double size;
  final Color base;
  final BadgeDescriptor descriptor;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.isNotEmpty == true;
    final period = descriptor.period;
    final illustrationTone = _shiftBadgeTone(base, 0.02);
    final bandsTone = _socleTone(base);
    // Le critère prend tout ce que le nombre et la temporalité laissent du
    // socle : une ligne sur un badge complet, bien plus sur un badge sans
    // nombre.
    final labelRatio = switch ((hasValue, period != null)) {
      (true, true) => _lineRatio,
      (true, false) => 2 * _lineRatio,
      (false, true) => _valueRatio + _lineRatio,
      (false, false) => _socleRatio,
    };

    return Container(
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bandsTone,
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: size * kBadgeIllustrationRatio,
            width: size,
            color: illustrationTone,
            alignment: Alignment.center,
            child: child,
          ),
          if (hasValue)
            _Band(
              height: size * _valueRatio,
              color: bandsTone,
              child: _BandText(
                value!,
                fontSize: size * 0.16,
                color: Colors.white,
                letterSpacing: 0,
              ),
            ),
          _Band(
            height: size * labelRatio,
            color: bandsTone,
            child: hasValue
                ? _BandText(
                    descriptor.label,
                    fontSize: size * 0.095,
                    color: Colors.white,
                  )
                : _TitleText(
                    descriptor.label,
                    width: size * (1 - 2 * _titleInsetRatio),
                    height: size * (labelRatio - _titleInsetRatio),
                    fontSize: size * 0.14,
                    color: Colors.white,
                  ),
          ),
          if (period != null)
            _Band(
              height: size * _lineRatio,
              color: bandsTone,
              child: _BandText(
                period,
                fontSize: size * 0.095,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

/// Une bande pleine largeur de l'emblème, collée à celle du dessus.
class _Band extends StatelessWidget {
  const _Band({required this.height, required this.color, required this.child});

  final double height;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      color: color,
      child: child,
    );
  }
}

/// Texte d'une bande : réduit pour tenir dans la largeur, jamais tronqué.
///
/// Deux couches strictement superposées sont rendues : une première en trait
/// noir, puis le texte blanc par-dessus. Le contour suit donc exactement les
/// chiffres et lettres sans modifier leur métrique ni la taille du badge.
class _BandText extends StatelessWidget {
  const _BandText(
    this.text, {
    required this.fontSize,
    required this.color,
    this.letterSpacing = 0.2,
  });

  final String text;
  final double fontSize;
  final Color color;
  final double letterSpacing;

  TextStyle _style({Color? fill, Paint? foreground}) {
    return TextStyle(
      color: fill,
      foreground: foreground,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: letterSpacing,
      height: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = fontSize * 0.16
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Text(
            text,
            maxLines: 1,
            style: _style(foreground: outline),
          ),
          Text(text, maxLines: 1, style: _style(fill: color)),
        ],
      ),
    );
  }
}

/// Marge laissée autour d'un titre sur plusieurs lignes, pour qu'il ne morde
/// pas sur les coins arrondis de l'emblème.
const _titleInsetRatio = 0.07;

/// Titre d'un badge sans nombre : il occupe tout le socle et passe à la ligne
/// entre deux mots au lieu d'être rétréci sur une seule ligne.
///
/// Le texte part de [fontSize] et ne diminue que s'il ne tient pas dans
/// [width] × [height] en trois lignes au plus, sans couper un mot. Comme dans
/// [_BandText], un trait noir est peint sous le remplissage blanc.
class _TitleText extends StatelessWidget {
  const _TitleText(
    this.text, {
    required this.width,
    required this.height,
    required this.fontSize,
    required this.color,
  });

  final String text;
  final double width;
  final double height;
  final double fontSize;
  final Color color;

  static const _maxLines = 3;

  TextStyle _style(double size, {Color? fill, Paint? foreground}) {
    return TextStyle(
      color: fill,
      foreground: foreground,
      fontSize: size,
      fontWeight: FontWeight.w400,
      // Proportionnel à la taille : la largeur du texte suit alors exactement
      // sa taille, ce qui permet de la calculer d'un coup.
      letterSpacing: size * 0.015,
      height: 1.05,
    );
  }

  TextPainter _layout(String value, TextStyle style, TextDirection direction) {
    return TextPainter(
      text: TextSpan(text: value, style: style),
      textAlign: TextAlign.center,
      textDirection: direction,
      maxLines: _maxLines,
    )..layout(maxWidth: width);
  }

  /// La plus grande taille, au plus [fontSize], à laquelle le titre tient.
  double _fittedSize(TextStyle inherited, TextDirection direction) {
    // Un mot plus large que le badge serait coupé en plein milieu : le plus
    // long fixe donc une première limite, calculée d'un coup.
    var widestWord = '';
    var widestWidth = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: inherited.merge(_style(fontSize))),
        textDirection: direction,
        maxLines: 1,
      )..layout();
      if (painter.width > widestWidth) {
        widestWidth = painter.width;
        widestWord = word;
      }
      painter.dispose();
    }
    var size =
        widestWidth > width ? fontSize * width / widestWidth * 0.98 : fontSize;

    // Puis le titre entier doit tenir en trois lignes dans la hauteur du
    // socle, sans que le mot le plus long ne soit coupé.
    for (var attempt = 0; attempt < 40; attempt++) {
      final style = inherited.merge(_style(size));
      final whole = _layout(text, style, direction);
      final word = _layout(widestWord, style, direction);
      final fits = !whole.didExceedMaxLines &&
          whole.height <= height &&
          word.computeLineMetrics().length <= 1;
      whole.dispose();
      word.dispose();
      if (fits) break;
      size *= 0.92;
    }
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final size = _fittedSize(inherited, direction);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.16
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black;

    // RichText plutôt que Text : le rendu reprend exactement le style mesuré
    // ci-dessus, sans agrandissement ni graisse ajoutés par les réglages
    // d'accessibilité, qui feraient déborder le titre de son socle.
    Widget layer(TextStyle style) => RichText(
          text: TextSpan(text: text, style: inherited.merge(style)),
          textAlign: TextAlign.center,
          textDirection: direction,
          maxLines: _maxLines,
          overflow: TextOverflow.clip,
        );

    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          layer(_style(size, foreground: outline)),
          layer(_style(size, fill: color)),
        ],
      ),
    );
  }
}
