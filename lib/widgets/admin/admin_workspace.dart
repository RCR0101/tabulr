import 'package:flutter/material.dart';

import '../../services/ui/responsive_service.dart';
import '../../utils/design_constants.dart';
import '../common/tabulr_surface.dart';

/// Centers an admin workspace while preserving edge-to-edge scrolling on
/// compact screens.
class AdminWorkspace extends StatelessWidget {
  const AdminWorkspace({
    super.key,
    required this.child,
    this.maxWidth = 1240,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding =
        padding ??
        ResponsiveService.getAdaptivePadding(
          context,
          const EdgeInsets.all(AppDesign.spacingLg),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: resolvedPadding, child: child),
      ),
    );
  }
}

/// A compact control row that wraps naturally instead of overflowing on phone.
class AdminToolbar extends StatelessWidget {
  const AdminToolbar({
    super.key,
    required this.children,
    this.leading,
    this.trailing,
  });

  final List<Widget> children;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TabulrSurface(
      padding: const EdgeInsets.all(AppDesign.spacingSm + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppDesign.spacingSm,
                right: AppDesign.spacingMd,
              ),
              child: leading!,
            ),
          ],
          Expanded(
            child: Wrap(
              spacing: AppDesign.spacingSm,
              runSpacing: AppDesign.spacingSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppDesign.spacingSm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Standard hierarchy for an admin data group. The accent rail identifies the
/// section without adding another decorative icon tile.
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppDesign.spacingMd),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return TabulrSurface(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.spacingMd,
              AppDesign.spacingMd,
              AppDesign.spacingMd,
              AppDesign.spacingSm + 4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: subtitle == null ? 22 : 38,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: AppDesign.borderRadiusXxs,
                  ),
                ),
                const SizedBox(width: AppDesign.spacingSm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppDesign.spacingXxs),
                        Text(
                          subtitle!,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppDesign.muted(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppDesign.spacingMd),
                  trailing!,
                ],
              ],
            ),
          ),
          Divider(height: 1, color: AppDesign.dividerColor(context)),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
