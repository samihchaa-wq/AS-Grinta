import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_paper.dart';
import 'package:flutter/material.dart';

/// Taille logique des images partagées. Capturées à trois fois cette taille,
/// elles sortent en 1080 × 1350, le format portrait des messageries.
const double kSeasonWrappedShareWidth = 360;
const double kSeasonWrappedShareHeight = 450;
const double kSeasonWrappedSharePixelRatio = 3;

/// « 1er », puis « 2e », « 3e »…
String seasonWrappedOrdinal(int rank) => rank == 1 ? '1er' : '${rank}e';

/// En-tête commun aux images partagées.
class _ShareHeader extends StatelessWidget {
  const _ShareHeader({required this.seasonName, required this.title});

  final String seasonName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AS GRINTA · FEUILLE DE SAISON',
            style: WrappedPaper.label(size: 9)),
        const SizedBox(height: 5),
        Container(height: 1.4, color: WrappedPaper.ink.withValues(alpha: .25)),
        const SizedBox(height: 14),
        Text(title, style: WrappedPaper.title(size: 27)),
        const SizedBox(height: 2),
        Text(
          'Saison $seasonName',
          style: WrappedPaper.body(size: 11, color: WrappedPaper.inkSoft),
        ),
      ],
    );
  }
}

class _ShareSignature extends StatelessWidget {
  const _ShareSignature({required this.playerName});

  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const WrappedStamp(text: 'Vu et approuvé', size: 10, angle: -.1),
        const Spacer(),
        if (playerName != null && playerName!.isNotEmpty)
          Flexible(
            child: Text(
              playerName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WrappedPaper.body(size: 13).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// Une feuille thématique, telle qu'elle part en photo.
///
/// Elle est dessinée hors écran puis capturée : elle ne dépend d'aucune
/// contrainte de l'écran qui l'affiche, et rend le même visuel sur tous les
/// téléphones.
class SeasonWrappedShareSheet extends StatelessWidget {
  const SeasonWrappedShareSheet({
    super.key,
    required this.sheet,
    required this.seasonName,
    required this.playerName,
  });

  final SeasonWrappedSheet sheet;
  final String seasonName;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kSeasonWrappedShareWidth,
      height: kSeasonWrappedShareHeight,
      child: WrappedPaperBackground(
        seed: sheet.title.length,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 26, 26, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShareHeader(seasonName: seasonName, title: sheet.title),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final stat in sheet.stats) _ShareStatLine(stat: stat),
                  ],
                ),
              ),
              _ShareSignature(playerName: playerName),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareStatLine extends StatelessWidget {
  const _ShareStatLine({required this.stat});

  final SeasonWrappedStat stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WrappedPaper.label(size: 9),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(stat.value, style: WrappedPaper.figure(size: 40)),
              ),
            ],
          ),
        ),
        if (stat.isRanked) ...[
          const SizedBox(width: 10),
          WrappedStamp(text: seasonWrappedOrdinal(stat.rank!), size: 11),
        ],
      ],
    );
  }
}

/// La feuille complète : les neuf critères sur une seule image.
class SeasonWrappedFullShareSheet extends StatelessWidget {
  const SeasonWrappedFullShareSheet({
    super.key,
    required this.wrapped,
    required this.playerName,
  });

  final SeasonWrapped wrapped;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kSeasonWrappedShareWidth,
      height: kSeasonWrappedShareHeight,
      child: WrappedPaperBackground(
        seed: 42,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 26, 26, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShareHeader(seasonName: wrapped.seasonName, title: 'Ma saison'),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final stat in wrapped.stats)
                      _ShareRecapLine(stat: stat),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _ShareSignature(playerName: playerName),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareRecapLine extends StatelessWidget {
  const _ShareRecapLine({required this.stat});

  final SeasonWrappedStat stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 7,
          child: Text(
            stat.shortLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WrappedPaper.body(size: 10),
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: WrappedPaper.ink.withValues(alpha: .22),
                  ),
                ),
              ),
              child: const SizedBox(height: 9, width: double.infinity),
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: Text(
            stat.value,
            maxLines: 1,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: WrappedPaper.body(size: 11).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            stat.isRanked ? seasonWrappedOrdinal(stat.rank!) : '',
            textAlign: TextAlign.right,
            style: WrappedPaper.label(size: 10, color: WrappedPaper.stamp),
          ),
        ),
      ],
    );
  }
}
