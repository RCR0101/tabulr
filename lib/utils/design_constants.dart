import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/ui/theme_service.dart';

class AppDesign {
  AppDesign._();

  // Border radii
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;

  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);

  // Padding scale
  static const double spacingXxs = 2.0;
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;

  // Animation durations
  static const Duration animDurationFast = Duration(milliseconds: 150);
  static const Duration animDurationNormal = Duration(milliseconds: 200);
  static const Duration animDurationSlow = Duration(milliseconds: 500);
  static const Curve animCurve = Curves.easeInOutCubic;

  // Sidebar dimensions
  static const double sidebarWidth = 260.0;
  static const double sidebarCollapsedWidth = 72.0;

  // Opacity levels for text/icon emphasis
  static const double opacityHigh = 0.87;
  static const double opacityMedium = 0.6;
  static const double opacityLow = 0.38;
  static const double opacityDivider = 0.12;

  // Elevation
  static const double elevationNone = 0.0;
  static const double elevationLow = 1.0;
  static const double elevationMd = 2.0;

  // Semantic color helpers that work with any theme
  static Color success(BuildContext context) =>
      Theme.of(context).colorScheme.secondary;
  static Color warning(BuildContext context) =>
      Color.lerp(Colors.orange, Theme.of(context).colorScheme.primary, 0.2)!;
  static Color info(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
  static Color danger(BuildContext context) =>
      Theme.of(context).colorScheme.error;
  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: opacityMedium);
  static Color dividerColor(BuildContext context) =>
      Theme.of(context).colorScheme.outline.withValues(alpha: opacityDivider);

  // ── Standardized input decoration ──────────────────────────────────
  static InputDecoration inputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor:
          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(borderRadius: borderRadiusMd),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadiusMd,
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadiusMd,
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: spacingMd, vertical: spacingSm + 4),
    );
  }

  // ── Standardized dialog shape ──────────────────────────────────────
  static ShapeBorder dialogShape = RoundedRectangleBorder(
    borderRadius: borderRadiusLg,
  );

  static EdgeInsets dialogPadding =
      const EdgeInsets.fromLTRB(spacingLg, spacingLg, spacingLg, spacingMd);

  // ── Standardized card decoration ───────────────────────────────────
  static BoxDecoration cardDecoration(BuildContext context, {bool selected = false}) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surface,
      borderRadius: borderRadiusMd,
      border: selected
          ? Border.all(color: scheme.primary.withValues(alpha: 0.4))
          : Border.all(color: scheme.outline.withValues(alpha: opacityDivider)),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.06),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  // ── Standardized AppBar ────────────────────────────────────────────
  static AppBar appBar(
    BuildContext context, {
    required String title,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = true,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      title: Text(title),
      centerTitle: centerTitle,
      elevation: elevationNone,
      scrolledUnderElevation: elevationLow,
      leading: leading,
      actions: actions,
      bottom: bottom,
    );
  }

  // ── Theme-aware timetable color palette ───────────────────────────
  static List<Color> timetableColors(BuildContext context) {
    final ext = Theme.of(context).extension<TimetableTheme>();
    if (ext != null) return ext.accents;

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.dark) {
      return [
        const Color(0xFF58A6FF),
        const Color(0xFF3FB950),
        const Color(0xFFD29922),
        const Color(0xFFF778BA),
        const Color(0xFFBC8CFF),
        const Color(0xFF39D2C0),
        const Color(0xFFFF7B72),
        const Color(0xFF79C0FF),
        const Color(0xFFFFA657),
        const Color(0xFF7EE787),
        scheme.tertiary,
        scheme.secondary,
      ];
    }
    return [
      const Color(0xFF0969DA),
      const Color(0xFF1A7F37),
      const Color(0xFF9A6700),
      const Color(0xFFBF3989),
      const Color(0xFF8250DF),
      const Color(0xFF1B7C83),
      const Color(0xFFCF222E),
      const Color(0xFF0550AE),
      const Color(0xFFBC4C00),
      const Color(0xFF116329),
      scheme.tertiary,
      scheme.secondary,
    ];
  }

  // ── Motion tokens ─────────────────────────────────────────────────
  static const Duration motionFast = Duration(milliseconds: 200);
  static const Duration motionStandard = Duration(milliseconds: 350);
  static const Duration motionEmphasized = Duration(milliseconds: 500);

  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeInOutCubicEmphasized;
  static const Curve curveDecelerate = Curves.decelerate;

  // ── Glass / frosted tokens ────────────────────────────────────────
  static const double glassBlur = 24.0;
  static const double glassTintOpacity = 0.65;
  static const double glassBorderOpacity = 0.15;
}

extension AppMotion on Widget {
  /// Fade + slide up — default entry for cards, list items, panels.
  Widget motionEntry({
    Duration? duration,
    Duration? delay,
    Curve? curve,
    double slideOffset = 16,
  }) {
    return animate(delay: delay)
        .fadeIn(duration: duration ?? AppDesign.motionStandard, curve: curve ?? AppDesign.curveStandard)
        .slideY(begin: slideOffset / 100, end: 0, duration: duration ?? AppDesign.motionStandard, curve: curve ?? AppDesign.curveStandard);
  }

  /// Quick fade — for content swaps, tab changes, overlays.
  Widget motionFadeIn({Duration? duration, Duration? delay}) {
    return animate(delay: delay)
        .fadeIn(duration: duration ?? AppDesign.motionFast, curve: AppDesign.curveStandard);
  }

  /// Scale + fade — for dialogs, modals, FABs.
  Widget motionScale({Duration? duration, Duration? delay}) {
    return animate(delay: delay)
        .fadeIn(duration: duration ?? AppDesign.motionStandard, curve: AppDesign.curveStandard)
        .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), duration: duration ?? AppDesign.motionStandard, curve: AppDesign.curveEmphasized);
  }

  /// Staggered list item — use with index for cascading entries.
  Widget motionListItem(int index, {Duration? stagger}) {
    final delay = (stagger ?? const Duration(milliseconds: 50)) * index;
    return motionEntry(delay: delay, duration: AppDesign.motionStandard);
  }
}

class FrostedContainer extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final double? blur;

  const FrostedContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blur,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? AppDesign.borderRadiusLg;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur ?? AppDesign.glassBlur,
          sigmaY: blur ?? AppDesign.glassBlur,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: AppDesign.glassTintOpacity),
            borderRadius: radius,
            border: Border.all(
              color: scheme.outline.withValues(alpha: AppDesign.glassBorderOpacity),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
