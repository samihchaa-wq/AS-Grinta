import 'dart:async';

import 'package:flutter/material.dart';

/// Fait défiler automatiquement le [Scrollable] ancêtre le plus proche
/// lorsque le doigt approche du bord haut ou bas de l'écran pendant un
/// glisser-déposer. `Draggable`/`LongPressDraggable` n'ont pas ce
/// comportement par défaut : sans lui, il est impossible de déposer un
/// élément sur une cible actuellement hors écran (ex. glisser un joueur du
/// banc, en bas, vers le terrain, en haut).
///
/// Utilisation : créer une instance dans `onDragUpdate`, appeler
/// [update] à chaque déplacement, et [stop] dans `onDragEnd` /
/// `onDraggableCanceled`.
class DragAutoScroller {
  DragAutoScroller(this.context);

  final BuildContext context;

  // Un seul glisser-déposer peut être actif à la fois : l'état du minuteur
  // est donc statique/partagé. Les widgets de la liste (puces joueurs, banc…)
  // sont reconstruits en permanence pendant un drag (le `DragTarget` survolé
  // se reconstruit à chaque mouvement), ce qui recrée une nouvelle instance
  // de `DragAutoScroller` à chaque frame. Si l'état était porté par
  // l'instance, l'ancien minuteur devenait orphelin (plus personne ne
  // l'arrêtait) et continuait à défiler indéfiniment, rendant le défilement
  // manuel impossible. En centralisant l'état, n'importe quelle instance —
  // même créée après coup — arrête bien le même minuteur.
  static Timer? _timer;
  static double _velocity = 0;
  static ScrollableState? _scrollable;

  static const double _edgeSize = 90;
  static const double _maxPixelsPerTick = 16;

  void update(Offset globalPosition) {
    if (!context.mounted) {
      stop();
      return;
    }
    final height = MediaQuery.sizeOf(context).height;
    final dy = globalPosition.dy;
    double velocity = 0;
    if (dy < _edgeSize) {
      velocity = -_maxPixelsPerTick * (1 - dy / _edgeSize);
    } else if (dy > height - _edgeSize) {
      final fromBottom = height - dy;
      velocity = _maxPixelsPerTick * (1 - fromBottom / _edgeSize);
    }
    _velocity = velocity;
    _scrollable = Scrollable.maybeOf(context);
    if (velocity == 0) {
      stop();
    } else {
      _timer ??=
          Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    }
  }

  void _tick() {
    final position = _scrollable?.position;
    if (position == null) {
      stop();
      return;
    }
    final next = (position.pixels + _velocity)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next == position.pixels) return;
    position.jumpTo(next);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _velocity = 0;
    _scrollable = null;
  }
}
