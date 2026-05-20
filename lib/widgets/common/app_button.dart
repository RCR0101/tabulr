import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, Color border) = switch (variant) {
      AppButtonVariant.primary => (
        scheme.primary.withValues(alpha: 0.1),
        scheme.primary,
        scheme.primary.withValues(alpha: 0.3),
      ),
      AppButtonVariant.secondary => (
        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        scheme.onSurface,
        scheme.outline.withValues(alpha: 0.3),
      ),
      AppButtonVariant.ghost => (
        Colors.transparent,
        scheme.onSurface.withValues(alpha: 0.7),
        Colors.transparent,
      ),
      AppButtonVariant.danger => (
        scheme.error.withValues(alpha: 0.1),
        scheme.error,
        scheme.error.withValues(alpha: 0.3),
      ),
    };

    final child = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fg,
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: AppDesign.spacingSm),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final button = ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: AppDesign.borderRadiusMd,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spacingMd,
          vertical: AppDesign.spacingSm + 4,
        ),
      ),
      child: child,
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
