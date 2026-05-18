import 'package:flutter/material.dart';

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
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

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
}
