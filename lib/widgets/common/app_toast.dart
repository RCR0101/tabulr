import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

enum ToastType { success, error, info, warning }

class AppToast {
  AppToast._();

  static OverlayState? _overlayState;
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static _ToastOverlayState? _currentState;

  static void init(BuildContext context) {
    _overlayState = Overlay.of(context, rootOverlay: true);
  }

  static void show({
    required String message,
    required ToastType type,
    Duration duration = const Duration(seconds: 3),
  }) {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (_currentState != null && _currentEntry != null) {
      _currentState!.animateOut().then((_) {
        _currentEntry?.remove();
        _currentEntry = null;
        _currentState = null;
        _insert(message, type, duration);
      });
    } else {
      _currentEntry?.remove();
      _currentEntry = null;
      _currentState = null;
      _insert(message, type, duration);
    }
  }

  static void _insert(String message, ToastType type, Duration duration) {
    final entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: message,
        type: type,
        onDismiss: dismiss,
        onStateCreated: (state) => _currentState = state,
      ),
    );

    _currentEntry = entry;
    _overlayState?.insert(entry);
    _dismissTimer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (_currentState != null && _currentEntry != null) {
      final entry = _currentEntry;
      _currentEntry = null;
      final state = _currentState;
      _currentState = null;
      state!.animateOut().then((_) {
        entry?.remove();
      });
    } else {
      _currentEntry?.remove();
      _currentEntry = null;
      _currentState = null;
    }
  }

  static void showSuccess(String message) =>
      show(message: message, type: ToastType.success);
  static void showError(String message) =>
      show(message: message, type: ToastType.error);
  static void showInfo(String message) =>
      show(message: message, type: ToastType.info);
  static void showWarning(String message) =>
      show(message: message, type: ToastType.warning);
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;
  final ValueChanged<_ToastOverlayState> onStateCreated;

  const _ToastOverlay({
    required this.message,
    required this.type,
    required this.onDismiss,
    required this.onStateCreated,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDesign.animDurationNormal,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppDesign.animCurve));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    widget.onStateCreated(this);
  }

  Future<void> animateOut() {
    if (_dismissed) return Future.value();
    _dismissed = true;
    return _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (widget.type) {
      ToastType.success => (
        const Color(0xFF065F46),
        Colors.white,
        Icons.check_circle_outline,
      ),
      ToastType.error => (
        scheme.error,
        scheme.onError,
        Icons.error_outline,
      ),
      ToastType.warning => (
        const Color(0xFF92400E),
        Colors.white,
        Icons.warning_amber_rounded,
      ),
      ToastType.info => (
        scheme.primary,
        scheme.onPrimary,
        Icons.info_outline,
      ),
    };

    final String typeLabel = switch (widget.type) {
      ToastType.success => 'Success',
      ToastType.error => 'Error',
      ToastType.info => 'Info',
      ToastType.warning => 'Warning',
    };

    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: '$typeLabel: ${widget.message}',
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.spacingMd,
                    vertical: AppDesign.spacingSm + 4,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: AppDesign.borderRadiusMd,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: fg, size: 20),
                      const SizedBox(width: AppDesign.spacingSm + 4),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(color: fg, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
