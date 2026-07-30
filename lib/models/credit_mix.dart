import '../constants/app_constants.dart';
import 'course.dart';
import 'timetable.dart';

/// The per-semester ceiling for [basis], or null when there is none.
double? capFor(CreditBasis basis) => switch (basis) {
      CreditBasis.units => AppLimits.semesterCreditCap,
      CreditBasis.hours => AppLimits.semesterCreditHourCap,
    };

/// What a set of selected courses counts in, and whether that is coherent.
///
/// From 2026-27 a Pilani course can be taken two ways: under its ordinary com
/// cod for units, or under the 2026-batch com cod for contact hours. A student
/// belongs to one batch, so a timetable is one or the other — 4 units and 12
/// credit hours describe the same course to different people, and adding them
/// together produces a number that means nothing and a credit cap that cannot
/// be checked.
///
/// This is deliberately a report rather than a rule that refuses: the editor
/// shows the mix and offers to drop one side, because which side is wrong is
/// the student's to say.
class CreditMix {
  const CreditMix({
    required this.byBasis,
    required this.coursesByBasis,
  });

  static const empty = CreditMix(byBasis: {}, coursesByBasis: {});

  /// Total per basis. Units and hours are kept apart precisely so nothing can
  /// accidentally sum them.
  final Map<CreditBasis, double> byBasis;

  /// Course codes contributing to each basis, in selection order.
  final Map<CreditBasis, List<String>> coursesByBasis;

  /// True when the timetable holds both kinds at once, which no student can
  /// actually register for.
  bool get isMixed => byBasis.length > 1;

  /// The single basis in use, or null when empty or mixed.
  CreditBasis? get basis => byBasis.length == 1 ? byBasis.keys.first : null;

  double amountFor(CreditBasis basis) => byBasis[basis] ?? 0;

  List<String> coursesFor(CreditBasis basis) => coursesByBasis[basis] ?? const [];

  /// Reads the selection once, counting each course a single time however many
  /// sections of it are selected.
  factory CreditMix.of(
    List<SelectedSection> selected,
    List<Course> catalog,
  ) {
    if (selected.isEmpty) return empty;
    final index = {for (final c in catalog) c.courseCode: c};

    final byBasis = <CreditBasis, double>{};
    final coursesByBasis = <CreditBasis, List<String>>{};
    final seen = <String>{};

    for (final sel in selected) {
      if (!seen.add(sel.courseCode)) continue;
      final course = index[sel.courseCode];
      if (course == null) continue;
      final variant = course.variantFor(sel.comCode);
      byBasis.update(variant.basis, (v) => v + variant.amount,
          ifAbsent: () => variant.amount);
      coursesByBasis
          .putIfAbsent(variant.basis, () => [])
          .add(sel.courseCode);
    }

    return CreditMix(byBasis: byBasis, coursesByBasis: coursesByBasis);
  }
}
