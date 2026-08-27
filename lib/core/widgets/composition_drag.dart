import 'dart:async';

import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Point réellement visé pendant le glisser-déposer en cours : le centre de
/// la vignette que l'utilisateur voit se déplacer.
///
/// `DragTargetDetails.offset` ne donne **pas** ce point : Flutter y met le
/// coin haut-gauche de la vignette fantôme. Une cible qui convertit un dépôt
/// en coordonnées (le terrain) se trompait donc d'une demi-vignette, soit une
/// trentaine de pixels vers le haut et vers la gauche. On mémorise ici le
/// point visé, transmis par [CompositionDraggable] à chaque déplacement.
///
/// Un seul glisser-déposer peut être actif à la fois : un état statique
/// suffit.
class CompositionDragPointer {
  const CompositionDragPointer._();

  static Offset? _global;

  /// Dernier point visé, en coordonnées globales.
  static Offset? get global => _global;

  static void update(Offset value) => _global = value;

  static void clear() => _global = null;

  /// Position à viser pour un dépôt : le centre de la vignette fantôme s'il
  /// est connu, sinon la valeur brute fournie par Flutter.
  static Offset resolve(Offset fallback) => _global ?? fallback;
}

/// Où se place la vignette fantôme par rapport au doigt.
enum CompositionDragAnchor {
  /// Vignette centrée sur le doigt, puis remontée de `feedbackLift` pixels
  /// pour ne pas être cachée par la main. Le point de dépôt est le **centre
  /// de la vignette** : ce qu'on voit est exactement ce qui atterrit. À
  /// utiliser dès que la cible dépend d'une position (terrain, postes).
  pointer,

  /// Vignette qui garde la position où on l'a saisie. À réserver aux
  /// éléments larges (lignes de liste pleine largeur), qu'un centrage ferait
  /// sortir de l'écran.
  grabPoint,
}

/// Délai d'appui long avant qu'un glisser tactile ne démarre.
///
/// Flutter attend 500 ms par défaut, ce qui donne une impression de
/// non-réponse. 300 ms reste largement au-dessus d'un simple appui et ne gêne
/// pas le défilement : un doigt qui balaie dépasse le seuil de mouvement bien
/// avant, ce qui annule le glisser au profit du scroll.
const Duration kCompositionDragTouchDelay = Duration(milliseconds: 300);

/// Tolérance de tremblement avant qu'une souris ne déclenche un glisser.
///
/// Flutter n'accorde qu'1 px aux pointeurs précis : un clic un peu tremblant
/// démarrait un glisser au lieu de sélectionner le poste.
const double _kPreciseDragSlop = 8;

/// Remontée par défaut de la vignette fantôme, adaptée à une petite puce.
const double _kDefaultFeedbackLift = 22;

/// Glisser-déposer commun à toutes les compositions.
///
/// Trois différences avec `LongPressDraggable` :
///
/// * à la souris et au stylet, le glisser démarre immédiatement (plus besoin
///   d'un appui long d'une demi-seconde) ; au doigt, l'appui long est
///   conservé — sans lui le moindre balayage bloquerait le défilement — mais
///   raccourci ;
/// * la vignette fantôme est centrée sur le doigt et remontée au-dessus de
///   lui, au lieu d'apparaître décalée ;
/// * le défilement automatique et le suivi de la position réelle du doigt
///   sont câblés une fois pour toutes.
class CompositionDraggable<T extends Object> extends StatelessWidget {
  const CompositionDraggable({
    super.key,
    required this.data,
    required this.child,
    required this.feedback,
    this.childWhenDragging,
    this.enabled = true,
    this.anchor = CompositionDragAnchor.pointer,
    this.feedbackLift = _kDefaultFeedbackLift,
    this.onDragStarted,
    this.onDragEnd,
  });

  final T data;
  final Widget child;

  /// Ce qui suit le doigt. Il doit avoir une taille propre bornée.
  final Widget feedback;

  final Widget? childWhenDragging;
  final bool enabled;
  final CompositionDragAnchor anchor;

  /// De combien de pixels la vignette est remontée au-dessus du doigt, en
  /// ancrage [CompositionDragAnchor.pointer]. Vaut environ 45 % de la hauteur
  /// de la vignette : la photo reste visible pendant tout le déplacement,
  /// sans que le point de dépôt s'éloigne au point de dérouter.
  final double feedbackLift;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final autoScroll = DragAutoScroller(context);
    final pointerAnchored = anchor == CompositionDragAnchor.pointer;
    final lift = pointerAnchored ? feedbackLift : 0.0;

    void finish() {
      autoScroll.stop();
      CompositionDragPointer.clear();
      onDragEnd?.call();
    }

    return _AdaptiveDraggable<T>(
      data: data,
      touchDelay: kCompositionDragTouchDelay,
      dragAnchorStrategy:
          pointerAnchored ? _trackedPointerAnchor(lift) : _trackedChildAnchor,
      feedback: Material(
        type: MaterialType.transparency,
        child: pointerAnchored
            ? Transform.translate(
                offset: Offset(0, -lift),
                child: FractionalTranslation(
                  translation: const Offset(-.5, -.5),
                  child: feedback,
                ),
              )
            : feedback,
      ),
      childWhenDragging: childWhenDragging,
      onDragStarted: onDragStarted,
      onDragUpdate: (details) {
        CompositionDragPointer.update(
          details.globalPosition - Offset(0, lift),
        );
        autoScroll.update(details.globalPosition);
      },
      onDragEnd: (_) => finish(),
      onDraggableCanceled: (_, __) => finish(),
      child: child,
    );
  }
}

/// Comme `pointerDragAnchorStrategy`, mais en mémorisant le point visé dès le
/// départ : un glisser relâché sans le moindre mouvement a quand même une
/// position connue.
DragAnchorStrategy _trackedPointerAnchor(double lift) {
  return (draggable, context, position) {
    CompositionDragPointer.update(position - Offset(0, lift));
    return Offset.zero;
  };
}

Offset _trackedChildAnchor(
  Draggable<Object> draggable,
  BuildContext context,
  Offset position,
) {
  CompositionDragPointer.update(position);
  return childDragAnchorStrategy(draggable, context, position);
}

class _AdaptiveDraggable<T extends Object> extends Draggable<T> {
  const _AdaptiveDraggable({
    required super.child,
    required super.feedback,
    required this.touchDelay,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
    super.onDraggableCanceled,
  });

  final Duration touchDelay;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _AdaptiveMultiDragGestureRecognizer(
      delay: touchDelay,
      debugOwner: this,
    )..onStart = (position) {
        final drag = onStart(position);
        if (drag != null) unawaited(HapticFeedback.selectionClick());
        return drag;
      };
  }
}

/// Choisit le comportement selon l'appareil : immédiat au curseur, appui long
/// au doigt.
class _AdaptiveMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _AdaptiveMultiDragGestureRecognizer({required this.delay, super.debugOwner});

  final Duration delay;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    final precise = switch (event.kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus ||
      PointerDeviceKind.trackpad =>
        true,
      _ => false,
    };
    return precise
        ? _PreciseDragPointerState(event.position, event.kind, gestureSettings)
        : _DelayedDragPointerState(
            event.position,
            delay,
            event.kind,
            gestureSettings,
          );
  }

  @override
  String get debugDescription => 'composition drag';
}

/// Équivalent de l'état immédiat de Flutter, avec une tolérance de
/// tremblement plus large pour ne pas transformer un clic en glisser.
class _PreciseDragPointerState extends MultiDragPointerState {
  _PreciseDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  @override
  void checkForResolutionAfterMove() {
    final delta = pendingDelta;
    if (delta != null && delta.distance > _kPreciseDragSlop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

/// Reprise de l'état retardé de Flutter, avec un délai configurable.
class _DelayedDragPointerState extends MultiDragPointerState {
  _DelayedDragPointerState(
    super.initialPosition,
    Duration delay,
    super.kind,
    super.gestureSettings,
  ) {
    _timer = Timer(delay, _delayPassed);
  }

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  void _delayPassed() {
    _timer = null;
    final starter = _starter;
    if (starter != null) {
      _starter = null;
      starter(initialPosition);
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  void _ensureTimerStopped() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    // Le minuteur est déjà tombé : le glisser est acquis, plus rien à
    // arbitrer.
    if (_timer == null) return;
    final delta = pendingDelta;
    if (delta != null &&
        delta.distance > computeHitSlop(kind, gestureSettings)) {
      // Le doigt part avant la fin de l'appui long : c'est un défilement.
      resolve(GestureDisposition.rejected);
      _ensureTimerStopped();
    }
  }

  @override
  void dispose() {
    _ensureTimerStopped();
    super.dispose();
  }
}
