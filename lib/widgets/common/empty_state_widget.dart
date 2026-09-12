import 'package:flutter/material.dart';

import '../../utils/design_constants.dart';
import 'app_button.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimetableEmptyVisual(icon: icon).motionEntry(),
            const SizedBox(height: AppDesign.spacingLg),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ).motionFadeIn(delay: const Duration(milliseconds: 150)),
            if (subtitle != null) ...[
              const SizedBox(height: AppDesign.spacingSm),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ).motionFadeIn(delay: const Duration(milliseconds: 250)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppDesign.spacingLg),
              AppButton(
                label: actionLabel!,
                icon: actionIcon,
                onTap: onAction,
              ).motionEntry(delay: const Duration(milliseconds: 350)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimetableEmptyVisual extends StatelessWidget {
  const _TimetableEmptyVisual({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: 124,
        height: 82,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppDesign.borderRadiusLg,
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            for (var column = 1; column < 4; column++)
              Positioned(
                left: column * 31,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            for (var row = 1; row < 3; row++)
              Positioned(
                left: 0,
                right: 0,
                top: row * 27,
                child: Container(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            Positioned(
              left: 34,
              top: 30,
              child: Container(
                width: 56,
                height: 24,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Icon(icon, size: 17, color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
