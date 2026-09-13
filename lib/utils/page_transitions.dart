import 'package:flutter/material.dart';
import 'design_constants.dart';

class FadeSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeSlidePageRoute({required this.page, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: AppDesign.motionStandard,
        reverseTransitionDuration: AppDesign.motionFast,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppDesign.curveStandard,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.025, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );
}

/// A lightweight route for opening a timetable from its source card.
///
/// The source geometry remains part of the API for callers, but the transition
/// intentionally uses composited transforms rather than resizing and clipping
/// the full destination on every frame.
class ExpandPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Rect sourceRect;
  final Color sourceColor;
  final BorderRadius sourceBorderRadius;

  ExpandPageRoute({
    required this.page,
    required this.sourceRect,
    this.sourceColor = Colors.transparent,
    this.sourceBorderRadius = const BorderRadius.all(Radius.circular(12)),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) => page,
         transitionDuration: AppDesign.motionEmphasized,
         reverseTransitionDuration: AppDesign.motionStandard,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (MediaQuery.disableAnimationsOf(context)) return child;
           final curved = CurvedAnimation(
             parent: animation,
             curve: AppDesign.curveStandard,
             reverseCurve: AppDesign.curveStandard,
           );
           return SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0, 0.018),
               end: Offset.zero,
             ).animate(curved),
             child: ScaleTransition(
               scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
               child: child,
             ),
           );
         },
       );
}
