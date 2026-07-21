import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays out the first candidate whose natural width fits the available space,
/// falling back to the last one.
///
/// This exists so a toolbar can collapse without anyone hardcoding how wide its
/// buttons are. Hand-written breakpoints go stale the moment a label is
/// reworded, a button is added, or the app is read at a larger text scale —
/// and the failure mode is a visible overflow stripe. Here the candidates
/// measure themselves via [RenderBox.getMaxIntrinsicWidth].
///
/// Only the chosen candidate is laid out, painted, hit-tested, or exposed to
/// semantics; the rest cost a build and an intrinsic measurement, which for a
/// toolbar's worth of children is negligible.
class FirstThatFits extends MultiChildRenderObjectWidget {
  const FirstThatFits({super.key, required List<Widget> candidates})
      : assert(candidates.length > 0, 'Needs at least one candidate'),
        super(children: candidates);

  @override
  RenderFirstThatFits createRenderObject(BuildContext context) =>
      RenderFirstThatFits();
}

class _FitParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFirstThatFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitParentData> {
  RenderBox? _selected;

  /// Index of the candidate currently laid out, or -1 before first layout.
  ///
  /// Every candidate is built, so `find.text` matches text inside ones that
  /// were never laid out or painted; this is how a test asks which variant is
  /// actually on screen.
  int get selectedIndex => _selectedIndex;
  int _selectedIndex = -1;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _FitParentData) {
      child.parentData = _FitParentData();
    }
  }

  /// The first child that fits [maxWidth], or the last child if none do.
  (RenderBox?, int) _choose(double maxWidth) {
    RenderBox? child = firstChild;
    var index = 0;
    while (child != null) {
      final next = childAfter(child);
      if (next == null) return (child, index); // last resort, fits or not
      if (child.getMaxIntrinsicWidth(double.infinity) <= maxWidth) {
        return (child, index);
      }
      child = next;
      index++;
    }
    return (null, -1);
  }

  @override
  void performLayout() {
    final (chosen, index) = _choose(constraints.maxWidth);
    _selected = chosen;
    _selectedIndex = index;
    if (chosen == null) {
      size = constraints.smallest;
      return;
    }
    chosen.layout(constraints, parentUsesSize: true);
    (chosen.parentData! as _FitParentData).offset = Offset.zero;
    size = constraints.constrain(chosen.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final (chosen, _) = _choose(constraints.maxWidth);
    if (chosen == null) return constraints.smallest;
    return constraints.constrain(chosen.getDryLayout(constraints));
  }

  /// The narrowest candidate is what this can shrink to; the widest is what it
  /// would prefer.
  @override
  double computeMinIntrinsicWidth(double height) {
    if (lastChild == null) return 0;
    return lastChild!.getMinIntrinsicWidth(height);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (firstChild == null) return 0;
    return firstChild!.getMaxIntrinsicWidth(height);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final (chosen, _) = _choose(width);
    return chosen?.getMinIntrinsicHeight(width) ?? 0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final (chosen, _) = _choose(width);
    return chosen?.getMaxIntrinsicHeight(width) ?? 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = _selected;
    if (child != null) context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = _selected;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: Offset.zero,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  /// Without this, a screen reader would announce every candidate — several
  /// copies of the same toolbar.
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final child = _selected;
    if (child != null) visitor(child);
  }
}
