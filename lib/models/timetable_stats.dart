import '../constants/app_constants.dart';
import 'course.dart';
import 'credit_mix.dart';
import 'timetable.dart';

class TimetableStats {
  final int totalHoursPerWeek;

  /// The timetable's load in whatever it counts in — units for almost every
  /// timetable, contact hours for a 2026-batch Pilani one. Read [creditBasis]
  /// before labelling it; the two are not the same quantity and a bare number
  /// captioned "credits" would be wrong for half the students who see it.
  final double totalCredits;

  /// What [totalCredits] is measured in.
  final CreditBasis creditBasis;
  final int courseCount;
  final DayOfWeek busiestDay;
  final int busiestDayHours;
  final int freeDayCount;
  final List<DayOfWeek> freeDays;
  final int longestGapHours;
  final DayOfWeek? longestGapDay;
  final Map<DayOfWeek, int> hoursPerDay;
  final List<ExamCluster> examClusters;

  /// Days whose first class is the 8 AM slot. The single most asked-about
  /// property of a BITS timetable after "is it clash free".
  final List<DayOfWeek> earlyStartDays;

  /// Every free hour sandwiched between two classes on the same day. Unlike
  /// [longestGapHours] this is the whole week's dead time.
  final int totalGapHours;

  /// The longest unbroken run of classes on any one day, and where.
  final int longestStreakHours;
  final DayOfWeek? longestStreakDay;

  /// Every exam (mid-sem + comprehensive) across the selected courses, sorted by
  /// date then session — the series behind the exam-crunch timeline.
  final List<ExamEntry> allExams;

  const TimetableStats({
    required this.totalHoursPerWeek,
    required this.totalCredits,
    this.creditBasis = CreditBasis.units,
    required this.courseCount,
    required this.busiestDay,
    required this.busiestDayHours,
    required this.freeDayCount,
    required this.freeDays,
    required this.longestGapHours,
    required this.longestGapDay,
    required this.hoursPerDay,
    required this.examClusters,
    required this.allExams,
    this.earlyStartDays = const [],
    this.totalGapHours = 0,
    this.longestStreakHours = 0,
    this.longestStreakDay,
  });

  static const _empty = TimetableStats(
    totalHoursPerWeek: 0,
    totalCredits: 0,
    courseCount: 0,
    busiestDay: DayOfWeek.M,
    busiestDayHours: 0,
    freeDayCount: 6,
    freeDays: [DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F, DayOfWeek.S],
    longestGapHours: 0,
    longestGapDay: null,
    hoursPerDay: {},
    examClusters: [],
    allExams: [],
  );

  static TimetableStats fromTimetable(Timetable timetable) {
    if (timetable.selectedSections.isEmpty) return _empty;

    final dayHours = <DayOfWeek, Set<int>>{};
    final uniqueCourses = <String>{};
    // Counted on the timetable's own basis, so a credit-hours timetable does
    // not report 0 — its courses have no unit count to sum.
    final mix = CreditMix.of(timetable.selectedSections, timetable.availableCourses);
    final basis = mix.basis ?? timetable.creditBasis;
    final totalCredits = mix.amountFor(basis);

    for (final sel in timetable.selectedSections) {
      uniqueCourses.add(sel.courseCode);

      for (final entry in sel.section.schedule) {
        for (final day in entry.days) {
          dayHours.putIfAbsent(day, () => {});
          dayHours[day]!.addAll(entry.hours);
        }
      }
    }

    final hoursPerDay = <DayOfWeek, int>{};
    for (final day in DayOfWeek.values) {
      hoursPerDay[day] = dayHours[day]?.length ?? 0;
    }

    final totalHours = hoursPerDay.values.fold(0, (a, b) => a + b);

    // Busiest day
    var busiestDay = DayOfWeek.M;
    var busiestHours = 0;
    for (final entry in hoursPerDay.entries) {
      if (entry.value > busiestHours) {
        busiestDay = entry.key;
        busiestHours = entry.value;
      }
    }

    // Free days (weekdays only — M through F)
    const weekdays = [DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F];
    final freeDays = weekdays.where((d) => (hoursPerDay[d] ?? 0) == 0).toList();

    // One pass per day covers gaps, back-to-back runs and 8 AM starts.
    var longestGap = 0;
    DayOfWeek? longestGapDay;
    var totalGap = 0;
    var longestStreak = 0;
    DayOfWeek? longestStreakDay;
    final earlyStartDays = <DayOfWeek>[];

    // Iterate the enum, not the map, so day lists come out in week order.
    for (final day in DayOfWeek.values) {
      final hours = dayHours[day];
      if (hours == null || hours.isEmpty) continue;

      final sorted = hours.toList()..sort();
      if (sorted.first == ScheduleConstants.firstHour) earlyStartDays.add(day);

      // A day with a single class is still a one-hour run.
      var streak = 1;
      if (streak > longestStreak) {
        longestStreak = streak;
        longestStreakDay = day;
      }
      for (int i = 1; i < sorted.length; i++) {
        final gap = sorted[i] - sorted[i - 1] - 1;
        if (gap > 0) {
          totalGap += gap;
          if (gap > longestGap) {
            longestGap = gap;
            longestGapDay = day;
          }
          streak = 1;
        } else {
          streak++;
        }
        if (streak > longestStreak) {
          longestStreak = streak;
          longestStreakDay = day;
        }
      }
    }

    // Exams + clusters
    final allExams = _computeExams(timetable);
    final examClusters = _clustersOf(allExams);

    return TimetableStats(
      totalHoursPerWeek: totalHours,
      totalCredits: totalCredits,
      creditBasis: basis,
      courseCount: uniqueCourses.length,
      busiestDay: busiestDay,
      busiestDayHours: busiestHours,
      freeDayCount: freeDays.length,
      freeDays: freeDays,
      longestGapHours: longestGap,
      longestGapDay: longestGapDay,
      hoursPerDay: hoursPerDay,
      examClusters: examClusters,
      allExams: allExams,
      earlyStartDays: earlyStartDays,
      totalGapHours: totalGap,
      longestStreakHours: longestStreak,
      longestStreakDay: longestStreakDay,
    );
  }

  static List<ExamEntry> _computeExams(Timetable timetable) {
    final examEntries = <ExamEntry>[];
    final seenCourses = <String>{};

    for (final sel in timetable.selectedSections) {
      if (!seenCourses.add(sel.courseCode)) continue;
      final course = timetable.availableCourses.where(
        (c) => c.courseCode == sel.courseCode,
      ).firstOrNull;
      if (course == null) continue;

      if (course.midSemExam != null) {
        examEntries.add(ExamEntry(
          courseCode: sel.courseCode,
          courseTitle: course.courseTitle,
          date: course.midSemExam!.date,
          timeSlot: course.midSemExam!.timeSlot,
          isMidSem: true,
        ));
      }
      if (course.endSemExam != null) {
        examEntries.add(ExamEntry(
          courseCode: sel.courseCode,
          courseTitle: course.courseTitle,
          date: course.endSemExam!.date,
          timeSlot: course.endSemExam!.timeSlot,
          isMidSem: false,
        ));
      }
    }

    examEntries.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.timeSlot.index.compareTo(b.timeSlot.index);
    });
    return examEntries;
  }

  /// Runs of exams packed within a day of each other (≥2 in the run).
  static List<ExamCluster> _clustersOf(List<ExamEntry> examEntries) {
    if (examEntries.isEmpty) return [];

    final clusters = <ExamCluster>[];
    var clusterStart = 0;

    for (int i = 1; i <= examEntries.length; i++) {
      final shouldClose = i == examEntries.length ||
          examEntries[i].date.difference(examEntries[i - 1].date).inDays > 1;

      if (shouldClose) {
        final clusterExams = examEntries.sublist(clusterStart, i);
        if (clusterExams.length >= 2) {
          final days = clusterExams.last.date.difference(clusterExams.first.date).inDays + 1;
          clusters.add(ExamCluster(
            exams: clusterExams,
            startDate: clusterExams.first.date,
            endDate: clusterExams.last.date,
            spanDays: days,
          ));
        }
        clusterStart = i;
      }
    }

    return clusters;
  }

  bool get hasExamClusters => examClusters.isNotEmpty;

  /// Days that have at least one class.
  int get classDayCount => hoursPerDay.values.where((h) => h > 0).length;

  /// The ceiling for this timetable's basis: 25 units, or 70 contact hours.
  double get creditCap => capFor(creditBasis);

  bool get isOverCreditCap => totalCredits > creditCap;

  int get worstClusterSize =>
      examClusters.isEmpty ? 0 : examClusters.map((c) => c.exams.length).reduce((a, b) => a > b ? a : b);

  String get summaryLine {
    final parts = <String>[];
    parts.add('$totalHoursPerWeek hrs/wk');
    if (freeDayCount > 0) {
      parts.add('$freeDayCount free day${freeDayCount > 1 ? 's' : ''}');
    }
    parts.add('Busiest: ${_shortDay(busiestDay)} (${busiestDayHours}h)');
    return parts.join(' · ');
  }

  static String _shortDay(DayOfWeek day) => DayConstants.shortLabels[day.index];
}

class ExamEntry {
  final String courseCode;
  final String courseTitle;
  final DateTime date;
  final TimeSlot timeSlot;
  final bool isMidSem;

  const ExamEntry({
    required this.courseCode,
    required this.courseTitle,
    required this.date,
    required this.timeSlot,
    required this.isMidSem,
  });
}

class ExamCluster {
  final List<ExamEntry> exams;
  final DateTime startDate;
  final DateTime endDate;
  final int spanDays;

  const ExamCluster({
    required this.exams,
    required this.startDate,
    required this.endDate,
    required this.spanDays,
  });

  String get severity {
    if (exams.length >= 3 && spanDays <= 2) return 'severe';
    if (exams.length >= 2 && spanDays <= 1) return 'severe';
    return 'warning';
  }

  String get label => '${exams.length} exams in $spanDays day${spanDays > 1 ? 's' : ''}';
}
