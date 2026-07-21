import 'dart:math';

import 'package:flutter/material.dart';

import '../../utils/design_constants.dart';

/// Assigns one accent colour per course.
///
/// The previous implementation indexed the palette by `courseCode.hashCode`,
/// which collides often: with 12 accents and 6 courses there is roughly a 78%
/// chance that two of them land on the same colour, and colour is the primary
/// way a student tells one block from another at a glance. Assigning by order
/// of first appearance instead guarantees distinct colours while the timetable
/// holds no more accents than the palette has.
///
/// Order of first appearance is stable because it follows the order of
/// `selectedSections`, so a course keeps its colour across rebuilds, across the
/// on-screen grid and the PNG export, and between the grid and the exam table.
class CoursePalette {
  CoursePalette._(this._colors, this._byCourse);

  final List<Color> _colors;
  final Map<String, Color> _byCourse;

  /// Builds a palette for [courseCodes], which must already be in the order the
  /// courses should be coloured (duplicates are ignored after the first).
  factory CoursePalette.forCourses(
    BuildContext context,
    Iterable<String> courseCodes,
  ) {
    final colors = AppDesign.timetableColors(context);
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final byCourse = <String, Color>{};
    for (final code in courseCodes) {
      if (byCourse.containsKey(code)) continue;
      final base = colors[byCourse.length % colors.length];
      byCourse[code] = _ensureContrast(base, surface, isDark);
    }
    return CoursePalette._(colors, byCourse);
  }

  /// The accent for [courseCode]. Courses absent from the seed list (an exam
  /// row for a course with no scheduled hours, say) fall back to a hash so they
  /// still get a stable colour rather than a default.
  Color colorFor(String courseCode) {
    final assigned = _byCourse[courseCode];
    if (assigned != null) return assigned;
    return _colors[courseCode.hashCode.abs() % _colors.length];
  }

  static Color _ensureContrast(Color color, Color background, bool isDark) {
    if (_contrastRatio(color, background) >= 4.5) return color;
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + (isDark ? 0.2 : -0.2)).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  static double _luminance(Color c) {
    double channel(double v) =>
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  static double _contrastRatio(Color a, Color b) {
    final la = _luminance(a) + 0.05;
    final lb = _luminance(b) + 0.05;
    return la > lb ? la / lb : lb / la;
  }
}
