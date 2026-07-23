import 'package:flutter/material.dart';
import '../../models/course.dart' show DayOfWeek;

/// A compact bar per weekday (Mon–Sat) showing contact hours, so the *shape* of
/// a week — a brutal Monday, a light Friday — is visible at a glance. Free days
/// read as a faint baseline tick.
class WeeklyLoadChart extends StatelessWidget {
  const WeeklyLoadChart({
    super.key,
    required this.hoursPerDay,
    this.height = 120,
  });

  final Map<DayOfWeek, int> hoursPerDay;
  final double height;

  static const _days = [
    DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F, DayOfWeek.S,
  ];
  static const _labels = ['M', 'T', 'W', 'Th', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHours = _days
        .map((d) => hoursPerDay[d] ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    final peak = maxHours == 0 ? 1 : maxHours;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _days.length; i++)
            Expanded(
              child: _bar(context, scheme, _labels[i],
                  hoursPerDay[_days[i]] ?? 0, peak),
            ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, ColorScheme scheme, String label, int hours,
      int peak) {
    final isPeak = hours == peak && hours > 0;
    final color = hours == 0
        ? scheme.onSurface.withValues(alpha: 0.12)
        : isPeak
            ? scheme.primary
            : scheme.primary.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            hours == 0 ? '·' : '$hours',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: hours == 0
                      ? scheme.onSurface.withValues(alpha: 0.35)
                      : scheme.onSurface.withValues(alpha: 0.75),
                  fontWeight: isPeak ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final full = c.maxHeight;
                final h = hours == 0 ? 3.0 : (full * hours / peak).clamp(4.0, full);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    height: h,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}
