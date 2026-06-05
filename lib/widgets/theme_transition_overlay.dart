import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
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
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _anim = AnimationController(
      vsync: this,
      duration: AppDesign.motionStandard,
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  Future<void> _runReveal(Offset origin) async {
    if (kIsWeb) {
      // toImage is too expensive on web — just let the theme swap instantly.
      return;
    }

    final boundary = widget.screenshotKey.currentContext
        ?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 1.0);
    _snapshot?.dispose();
    _snapshot = image;

    if (!mounted) return;

    _anim.reset();
    setState(() {});
    await _anim.forward();
    _snapshot?.dispose();
    _snapshot = null;
    if (mounted) setState(() {});
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
                return Opacity(
                  opacity: 1.0 - _anim.value,
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
