import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../models/timetable_stats.dart';
import '../models/course.dart';

class ExamTimelineWidget extends StatelessWidget {
  final Timetable timetable;

  const ExamTimelineWidget({super.key, required this.timetable});

  static const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final stats = TimetableStats.fromTimetable(timetable);
    final allExams = _getAllExams();

    if (allExams.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No exam dates available for your courses',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    // Split into midsem and endsem
    final midSems = allExams.where((e) => e.isMidSem).toList();
    final endSems = allExams.where((e) => !e.isMidSem).toList();
    final midClusters = stats.examClusters.where((c) => c.exams.first.isMidSem).toList();
    final endClusters = stats.examClusters.where((c) => !c.exams.first.isMidSem).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stats.hasExamClusters)
            _buildClusterWarnings(context, stats.examClusters),
          if (midSems.isNotEmpty) ...[
            _buildSectionHeader(context, 'Midsems', midSems.length),
            const SizedBox(height: 8),
            _buildExamTimeline(context, midSems, midClusters),
          ],
          if (midSems.isNotEmpty && endSems.isNotEmpty)
            const SizedBox(height: 24),
          if (endSems.isNotEmpty) ...[
            _buildSectionHeader(context, 'Endsems', endSems.length),
            const SizedBox(height: 8),
            _buildExamTimeline(context, endSems, endClusters),
          ],
        ],
      ),
    );
  }

  List<ExamEntry> _getAllExams() {
    final exams = <ExamEntry>[];
    final seen = <String>{};

    for (final sel in timetable.selectedSections) {
      if (!seen.add(sel.courseCode)) continue;
      final course = timetable.availableCourses.where(
        (c) => c.courseCode == sel.courseCode,
      ).firstOrNull;
      if (course == null) continue;

      if (course.midSemExam != null) {
        exams.add(ExamEntry(
          courseCode: sel.courseCode,
          courseTitle: course.courseTitle,
          date: course.midSemExam!.date,
          timeSlot: course.midSemExam!.timeSlot,
          isMidSem: true,
        ));
      }
      if (course.endSemExam != null) {
        exams.add(ExamEntry(
          courseCode: sel.courseCode,
          courseTitle: course.courseTitle,
          date: course.endSemExam!.date,
          timeSlot: course.endSemExam!.timeSlot,
          isMidSem: false,
        ));
      }
    }

    exams.sort((a, b) {
      final dc = a.date.compareTo(b.date);
      if (dc != 0) return dc;
      return a.timeSlot.index.compareTo(b.timeSlot.index);
    });

    return exams;
  }

  Widget _buildClusterWarnings(BuildContext context, List<ExamCluster> clusters) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Text(
                'Exam Density Warnings',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...clusters.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${c.label}: ${c.exams.map((e) => e.courseCode).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget _buildExamTimeline(BuildContext context, List<ExamEntry> exams, List<ExamCluster> clusters) {
    // Group exams by date
    final byDate = <DateTime, List<ExamEntry>>{};
    for (final exam in exams) {
      byDate.putIfAbsent(exam.date, () => []).add(exam);
    }

    final dates = byDate.keys.toList()..sort();
    final clusterDates = <DateTime>{};
    for (final c in clusters) {
      for (final e in c.exams) {
        clusterDates.add(e.date);
      }
    }

    return Column(
      children: [
        for (int i = 0; i < dates.length; i++) ...[
          _buildDateRow(context, dates[i], byDate[dates[i]]!, clusterDates.contains(dates[i])),
          if (i < dates.length - 1)
            _buildGapIndicator(context, dates[i], dates[i + 1]),
        ],
      ],
    );
  }

  Widget _buildDateRow(BuildContext context, DateTime date, List<ExamEntry> exams, bool isCluster) {
    final scheme = Theme.of(context).colorScheme;
    final weekDay = _weekDays[date.weekday - 1];
    final dateStr = '$weekDay, ${date.day} ${_monthNames[date.month]}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCluster
            ? scheme.errorContainer.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: isCluster ? Border.all(color: scheme.error.withValues(alpha: 0.2)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCluster ? scheme.error : null,
                  ),
                ),
                if (exams.length > 1)
                  Text(
                    '${exams.length} exams',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isCluster ? scheme.error.withValues(alpha: 0.7) : scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: exams.map((exam) {
                final slotName = TimeSlotInfo.timeSlotNames[exam.timeSlot] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isCluster ? scheme.error : scheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exam.courseCode,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              slotName,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGapIndicator(BuildContext context, DateTime from, DateTime to) {
    final gap = to.difference(from).inDays;
    if (gap <= 1) return const SizedBox(height: 2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Container(
            width: 1,
            height: 16,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '$gap days gap',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
