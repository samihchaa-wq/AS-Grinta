import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Empile ses enfants les uns sous les autres, sur toute la largeur, en leur
/// donnant à tous la hauteur du plus grand.
///
/// Chaque enfant est d'abord mesuré à sa hauteur naturelle, sans rien couper ;
/// tous reprennent ensuite la plus grande de ces hauteurs. Une liste de cartes
/// garde ainsi des cartes identiques, même quand un texte plus long que les
/// autres passe sur une ligne de plus.
class EqualHeightColumn extends MultiChildRenderObjectWidget {
  const EqualHeightColumn({
    super.key,
    this.spacing = 0,
    super.children,
  });

  /// L'espace laissé entre deux enfants.
  final double spacing;

  @override
  RenderEqualHeightColumn createRenderObject(BuildContext context) {
    return RenderEqualHeightColumn(spacing: spacing);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEqualHeightColumn renderObject,
  ) {
    renderObject.spacing = spacing;
  }
}

class EqualHeightColumnParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualHeightColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, EqualHeightColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox,
            EqualHeightColumnParentData> {
  RenderEqualHeightColumn({required double spacing}) : _spacing = spacing;

  double get spacing => _spacing;
  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! EqualHeightColumnParentData) {
      child.parentData = EqualHeightColumnParentData();
    }
  }

  double _stackHeight(double rowHeight) {
    if (childCount == 0) return 0;
    return rowHeight * childCount + spacing * (childCount - 1);
  }

  double _tallestIntrinsic(double Function(RenderBox child) measure) {
    var tallest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      tallest = math.max(tallest, measure(child));
    }
    return tallest;
  }

  double _widestIntrinsic(double Function(RenderBox child) measure) {
    var widest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      widest = math.max(widest, measure(child));
    }
    return widest;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widestIntrinsic((child) => child.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widestIntrinsic((child) => child.getMaxIntrinsicWidth(double.infinity));

  // Un enfant ne descend jamais sous sa hauteur naturelle : la hauteur
  // minimale est donc aussi celle qu'il prend réellement.
  @override
  double computeMinIntrinsicHeight(double width) => _stackHeight(
        _tallestIntrinsic((child) => child.getMaxIntrinsicHeight(width)),
      );

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToFirstActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final rowHeight = _tallestIntrinsic(
      (child) =>
          child.getDryLayout(BoxConstraints.tightFor(width: width)).height,
    );
    return constraints.constrain(Size(width, _stackHeight(rowHeight)));
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth,
      'EqualHeightColumn doit recevoir une largeur finie.',
    );
    final width = constraints.maxWidth;

    // Première passe : la hauteur naturelle de chaque enfant.
    var rowHeight = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      rowHeight = math.max(rowHeight, child.size.height);
    }

    // Seconde passe : tous prennent la hauteur du plus grand. Une hauteur
    // minimale plutôt qu'imposée : un enfant dont le contenu change alors
    // prévient la colonne, qui recalcule la hauteur commune.
    var y = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          minHeight: rowHeight,
        ),
        parentUsesSize: true,
      );
      (child.parentData! as EqualHeightColumnParentData).offset = Offset(0, y);
      y += rowHeight + spacing;
    }

    size = constraints.constrain(Size(width, _stackHeight(rowHeight)));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}
