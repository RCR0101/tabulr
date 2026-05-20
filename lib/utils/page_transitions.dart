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
