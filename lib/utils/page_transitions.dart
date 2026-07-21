import 'package:flutter/material.dart';
import 'design_constants.dart';

class FadeSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeSlidePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: AppDesign.animDurationNormal,
          reverseTransitionDuration: AppDesign.animDurationNormal,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppDesign.animCurve,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// A lightweight container-transform-style route that scales up from a
/// source rect (the tapped card) to full screen with a crossfade.
/// Much cheaper than OpenContainer — no rasterization, just rect interpolation.
class ExpandPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Rect sourceRect;
  final Color sourceColor;
  final BorderRadius sourceBorderRadius;

  static const _expandDuration = Duration(milliseconds: 450);

  ExpandPageRoute({
    required this.page,
    required this.sourceRect,
    this.sourceColor = Colors.transparent,
    this.sourceBorderRadius = const BorderRadius.all(Radius.circular(12)),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: _expandDuration,
          reverseTransitionDuration: _expandDuration,
          opaque: false,
          barrierColor: Colors.transparent,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppDesign.curveEmphasized,
              reverseCurve: AppDesign.curveStandard,
            );

            final screenSize = MediaQuery.sizeOf(context);
            final fullRect = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);

            final rectTween = RectTween(begin: sourceRect, end: fullRect);
            final borderTween = BorderRadiusTween(
              begin: sourceBorderRadius,
              end: BorderRadius.zero,
            );

            return AnimatedBuilder(
              animation: curved,
              child: child,
              builder: (context, cachedChild) {
                final rect = rectTween.evaluate(curved)!;
                final radius = borderTween.evaluate(curved)!;
                final fadeIn = Curves.easeIn.transform(curved.value.clamp(0.15, 1.0).remap(0.15, 1.0));

                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: rect,
                      child: ClipRRect(
                        borderRadius: radius,
                        child: ColoredBox(
                          color: sourceColor,
                          child: Opacity(
                            opacity: fadeIn,
                            child: cachedChild,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
}

extension _RemapDouble on double {
  double remap(double inMin, double inMax) {
    return (this - inMin) / (inMax - inMin);
  }
}
