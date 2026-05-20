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
            Container(
              padding: const EdgeInsets.all(AppDesign.spacingLg),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: scheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppDesign.spacingLg),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppDesign.spacingSm),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppDesign.spacingLg),
              AppButton(
                label: actionLabel!,
                icon: actionIcon,
                onTap: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
