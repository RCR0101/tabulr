import 'package:flutter/material.dart';

/// A tap target that shows the pointer (hand) cursor on web/desktop.
///
/// A raw [GestureDetector] does **not** change the mouse cursor on Flutter web,
/// so clickable elements built with one look non-interactive (they keep the
/// default arrow) while [InkWell]s and buttons show a hand. Use [AppTappable]
/// for clickable regions that aren't Material ink surfaces so hover affordances
/// stay consistent across the app.
///
/// The constructor mirrors [GestureDetector]'s common parameters — including the
/// same default [HitTestBehavior.deferToChild] — so swapping a plain
/// `GestureDetector` for an `AppTappable` is behavior-preserving.
class AppTappable extends StatelessWidget {
  const AppTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.behavior = HitTestBehavior.deferToChild,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior behavior;

  /// Cursor shown on hover. Defaults to the pointer/hand. Falls back to the
  /// ambient cursor when there is nothing to tap.
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    final interactive =
        onTap != null || onDoubleTap != null || onLongPress != null;
    return MouseRegion(
      cursor: interactive ? cursor : MouseCursor.defer,
      child: GestureDetector(
        behavior: behavior,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}
