import 'course.dart';
import 'timetable.dart';

class TimetableStats {
  final int totalHoursPerWeek;
  final double totalCredits;
  final int courseCount;
  final DayOfWeek busiestDay;
  final int busiestDayHours;
  final int freeDayCount;
  final List<DayOfWeek> freeDays;
  final int longestGapHours;
  final DayOfWeek? longestGapDay;
  final Map<DayOfWeek, int> hoursPerDay;
  final List<ExamCluster> examClusters;

  const TimetableStats({
    required this.totalHoursPerWeek,
    required this.totalCredits,
    required this.courseCount,
    required this.busiestDay,
    required this.busiestDayHours,
    required this.freeDayCount,
    required this.freeDays,
    required this.longestGapHours,
    required this.longestGapDay,
    required this.hoursPerDay,
    required this.examClusters,
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
  );

  static TimetableStats fromTimetable(Timetable timetable) {
    if (timetable.selectedSections.isEmpty) return _empty;

    final dayHours = <DayOfWeek, Set<int>>{};
    final uniqueCourses = <String>{};
    double totalCredits = 0;

    for (final sel in timetable.selectedSections) {
      if (uniqueCourses.add(sel.courseCode)) {
        final course = timetable.availableCourses.where(
          (c) => c.courseCode == sel.courseCode,
        ).firstOrNull;
        if (course != null) totalCredits += course.totalCredits;
      }

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

    // Longest gap: largest break between consecutive classes on any day
    var longestGap = 0;
    DayOfWeek? longestGapDay;
    for (final entry in dayHours.entries) {
      final sorted = entry.value.toList()..sort();
      if (sorted.length < 2) continue;
      for (int i = 1; i < sorted.length; i++) {
        final gap = sorted[i] - sorted[i - 1] - 1;
        if (gap > longestGap) {
          longestGap = gap;
          longestGapDay = entry.key;
        }
      }
    }

    // Exam clusters
    final examClusters = _computeExamClusters(timetable);

    return TimetableStats(
      totalHoursPerWeek: totalHours,
      totalCredits: totalCredits,
      courseCount: uniqueCourses.length,
      busiestDay: busiestDay,
      busiestDayHours: busiestHours,
      freeDayCount: freeDays.length,
      freeDays: freeDays,
      longestGapHours: longestGap,
      longestGapDay: longestGapDay,
      hoursPerDay: hoursPerDay,
      examClusters: examClusters,
    );
  }

  static List<ExamCluster> _computeExamClusters(Timetable timetable) {
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

    if (examEntries.isEmpty) return [];

    examEntries.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.timeSlot.index.compareTo(b.timeSlot.index);
    });

    // Group exams within 2-day windows to find clusters
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

  static String _shortDay(DayOfWeek day) => switch (day) {
    DayOfWeek.M => 'Mon',
    DayOfWeek.T => 'Tue',
    DayOfWeek.W => 'Wed',
    DayOfWeek.Th => 'Thu',
    DayOfWeek.F => 'Fri',
    DayOfWeek.S => 'Sat',
  };
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
