import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:as_grinta/features/sports_management/domain/football_formation.dart';

/// Une personne présentée dans la vidéo de la composition : titulaire,
/// remplaçant ou coach.
class PresentationPerson {
  const PresentationPerson({
    required this.id,
    required this.name,
    this.position,
    this.isGoalkeeper = false,
  });

  final String id;
  final String name;

  /// Position normalisée sur le terrain (x et y entre 0 et 1, l'attaque vers
  /// le haut). Seuls les titulaires en ont une.
  final Offset? position;
  final bool isGoalkeeper;
}

/// Les écrans de la vidéo, dans leur ordre d'apparition.
enum PresentationLineKind {
  goalkeeper,
  defenders,
  midfielders,
  attackers,
  bench,
  coach;

  bool get isOnField =>
      this != PresentationLineKind.bench && this != PresentationLineKind.coach;

  String labelFor(int count) {
    final single = count <= 1;
    return switch (this) {
      PresentationLineKind.goalkeeper => single ? 'Gardien' : 'Gardiens',
      PresentationLineKind.defenders => single ? 'Défenseur' : 'Défenseurs',
      PresentationLineKind.midfielders => single ? 'Milieu' : 'Milieux',
      PresentationLineKind.attackers => single ? 'Attaquant' : 'Attaquants',
      PresentationLineKind.bench => single ? 'Remplaçant' : 'Remplaçants',
      PresentationLineKind.coach => 'Coach',
    };
  }
}

/// Famille de poste d'un emplacement de la feuille de match.
///
/// Les milieux offensifs restent des milieux ; les ailiers (AG, AD) et les
/// buteurs (BU, BUG, BUD) sont des attaquants.
PresentationLineKind familyForSlotLabel(String label) {
  if (label == 'GB') return PresentationLineKind.goalkeeper;
  if (label.startsWith('D')) return PresentationLineKind.defenders;
  if (label.startsWith('M')) return PresentationLineKind.midfielders;
  return PresentationLineKind.attackers;
}

/// Un écran de la vidéo : son intitulé et ses photos, rangées comme sur le
/// terrain pour que chacune descende tout droit vers sa place.
class PresentationLine {
  const PresentationLine({
    required this.kind,
    required this.start,
    required this.rows,
  });

  final PresentationLineKind kind;

  /// Instant (en secondes) où l'écran s'ouvre.
  final double start;

  /// Rangées de l'écran, de haut en bas ; chaque rangée de gauche à droite.
  final List<List<PresentationPerson>> rows;

  List<PresentationPerson> get people => [for (final row in rows) ...row];

  String get label => kind.labelFor(people.length);
}

/// Déroulé complet de la vidéo : l'accroche, un écran par ligne, puis la
/// bascule vers l'écran Composition.
class CompositionPresentationPlan {
  const CompositionPresentationPlan._(this.lines);

  /// Les joueurs sont regroupés par famille de poste (gardien, défenseurs,
  /// milieux, attaquants), puis viennent les remplaçants et, s'il s'est dit
  /// présent, le coach. Une ligne vide n'a pas d'écran.
  factory CompositionPresentationPlan.build({
    required List<PresentationPerson> field,
    List<PresentationPerson> bench = const [],
    PresentationPerson? coach,
  }) {
    final families = <PresentationLineKind, List<PresentationPerson>>{};
    for (final person in field) {
      families.putIfAbsent(_familyOf(person), () => []).add(person);
    }
    final groups = <(PresentationLineKind, List<List<PresentationPerson>>)>[
      for (final kind in PresentationLineKind.values)
        if (kind.isOnField && (families[kind]?.isNotEmpty ?? false))
          (kind, fieldRows(families[kind]!)),
      if (bench.isNotEmpty)
        (PresentationLineKind.bench, _chunks(bench, maxPerRow)),
      if (coach != null)
        (
          PresentationLineKind.coach,
          [
            [coach],
          ],
        ),
    ];
    return CompositionPresentationPlan._([
      for (final (index, (kind, rows)) in groups.indexed)
        PresentationLine(
          kind: kind,
          start: introDuration + index * lineInterval,
          rows: rows,
        ),
    ]);
  }

  final List<PresentationLine> lines;

  /// Durée de l'accroche (adversaire, date, lieu) avant le premier écran.
  static const double introDuration = 2.8;

  /// Durée d'un écran de ligne.
  static const double lineInterval = 2.0;

  /// Après l'ouverture d'un écran : départ des photos vers le terrain, et
  /// durée de leur vol.
  static const double flyDelay = 1.05;
  static const double flyDuration = 0.62;

  /// Au-delà, les photos d'un écran passent sur plusieurs rangées pour rester
  /// assez grandes.
  static const int maxPerRow = 4;

  /// Le dernier écran se referme, puis la caméra bascule à la verticale du
  /// terrain de l'écran Composition.
  double get moveStart =>
      (lines.isEmpty ? introDuration : lines.last.start) + 2.2;
  double get flatAt => moveStart + 1.6;
  double get duration => flatAt + 0.8;

  bool get hasPlayers =>
      lines.any((line) => line.kind.isOnField && line.people.isNotEmpty);

  static PresentationLineKind _familyOf(PresentationPerson person) {
    final position = person.position;
    if (position == null) {
      return person.isGoalkeeper
          ? PresentationLineKind.goalkeeper
          : PresentationLineKind.midfielders;
    }
    return familyForSlotLabel(nearestMatchSheetSlotLabel(position));
  }

  /// Rangées d'une famille de titulaires : un rang par ligne du terrain (les
  /// milieux offensifs au-dessus des autres milieux, par exemple), chaque
  /// rang de gauche à droite comme sur le terrain.
  static List<List<PresentationPerson>> fieldRows(
    List<PresentationPerson> people,
  ) {
    int byX(PresentationPerson a, PresentationPerson b) =>
        _x(a).compareTo(_x(b));
    // Une seule rangée tant qu'elle tient : deux joueurs à peine décalés ne
    // méritent pas deux rangées.
    if (people.length <= maxPerRow) {
      return [
        [...people]..sort(byX),
      ];
    }

    final byDepth = [...people]..sort((a, b) => _y(a).compareTo(_y(b)));
    final clusters = <List<PresentationPerson>>[];
    for (final person in byDepth) {
      if (clusters.isEmpty || _y(person) - _y(clusters.last.last) > .06) {
        clusters.add([person]);
      } else {
        clusters.last.add(person);
      }
    }
    return [
      for (final cluster in clusters)
        for (final row in _chunks([...cluster]..sort(byX), maxPerRow)) row,
    ];
  }

  static double _x(PresentationPerson person) => person.position?.dx ?? .5;
  static double _y(PresentationPerson person) => person.position?.dy ?? .5;

  /// Découpe en rangées équilibrées d'au plus [max] éléments (5 → 3 + 2).
  static List<List<T>> _chunks<T>(List<T> items, int max) {
    if (items.isEmpty) return const [];
    final rowCount = (items.length / max).ceil();
    final size = (items.length / rowCount).ceil();
    return [
      for (var start = 0; start < items.length; start += size)
        items.sublist(start, math.min(start + size, items.length)),
    ];
  }
}
