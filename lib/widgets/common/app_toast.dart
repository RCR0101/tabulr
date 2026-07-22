import 'dart:async';
import 'package:flutter/material.dart';
import 'app_tappable.dart';
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
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Actionable toasts linger — 3s is not long enough to read a message and
    // decide to act on it. Held in a final so the closures below keep the
    // promoted non-nullable type.
    final Duration effectiveDuration = duration ??
        (actionLabel != null
            ? const Duration(seconds: 8)
            : const Duration(seconds: 3));

    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (_currentState != null && _currentEntry != null) {
      _currentState!.animateOut().then((_) {
        _currentEntry?.remove();
        _currentEntry = null;
        _currentState = null;
        _insert(message, type, effectiveDuration, actionLabel, onAction);
      });
    } else {
      _currentEntry?.remove();
      _currentEntry = null;
      _currentState = null;
      _insert(message, type, effectiveDuration, actionLabel, onAction);
    }
  }

  static void _insert(
    String message,
    ToastType type,
    Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    final entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: message,
        type: type,
        onDismiss: dismiss,
        onStateCreated: (state) => _currentState = state,
        actionLabel: actionLabel,
        // Dismiss first so the action never fires against a stale overlay.
        onAction: onAction == null
            ? null
            : () {
                dismiss();
                onAction();
              },
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
  static void showError(String message, {String? actionLabel, VoidCallback? onAction}) =>
      show(
        message: message,
        type: ToastType.error,
        actionLabel: actionLabel,
        onAction: onAction,
      );
  static void showInfo(String message) =>
      show(message: message, type: ToastType.info);
  static void showWarning(String message, {String? actionLabel, VoidCallback? onAction}) =>
      show(
        message: message,
        type: ToastType.warning,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;
  final ValueChanged<_ToastOverlayState> onStateCreated;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ToastOverlay({
    required this.message,
    required this.type,
    required this.onDismiss,
    required this.onStateCreated,
    this.actionLabel,
    this.onAction,
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
        scheme.secondary,
        scheme.onSecondary,
        Icons.check_circle_outline,
      ),
      ToastType.error => (
        scheme.error,
        scheme.onError,
        Icons.error_outline,
      ),
      ToastType.warning => (
        scheme.tertiary,
        scheme.onTertiary,
        Icons.warning_amber_rounded,
      ),
      ToastType.info => (
        scheme.primary,
        scheme.onPrimary,
        Icons.info_outline,
      ),
    };

    final bool hasAction =
        widget.actionLabel != null && widget.onAction != null;

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
                child: AppTappable(
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
                      if (hasAction) ...[
                        const SizedBox(width: AppDesign.spacingSm),
                        // Sits inside the dismiss-on-tap GestureDetector; the
                        // inner hit target wins, so tapping here does not dismiss.
                        TextButton(
                          onPressed: widget.onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: fg,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDesign.spacingSm,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide(color: fg.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppDesign.borderRadiusSm,
                            ),
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
