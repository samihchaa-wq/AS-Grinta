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
  Timer? _timer;
  double _velocity = 0;

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
    if (velocity == 0) {
      stop();
    } else {
      _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    }
  }

  void _tick() {
    if (!context.mounted) {
      stop();
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return;
    final next = (position.pixels + _velocity)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next == position.pixels) return;
    position.jumpTo(next);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _velocity = 0;
  }
}
