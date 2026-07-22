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
/// Only the chosen candidate is laid out, painted, hit-tested, exposed to
/// semantics, or reachable by keyboard focus; the rest cost a build and an
/// intrinsic measurement, which for a toolbar's worth of children is
/// negligible.
///
/// The focus part is not optional. Every candidate is *built*, so every
/// candidate's buttons register focus nodes — and focus traversal reads the
/// rect of each one it sorts. Reading a rect off a render box that was never
/// laid out asserts, so leaving the unchosen candidates focusable crashed the
/// app on the first Tab keypress. [ExcludeFocus] keeps them out of traversal,
/// which also stops Tab landing on invisible duplicate buttons.
class FirstThatFits extends StatefulWidget {
  const FirstThatFits({super.key, required this.candidates})
      : assert(candidates.length > 0, 'Needs at least one candidate');

  final List<Widget> candidates;

  @override
  State<FirstThatFits> createState() => _FirstThatFitsState();
}

class _FirstThatFitsState extends State<FirstThatFits> {
  /// Which candidate is currently laid out.
  ///
  /// Starts at the first (widest) rather than "none": the real choice isn't
  /// known until layout, and on that first frame exactly one candidate should
  /// be focusable rather than all of them.
  int _selected = 0;

  void _onSelected(int index) {
    if (index < 0 || index == _selected) return;
    // The render object reports this from performLayout, so the rebuild has to
    // wait for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selected != index) setState(() => _selected = index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _FirstThatFitsLayout(
      onSelected: _onSelected,
      candidates: [
        for (final (i, candidate) in widget.candidates.indexed)
          ExcludeFocus(excluding: i != _selected, child: candidate),
      ],
    );
  }
}

class _FirstThatFitsLayout extends MultiChildRenderObjectWidget {
  const _FirstThatFitsLayout({
    required List<Widget> candidates,
    required this.onSelected,
  }) : super(children: candidates);

  final ValueChanged<int> onSelected;

  @override
  RenderFirstThatFits createRenderObject(BuildContext context) =>
      RenderFirstThatFits(onSelected: onSelected);

  @override
  void updateRenderObject(
      BuildContext context, RenderFirstThatFits renderObject) {
    renderObject.onSelected = onSelected;
  }
}

class _FitParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFirstThatFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitParentData> {
  RenderFirstThatFits({required this.onSelected});

  /// Reports which candidate won, so the widget layer can keep the others out
  /// of focus traversal.
  ValueChanged<int> onSelected;

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
    if (index != _selectedIndex) {
      _selectedIndex = index;
      onSelected(index);
    }
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
