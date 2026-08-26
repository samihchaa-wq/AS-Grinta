import 'package:as_grinta/features/season_wrapped/data/season_wrapped_repository.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_slides.dart';
import 'package:as_grinta/features/season_wrapped/presentation/wrapped_theme.dart';
import 'package:flutter/material.dart';

/// Taille logique des images partagées. Capturées à trois fois cette taille,
/// elles sortent en 1080 × 1350, le format portrait des messageries.
const double kSeasonWrappedShareWidth = 360;
const double kSeasonWrappedShareHeight = 450;
const double kSeasonWrappedSharePixelRatio = 3;

/// En-tête commun aux images partagées.
class _ShareHeader extends StatelessWidget {
  const _ShareHeader({
    required this.skin,
    required this.seasonName,
    required this.title,
  });

  final WrappedSkin skin;
  final String seasonName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 4, width: 40, color: skin.figure),
        const SizedBox(height: 10),
        Text(
          'AS GRINTA · $seasonName',
          style: WrappedType.label(skin.muted, size: 11),
        ),
        const SizedBox(height: 6),
        Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WrappedType.title(skin.text, size: 32),
        ),
      ],
    );
  }
}

class _ShareSignature extends StatelessWidget {
  const _ShareSignature({required this.skin, required this.playerName});

  final WrappedSkin skin;
  final String? playerName;

  @override
  Widget build(BuildContext context) {
    if (playerName == null || playerName!.isEmpty) return const SizedBox();
    return Text(
      playerName!.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WrappedType.title(skin.figure, size: 22),
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

  /// Une image par thème, chacune son habillage : trois images identiques
  /// n'auraient aucune raison d'être partagées séparément.
  WrappedSkin get _skin => switch (sheet.title) {
        'Ma présence' => WrappedSkin.night,
        'Mon apport' => WrappedSkin.flash,
        _ => WrappedSkin.deep,
      };

  @override
  Widget build(BuildContext context) {
    final skin = _skin;

    return SizedBox(
      width: kSeasonWrappedShareWidth,
      height: kSeasonWrappedShareHeight,
      child: WrappedBackdrop(
        skin: skin,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShareHeader(
                skin: skin,
                seasonName: seasonName,
                title: sheet.title,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final stat in sheet.stats)
                      _ShareStatLine(stat: stat, skin: skin),
                  ],
                ),
              ),
              _ShareSignature(skin: skin, playerName: playerName),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareStatLine extends StatelessWidget {
  const _ShareStatLine({required this.stat, required this.skin});

  final SeasonWrappedStat stat;
  final WrappedSkin skin;

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
                style: WrappedType.label(skin.muted, size: 10),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  stat.value,
                  // L'interlignage serre des chiffres geants faisait remonter
                  // le chiffre par-dessus son intitule.
                  style: WrappedType.figure(
                    skin.figure,
                    size: 54,
                  ).copyWith(height: 1),
                ),
              ),
            ],
          ),
        ),
        if (stat.isRanked) ...[
          const SizedBox(width: 10),
          WrappedRankBadge(rank: stat.rank!, skin: skin, size: 13),
        ],
      ],
    );
  }
}

/// La saison entière : les neuf critères sur une seule image.
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
    const skin = WrappedSkin.night;

    return SizedBox(
      width: kSeasonWrappedShareWidth,
      height: kSeasonWrappedShareHeight,
      child: WrappedBackdrop(
        skin: skin,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShareHeader(
                skin: skin,
                seasonName: wrapped.seasonName,
                title: 'Ma saison',
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final stat in wrapped.stats)
                      WrappedRecapLine(stat: stat, skin: skin, dense: true),
                  ],
                ),
              ),
              _ShareSignature(skin: skin, playerName: playerName),
            ],
          ),
        ),
      ),
    );
  }
}
