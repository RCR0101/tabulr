import 'package:flutter/material.dart';

import '../models/bug_report.dart';
import '../models/timetable_display.dart';
import '../utils/demo_data.dart';
import '../utils/design_constants.dart';
import '../utils/guide_content.dart';
import 'academic_calendar_list.dart';
import 'bug_status_chip.dart';
import 'charts/cgpa_trajectory_chart.dart';
import 'charts/exam_timeline_chart.dart';
import 'charts/weekly_load_chart.dart';
import 'clash_warnings_widget.dart';
import 'course_list_widget.dart';
import 'courses_tab_widget.dart';
import 'exam_dates_widget.dart';
import 'generated_timetable_card.dart';
import 'generator/ranking_importance_panel.dart';
import 'timetable/course_palette.dart';
import 'timetable/timetable_agenda.dart';
import 'timetable/timetable_grid.dart';
import 'timetable_stats_panel.dart';

class GuideVisualFrame extends StatelessWidget {
  const GuideVisualFrame({super.key, required this.visual, this.enabled = true});

  final GuideVisual visual;

  final bool enabled;

  static double _minWidthOf(GuideVisual visual) => switch (visual) {
        GuideVisual.coursesTab => 560,
        _ => 360,
      };

  static EdgeInsets _padOf(GuideVisual visual) => switch (visual) {
        GuideVisual.clashes ||
        GuideVisual.stats ||
        GuideVisual.examDates ||
        GuideVisual.coursesTab ||
        GuideVisual.generatorResult ||
        GuideVisual.academicCalendar =>
          EdgeInsets.zero,
        GuideVisual.weekGrid ||
        GuideVisual.agenda ||
        GuideVisual.courseCards =>
          const EdgeInsets.all(AppDesign.spacingSm),
        GuideVisual.weeklyLoad ||
        GuideVisual.examTimeline ||
        GuideVisual.rankingImportance ||
        GuideVisual.cgpaTrajectory ||
        GuideVisual.bugStatuses =>
          const EdgeInsets.all(AppDesign.spacingMd),
      };

  static String captionOf(GuideVisual visual) => switch (visual) {
        GuideVisual.weekGrid => 'The week grid, vertical layout',
        GuideVisual.agenda => 'The same week as an agenda',
        GuideVisual.courseCards => 'Course cards, with their sections',
        GuideVisual.coursesTab => 'The editor\'s course list and credit bar',
        GuideVisual.clashes => 'A clash banner, class and exam',
        GuideVisual.stats => 'TT Stats for this timetable',
        GuideVisual.weeklyLoad => 'Contact hours per day',
        GuideVisual.generatorResult => 'One generated option, ranked',
        GuideVisual.rankingImportance => 'Telling the generator what matters',
        GuideVisual.examTimeline => 'Midsem and compre windows',
        GuideVisual.examDates => 'The exam table, sortable',
        GuideVisual.academicCalendar => 'The semester calendar',
        GuideVisual.cgpaTrajectory => 'Four graded semesters',
        GuideVisual.bugStatuses => 'The states a report moves through',
      };

  Widget _build(BuildContext context) {
    final palette = CoursePalette.forCourses(
      context,
      DemoData.courses.map((c) => c.courseCode),
    );

    return switch (visual) {
      GuideVisual.weekGrid => SizedBox(
          height: 420,
          child: TimetableGrid(
            slots: DemoData.slots,
            layout: TimetableLayout.vertical,
            size: TimetableSize.compact,
            palette: palette,
          ),
        ),
      GuideVisual.agenda => SizedBox(
          height: 340,
          child: TimetableAgenda(slots: DemoData.slots, palette: palette),
        ),
      GuideVisual.courseCards => SizedBox(
          height: 420,
          child: CourseListWidget(
            courses: DemoData.courses,
            catalog: DemoData.courses,
            selectedSections: DemoData.selections,
            onSectionToggle: (_, __, ___) {},
          ),
        ),
      GuideVisual.coursesTab => SizedBox(
          height: 460,
          child: CoursesTabWidget(
            courses: DemoData.courses,
            selectedSections: DemoData.selections,
            onSectionToggle: (_, __, ___) {},
            projectCount: 0,
            onProjectCountChanged: (_) {},
          ),
        ),
      GuideVisual.clashes => ClashWarningsWidget(warnings: DemoData.clashes),
      GuideVisual.generatorResult => GeneratedTimetableCard(
          ranked: DemoData.rankedTimetable,
          onSelect: () {},
        ),
      GuideVisual.rankingImportance => RankingImportancePanel(
          importance: DemoData.axisImportance,
          onChanged: (_, __) {},
          onReset: () {},
        ),
      GuideVisual.academicCalendar => SizedBox(
          height: 360,
          child: AcademicCalendarAgenda(events: DemoData.calendarEvents),
        ),
      GuideVisual.bugStatuses => Wrap(
          spacing: AppDesign.spacingSm,
          runSpacing: AppDesign.spacingSm,
          children: [
            for (final status in BugStatus.values) BugStatusChip(status: status),
          ],
        ),
      GuideVisual.stats => TimetableStatsPanel(timetable: DemoData.timetable),
      GuideVisual.weeklyLoad =>
        const WeeklyLoadChart(hoursPerDay: DemoData.hoursPerDay),
      GuideVisual.examTimeline => ExamTimelineChart(
          exams: DemoData.exams,
          clusters: DemoData.examClusters,
        ),
      GuideVisual.examDates => SizedBox(
          height: 360,
          child: ExamDatesWidget(
            selectedSections: DemoData.selections,
            courses: DemoData.courses,
          ),
        ),
      GuideVisual.cgpaTrajectory => const CgpaTrajectoryChart(
          points: DemoData.trajectory,
          targetCgpa: 8.5,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: AppDesign.borderRadiusMd,
              border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
            ),
            clipBehavior: Clip.antiAlias,
            child: !enabled
                ? const SizedBox(height: 88)
                : LayoutBuilder(
              builder: (context, constraints) {
                final pad = _padOf(visual);
                final wanted = _minWidthOf(visual) + pad.horizontal;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: constraints.maxWidth < wanted
                        ? wanted
                        : constraints.maxWidth,
                    child: Padding(padding: pad, child: _build(context)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppDesign.spacingXs + 2),
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 12, color: scheme.primary.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${captionOf(visual)} — this is the live component, with sample data',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppDesign.muted(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
