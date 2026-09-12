import 'package:flutter/material.dart';

import '../../utils/design_constants.dart';

enum TabulrSurfaceLevel { canvas, panel, raised }

/// A small, semantic surface vocabulary for product layouts.
///
/// Prefer spacing or dividers inside a surface instead of wrapping every
/// child in another bordered card.
class TabulrSurface extends StatelessWidget {
  const TabulrSurface({
    super.key,
    required this.child,
    this.level = TabulrSurfaceLevel.panel,
    this.padding,
    this.borderRadius,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final TabulrSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? AppDesign.cardBorderRadius(context);
    final color = switch (level) {
      TabulrSurfaceLevel.canvas => scheme.surface,
      TabulrSurfaceLevel.panel => scheme.surfaceContainerLow,
      TabulrSurfaceLevel.raised => scheme.surfaceContainer,
    };

    // The colour is painted by a Material so ink and ListTile backgrounds
    // inside a surface land on it instead of being hidden behind it.
    final Widget surface = Material(
      color: color,
      clipBehavior: clipBehavior,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side:
            level == TabulrSurfaceLevel.canvas
                ? BorderSide.none
                : BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.65),
                ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (level != TabulrSurfaceLevel.raised) return surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha:
                  Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.06,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: surface,
    );
  }
}
