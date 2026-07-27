import 'package:flutter/material.dart';

/// Affiche une rencontre au format vertical : équipe à domicile au-dessus,
/// équipe à l'extérieur en dessous, chacune avec son score si le match est
/// terminé.
///
/// Les scores sont colorés selon le résultat d'AS Grinta : vert si elle gagne,
/// rouge si elle perd, orange en cas de nul.
class MatchFixture extends StatelessWidget {
  const MatchFixture({
    super.key,
    required this.homeName,
    required this.awayName,
    required this.grintaIsHome,
    this.homeScore,
    this.awayScore,
    this.finished = false,
    this.foreground,
    this.nameStyle,
    this.scoreFontSize = 22,
    this.textAlign = TextAlign.start,
  });

  final String homeName;
  final String awayName;
  final bool grintaIsHome;
  final int? homeScore;
  final int? awayScore;
  final bool finished;
  final Color? foreground;
  final TextStyle? nameStyle;
  final double scoreFontSize;
  final TextAlign textAlign;

  static const Color _won = Color(0xFF3BD16F);
  static const Color _lost = Color(0xFFE5555A);
  static const Color _draw = Color(0xFFE9963C);

  static Color resultColor(int grintaScore, int opponentScore) {
    if (grintaScore > opponentScore) return _won;
    if (grintaScore < opponentScore) return _lost;
    return _draw;
  }

  bool get _hasScores => finished && homeScore != null && awayScore != null;

  Color? get _scoreColor {
    if (!_hasScores) return null;
    final grinta = grintaIsHome ? homeScore! : awayScore!;
    final opponent = grintaIsHome ? awayScore! : homeScore!;
    return resultColor(grinta, opponent);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseName = (nameStyle ??
            Theme.of(context).textTheme.titleMedium ??
            const TextStyle())
        .copyWith(fontWeight: FontWeight.w800, color: foreground);
    final scoreColor = _scoreColor;

    Widget line(String name, int? score) {
      final scoreText = '$score';
      return Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: baseName,
            ),
          ),
          if (_hasScores) ...[
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .9, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                scoreText,
                key: ValueKey(scoreText),
                style: baseName.copyWith(
                  color: scoreColor,
                  fontWeight: FontWeight.w900,
                  fontSize: scoreFontSize,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(homeName, homeScore),
        const SizedBox(height: 8),
        line(awayName, awayScore),
      ],
    );
  }
}
