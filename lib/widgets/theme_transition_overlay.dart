import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../utils/design_constants.dart';

class ThemeTransitionController {
  _ThemeTransitionOverlayState? _state;

  Future<void> runReveal(Offset origin) async {
    await _state?._runReveal(origin);
  }
}

class ThemeTransitionOverlay extends StatefulWidget {
  final ThemeTransitionController controller;
  final Widget child;
  final GlobalKey screenshotKey;

  const ThemeTransitionOverlay({
    super.key,
    required this.controller,
    required this.child,
    required this.screenshotKey,
  });

  @override
  State<ThemeTransitionOverlay> createState() => _ThemeTransitionOverlayState();
}

class _ThemeTransitionOverlayState extends State<ThemeTransitionOverlay>
    with SingleTickerProviderStateMixin {
  ui.Image? _snapshot;
  Offset _origin = Offset.zero;
  late AnimationController _anim;
  late Animation<double> _radiusTween;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _anim = AnimationController(
      vsync: this,
      duration: AppDesign.motionEmphasized,
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  Future<void> _runReveal(Offset origin) async {
    final boundary = widget.screenshotKey.currentContext
        ?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 1.0);
    _origin = origin;
    _snapshot?.dispose();
    _snapshot = image;

    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final maxRadius = _maxRadius(size, origin);
    _radiusTween = Tween<double>(begin: 0, end: maxRadius).animate(
      CurvedAnimation(parent: _anim, curve: AppDesign.curveEmphasized),
    );

    _anim.reset();
    setState(() {});
    await _anim.forward();
    _snapshot?.dispose();
    _snapshot = null;
    if (mounted) setState(() {});
  }

  double _maxRadius(Size size, Offset origin) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    return corners.map((c) => (c - origin).distance).reduce((a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_snapshot != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, child) {
                return ClipPath(
                  clipper: _CircleRevealClipper(
                    center: _origin,
                    radius: _radiusTween.value,
                    invert: true,
                  ),
                  child: child,
                );
              },
              child: RawImage(image: _snapshot, fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  final bool invert;

  _CircleRevealClipper({
    required this.center,
    required this.radius,
    this.invert = false,
  });

  @override
  Path getClip(Size size) {
    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    if (invert) {
      return Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addPath(circle, Offset.zero)
        ..fillType = PathFillType.evenOdd;
    }
    return circle;
  }

  @override
  bool shouldReclip(_CircleRevealClipper old) =>
      old.radius != radius || old.center != center;
}
