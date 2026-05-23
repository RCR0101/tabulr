import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = scheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final highlightColor = scheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class ShimmerBlock extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBlock({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = AppDesign.radiusSm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class TimetableListSkeleton extends StatelessWidget {
  final int count;

  const TimetableListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          children: List.generate(count, (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.spacingSm + 4),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: AppDesign.borderRadiusMd,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppDesign.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShimmerBlock(width: 180, height: 16),
                    const SizedBox(height: AppDesign.spacingSm),
                    ShimmerBlock(width: 120, height: 12),
                  ],
                ),
              ),
            ),
          )),
        ),
      ),
    );
  }
}

class CourseListSkeleton extends StatelessWidget {
  final int count;

  const CourseListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          children: [
            const ShimmerBlock(height: 48),
            const SizedBox(height: AppDesign.spacingSm + 4),
            ...List.generate(count, (i) => Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
              child: ShimmerBlock(height: 64),
            )),
          ],
        ),
      ),
    );
  }
}

class CalendarSkeleton extends StatelessWidget {
  const CalendarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          children: [
            Row(
              children: List.generate(5, (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDesign.spacingXs),
                  child: const ShimmerBlock(height: 24),
                ),
              )),
            ),
            const SizedBox(height: AppDesign.spacingSm),
            Expanded(
              child: Row(
                children: List.generate(5, (i) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppDesign.spacingXs),
                    child: Column(
                      children: List.generate(8, (j) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppDesign.spacingXxs),
                          child: const ShimmerBlock(height: double.infinity),
                        ),
                      )),
                    ),
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AcadDrivesSkeleton extends StatelessWidget {
  final int count;
  final bool grid;

  const AcadDrivesSkeleton({super.key, this.count = 8, this.grid = false});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBlock(width: 160, height: 14),
            const SizedBox(height: AppDesign.spacingSm + 4),
            Expanded(
              child: grid
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: List.generate(
                        count,
                        (_) => SizedBox(
                          width: 340,
                          height: 80,
                          child: ShimmerBlock(height: 80, borderRadius: AppDesign.radiusMd),
                        ),
                      ),
                    )
                  : Column(
                      children: List.generate(
                        count,
                        (_) => Padding(
                          padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
                          child: ShimmerBlock(height: 72, borderRadius: AppDesign.radiusMd),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnnouncementsSkeleton extends StatelessWidget {
  final int count;

  const AnnouncementsSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          children: List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm + 4),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: AppDesign.borderRadiusMd,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ShimmerBlock(width: 80, height: 20, borderRadius: AppDesign.radiusSm),
                          const SizedBox(width: AppDesign.spacingSm),
                          ShimmerBlock(width: 140, height: 16),
                        ],
                      ),
                      const SizedBox(height: AppDesign.spacingSm + 4),
                      const ShimmerBlock(height: 14),
                      const SizedBox(height: AppDesign.spacingSm),
                      ShimmerBlock(width: 200, height: 14),
                    ],
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

class PrerequisitesSkeleton extends StatelessWidget {
  final int count;

  const PrerequisitesSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          children: List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm + 4),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  child: Row(
                    children: [
                      ShimmerBlock(width: 100, height: 18),
                      const SizedBox(width: AppDesign.spacingMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ShimmerBlock(width: 200, height: 14),
                            const SizedBox(height: AppDesign.spacingSm),
                            ShimmerBlock(width: 120, height: 12),
                          ],
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
    );
  }
}

class GenericListSkeleton extends StatelessWidget {
  final int count;
  final double itemHeight;

  const GenericListSkeleton({
    super.key,
    this.count = 5,
    this.itemHeight = 64,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Column(
          children: List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
              child: ShimmerBlock(height: itemHeight, borderRadius: AppDesign.radiusMd),
            ),
          ),
        ),
      ),
    );
  }
}
