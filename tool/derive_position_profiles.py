#!/usr/bin/env python3
"""Dérive les profils de postes des joueurs depuis l'archive du club.

L'archive (« AS Grinta — Archives 2013-2026 », relevée sur SportEasy) est un
fichier HTML conservé hors du dépôt : il contient les compositions réellement
alignées, chaque titulaire portant sa position sur le terrain et son rôle.

Ce script projette chacun de ces placements sur les 22 postes de la feuille de
match de l'application, pondère les saisons par récence, puis écrit le fichier
Dart `lib/features/sports_management/domain/player_position_profiles.dart`.

Usage :
    python3 tool/derive_position_profiles.py chemin/vers/archives.html

Le fichier Dart produit est le socle des postes, pas leur état final :
l'application y ajoute au vol les compositions réellement alignées depuis, de
sorte qu'un joueur qui change de poste voit son profil suivre. Il n'existe
aucune saisie manuelle de poste, ni dans l'application ni en base.
"""

import json
import math
import pathlib
import re
import sys
import unicodedata
from collections import defaultdict

# Les 22 postes de la feuille de match, avec leur position normalisée.
# Doit rester aligné sur `matchSheetSlots` dans football_formation.dart.
SLOTS = {
    'GB': (.50, .85),
    'DG': (.10, .65), 'DCG': (.32, .70), 'DC': (.50, .72),
    'DCD': (.68, .70), 'DD': (.90, .65),
    'MDG': (.30, .50), 'MDC': (.50, .53), 'MDD': (.70, .50),
    'MG': (.10, .38), 'MCG': (.34, .38), 'MC': (.50, .40),
    'MCD': (.66, .38), 'MD': (.90, .38),
    'AG': (.12, .22), 'MOG': (.32, .25), 'MOC': (.50, .27),
    'MOD': (.68, .25), 'AD': (.88, .22),
    'BUG': (.35, .10), 'BU': (.50, .08), 'BUD': (.65, .10),
}

# Une saison démarre en juillet.
SEASON_START_MONTH = 7
# Saison de référence de la pondération : la plus récente de l'archive.
# Un match pesant 2× moins tous les deux ans, une saison vieille de 6 ans
# compte pour un huitième d'une saison en cours.
HALF_LIFE_SEASONS = 2.0
# Sous ce nombre de titularisations, l'échantillon ne dit rien de fiable.
MIN_APPEARANCES = 3
# Un poste représentant moins de 4 % du temps du joueur est du bruit.
MIN_SHARE = .04
# Au-delà de six postes, la queue de distribution n'apporte plus rien.
MAX_SLOTS_PER_PLAYER = 6
# Un joueur dont le poste principal pèse moins que ce seuil n'a pas de poste
# de référence : c'est un polyvalent, que la simulation utilise en ajustement.
VERSATILE_THRESHOLD = .30

PLACEHOLDER_NAME = 'Poste laissé vide'
IDENTITY_MAP = pathlib.Path(__file__).parent / 'player_identity_map.json'
OUTPUT = (
    pathlib.Path(__file__).parent.parent
    / 'lib/features/sports_management/domain/player_position_profiles.dart'
)

PION = re.compile(
    r'<span class="pion[^"]*" style="left:([\d.]+)%;top:([\d.]+)%" '
    r'title="([^"]*)">'
)
ARTICLE = re.compile(r'<article class="match.*?</article>', re.S)
KICKOFF = re.compile(r'datetime="(\d{4})-(\d{2})')


def strip_accents(value):
    decomposed = unicodedata.normalize('NFD', value)
    return ''.join(c for c in decomposed if unicodedata.category(c) != 'Mn')


def nearest_slot(x, y):
    return min(
        SLOTS.items(),
        key=lambda item: (item[1][0] - x) ** 2 + (item[1][1] - y) ** 2,
    )[0]


def read_placements(html):
    """(nom, poste, saison, date) de chaque titulaire de chaque compo."""
    for article in ARTICLE.findall(html):
        kickoff = KICKOFF.search(article)
        if not kickoff:
            continue
        year, month = int(kickoff.group(1)), int(kickoff.group(2))
        season = year if month >= SEASON_START_MONTH else year - 1
        played_on = re.search(r'datetime="([\d-]+)"', article).group(1)
        for left, top, title in PION.findall(article):
            if '—' not in title:
                continue
            name = title.split('—', 1)[0].strip()
            if name == PLACEHOLDER_NAME:
                continue
            yield (
                name,
                nearest_slot(float(left) / 100, float(top) / 100),
                season,
                played_on,
            )


def build_profiles(html, identities):
    placements = defaultdict(list)
    coverage_end = ''
    for name, slot, season, played_on in read_placements(html):
        placements[name].append((slot, season))
        coverage_end = max(coverage_end, played_on)

    latest = max(
        season for entries in placements.values() for _, season in entries
    )

    unknown = []
    profiles = []
    for name, entries in sorted(placements.items()):
        if len(entries) < MIN_APPEARANCES:
            continue
        player_ids = identities.get(name)
        if not player_ids:
            unknown.append((name, len(entries)))
            continue

        # Poids absolus, ancrés sur la saison de référence : la suite de
        # l'historique, lue en base, s'y ajoute avec la même formule.
        weighted = defaultdict(float)
        for slot, season in entries:
            weighted[slot] += .5 ** ((latest - season) / HALF_LIFE_SEASONS)
        total = sum(weighted.values())

        samples = sorted(weighted.items(), key=lambda kv: (-kv[1], kv[0]))
        samples = [
            (slot, weight)
            for slot, weight in samples[:MAX_SLOTS_PER_PLAYER]
            if weight / total >= MIN_SHARE
        ]
        seasons = sorted({season for _, season in entries})
        profiles.append({
            'name': name,
            'player_ids': player_ids,
            'appearances': len(entries),
            'first_season': seasons[0],
            'last_season': seasons[-1],
            'samples': samples,
            'total': total,
        })

    return profiles, latest, coverage_end, unknown


def dart_string(value):
    return "'" + value.replace('\\', r'\\').replace("'", r"\'") + "'"


def render(profiles, latest, coverage_end, source):
    lines = [
        '// GÉNÉRÉ — ne pas modifier à la main sans le vouloir.',
        '// Produit par `python3 tool/derive_position_profiles.py '
        '<archive.html>`',
        f'// Source : {source}',
        '//',
        "// Postes de référence des joueurs, dérivés des compositions "
        'réellement',
        "// alignées par le club. Chaque titularisation archivée est projetée "
        'sur le',
        '// poste le plus proche de la feuille de match, puis les saisons sont',
        f'// pondérées par récence (demi-vie {HALF_LIFE_SEASONS:.0f} saisons, '
        f'référence {latest}-{latest + 1}).',
        '//',
        "// C'est le socle des postes, pas leur état final : l'application y "
        'ajoute',
        '// les compositions réellement alignées depuis, avec le poids de leur',
        '// saison. Aucune saisie manuelle de poste nulle part.',
        '',
        'library;',
        '',
        '/// Saison de référence de la pondération.',
        '///',
        "/// Les poids de ce fichier y sont ancrés : l'historique lu en base "
        'est',
        '/// pondéré avec la même formule et le même ancrage, pour que les deux',
        "/// sources s'additionnent sans se déformer.",
        f'const int kPositionProfilesReferenceSeason = {latest};',
        '',
        "/// Nombre de saisons au bout duquel une titularisation ne pèse plus "
        'que',
        '/// la moitié.',
        f'const double kPositionProfilesHalfLifeSeasons = '
        f'{HALF_LIFE_SEASONS};',
        '',
        "/// Dernière composition couverte par l'archive.",
        '///',
        '/// Tout ce qui précède cette date est déjà compté ici : reprendre ces',
        '/// matchs depuis la base les compterait deux fois.',
        f'final DateTime kPositionProfilesCoverageEnd = '
        f'DateTime.utc({coverage_end[:4]}, {int(coverage_end[5:7])}, '
        f'{int(coverage_end[8:10])});',
        '',
        "/// Un poste occupé par un joueur, et le poids de ses passages "
        'à ce poste.',
        'class PlayerPositionSample {',
        '  const PlayerPositionSample(this.slotLabel, this.weight);',
        '',
        '  /// Étiquette du poste, telle que `matchSheetSlots` la nomme.',
        '  final String slotLabel;',
        '',
        '  /// Somme pondérée de ses titularisations à ce poste. La valeur est',
        "  /// absolue, pas un pourcentage : c'est ce qui permet d'y ajouter "
        'les',
        '  /// matchs joués depuis.',
        '  final double weight;',
        '}',
        '',
        '/// Postes de référence d\'un joueur, du plus fréquent au moins '
        'fréquent.',
        'class PlayerPositionProfile {',
        '  const PlayerPositionProfile({',
        '    required this.displayName,',
        '    required this.appearances,',
        '    required this.samples,',
        '    required this.totalWeight,',
        '  });',
        '',
        "  /// Nom du joueur dans l'archive du club, à titre indicatif. Vide "
        'pour',
        "  /// un joueur connu uniquement par les matchs joués dans l'app.",
        '  final String displayName;',
        '',
        '  /// Nombre de titularisations relevées, toutes saisons confondues.',
        '  final int appearances;',
        '',
        '  /// Postes occupés, triés par poids décroissant. Jamais vide.',
        '  final List<PlayerPositionSample> samples;',
        '',
        '  /// Somme des poids de toutes ses titularisations, y compris les',
        "  /// postes trop rares pour figurer dans [samples]. C'est le",
        '  /// dénominateur des parts : sans lui, tronquer la queue de',
        '  /// distribution gonflerait artificiellement le poste principal.',
        '  final double totalWeight;',
        '',
        '  /// Part du temps de jeu passée à un poste, entre 0 et 1.',
        '  double shareOf(String slotLabel) {',
        '    if (totalWeight <= 0) return 0;',
        '    for (final sample in samples) {',
        '      if (sample.slotLabel == slotLabel) {',
        '        return sample.weight / totalWeight;',
        '      }',
        '    }',
        '    return 0;',
        '  }',
        '',
        '  /// Le poste où le joueur a le plus joué.',
        '  String get mainSlotLabel => samples.first.slotLabel;',
        '',
        "  /// Son second poste, s'il en a réellement un.",
        '  String? get secondarySlotLabel =>',
        '      samples.length > 1 ? samples[1].slotLabel : null;',
        '',
        '  /// Vrai quand aucun poste ne domine : le joueur est un couteau',
        '  /// suisse, que la simulation place en ajustement plutôt que sur',
        "  /// un poste de référence qui n'en est pas un.",
        f'  bool get isVersatile => shareOf(mainSlotLabel) < '
        f'{VERSATILE_THRESHOLD};',
        '}',
        '',
        '/// Profils indexés par identité canonique (`players.id`).',
        '///',
        "/// L'identité canonique traverse les saisons et les changements de "
        'nom,',
        "/// contrairement à `season_players.id` ou au nom affiché.",
        'const Map<String, PlayerPositionProfile> kPlayerPositionProfiles =',
        '    <String, PlayerPositionProfile>{',
    ]

    for profile in profiles:
        comment = ', '.join(
            f'{slot} {weight / profile["total"] * 100:.0f}%'
            for slot, weight in profile['samples']
        )
        for player_id in profile['player_ids']:
            lines.append(f'  // {profile["name"]} — {comment}')
            lines.append(f'  {dart_string(player_id)}: PlayerPositionProfile(')
            lines.append(
                f'    displayName: {dart_string(profile["name"])},'
            )
            lines.append(f'    appearances: {profile["appearances"]},')
            lines.append(f'    totalWeight: {profile["total"]:.4f},')
            lines.append('    samples: <PlayerPositionSample>[')
            for slot, weight in profile['samples']:
                lines.append(
                    f'      PlayerPositionSample({dart_string(slot)}, '
                    f'{weight:.4f}),'
                )
            lines.append('    ],')
            lines.append('  ),')

    lines.append('};')
    lines.append('')
    return '\n'.join(lines)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = pathlib.Path(sys.argv[1])
    html = source.read_text(encoding='utf-8')
    identities = {
        name: ids
        for name, ids in json.loads(IDENTITY_MAP.read_text(encoding='utf-8')).items()
        if not name.startswith('_')
    }

    profiles, latest, coverage_end, unknown = build_profiles(html, identities)
    OUTPUT.write_text(
        render(profiles, latest, coverage_end, source.name),
        encoding='utf-8',
    )

    emitted = sum(len(p['player_ids']) for p in profiles)
    print(f'{OUTPUT.relative_to(pathlib.Path.cwd())} : '
          f'{len(profiles)} joueurs, {emitted} identités, '
          f'archive jusqu\'au {coverage_end}.')
    versatile = [
        p['name'] for p in profiles
        if p['samples'][0][1] / p['total'] < VERSATILE_THRESHOLD
    ]
    if versatile:
        print('Polyvalents (aucun poste dominant) : ' + ', '.join(versatile))
    if unknown:
        print('Sans identité canonique, ignorés :')
        for name, count in sorted(unknown, key=lambda item: -item[1]):
            print(f'  {name} ({count} titularisations)')


if __name__ == '__main__':
    main()
