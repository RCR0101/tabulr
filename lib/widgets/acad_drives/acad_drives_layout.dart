import 'package:flutter/material.dart';

import '../../utils/design_constants.dart';

/// Layout primitives owned by the Academic Drives resource browser.
class AcadDrivesPageBackground extends StatelessWidget {
  const AcadDrivesPageBackground({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = accent ?? scheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: .025), scheme.surfaceContainerLowest],
          stops: const [0, .28],
        ),
      ),
      child: child,
    );
  }
}

class AcadDrivesHeader extends StatelessWidget {
  const AcadDrivesHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.eyebrow,
    this.metrics = const [],
    this.actions = const [],
    this.accent,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? eyebrow;
  final List<AcadDrivesMetric> metrics;
  final List<Widget> actions;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = accent ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppDesign.borderRadiusLg,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .8)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final heading = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .09),
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Icon(icon, color: tint, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Text(
                        eyebrow!,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actionBar = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: actions,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                heading,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  actionBar,
                ],
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: 24),
                      actionBar,
                    ],
                  ],
                ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 17),
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: .7),
                ),
                const SizedBox(height: 13),
                Wrap(spacing: 22, runSpacing: 10, children: metrics),
              ],
            ],
          );
        },
      ),
    );
  }
}

class AcadDrivesMetric extends StatelessWidget {
  const AcadDrivesMetric({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class AcadDrivesToolbar extends StatelessWidget {
  const AcadDrivesToolbar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppDesign.borderRadiusMd,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .8)),
      ),
      child: child,
    );
  }
}

class AcadDrivesSectionTitle extends StatelessWidget {
  const AcadDrivesSectionTitle({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.15,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
