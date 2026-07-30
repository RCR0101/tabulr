import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/academic_record.dart';
import '../models/course.dart';
import '../models/credit_mix.dart';
import '../models/timetable.dart';
import 'course_list_widget.dart';
import 'exam_dates_widget.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';

class CoursesTabWidget extends StatefulWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String, String, bool) onSectionToggle;
  final int projectCount;
  final ValueChanged<int> onProjectCountChanged;

  /// Marks courses the student has already cleared.
  final AcademicRecord record;

  /// The editor's "allow section clashes" bypass — forwarded so a conflicting
  /// section's Add button stays tappable.
  final bool allowSectionClash;

  /// What this timetable counts in, so a course offered both ways is shown and
  /// added on the same basis as the timetable holding it.
  final CreditBasis creditBasis;

  /// Drops every course counted in one basis — the way out of a mixed
  /// timetable.
  final void Function(CreditBasis basis)? onRemoveBasis;

  const CoursesTabWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
    required this.projectCount,
    required this.onProjectCountChanged,
    this.record = AcademicRecord.empty,
    this.allowSectionClash = false,
    this.creditBasis = CreditBasis.units,
    this.onRemoveBasis,
  });

  @override
  State<CoursesTabWidget> createState() => _CoursesTabWidgetState();
}

class _CoursesTabWidgetState extends State<CoursesTabWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// The warning that a timetable holds both units and credit hours, with the
  /// two ways out of it.
  ///
  /// Not a refusal: the editor cannot know which half is the mistake, and a
  /// student who has just switched batches would lose work to a rule that
  /// simply blocked the second add. It states the problem in the student's
  /// terms and offers to drop either side.
  Widget _buildMixWarning(CreditMix mix) {
    final scheme = Theme.of(context).colorScheme;
    final unitCount = mix.coursesFor(CreditBasis.units).length;
    final hourCount = mix.coursesFor(CreditBasis.hours).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        border: Border(
            bottom: BorderSide(color: scheme.error.withValues(alpha: 0.4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem_outlined,
                  size: 16, color: scheme.onErrorContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This timetable mixes credits and credit hours',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Credit hours are how the 2026 batch onwards registers; credits are '
            'how everyone else does. You can only register for one of them, so '
            'drop the set that is not yours.',
            style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onErrorContainer.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _removeButton(
                  '$unitCount in credits', CreditBasis.units, scheme),
              _removeButton(
                  '$hourCount in credit hours', CreditBasis.hours, scheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _removeButton(String what, CreditBasis basis, ColorScheme scheme) {
    return OutlinedButton.icon(
      onPressed: widget.onRemoveBasis == null
          ? null
          : () => widget.onRemoveBasis!(basis),
      icon: const Icon(Icons.delete_outline, size: 15),
      label: Text('Remove $what', style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onErrorContainer,
        side: BorderSide(color: scheme.onErrorContainer.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 32),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildStickyCreditsBar(CreditMix mix) {
    final selectedCoursesCodes = widget.selectedSections.map((s) => s.courseCode).toSet();
    // Units only. Credit hours are counted and shown separately because they
    // are a different quantity — adding them here would report a number that
    // matches no rule the registrar has.
    final courseCredits = mix.amountFor(CreditBasis.units);
    final creditHours = mix.amountFor(CreditBasis.hours);

    final projectCredits = widget.projectCount * 3;
    final totalCredits = courseCredits + projectCredits;
    final scheme = Theme.of(context).colorScheme;
    final inHours = widget.creditBasis == CreditBasis.hours;
    // Credit hours have no published ceiling, so there is nothing to be over
    // and nothing to print after the slash — "0/25 credits" beside a
    // credit-hours load is a limit nobody set, against a count it is not even
    // measuring.
    final cap = capFor(widget.creditBasis);
    final isOver = cap != null && totalCredits > cap;
    final canAddProject =
        (cap == null || totalCredits + 3 <= cap) && widget.projectCount < 8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOver ? scheme.errorContainer : scheme.primaryContainer.withValues(alpha: AppDesign.opacityLow),
        border: Border(bottom: BorderSide(color: scheme.outline.withValues(alpha: AppDesign.opacityLow))),
      ),
      child: Row(
        children: [
          Icon(Icons.school, size: 16, color: isOver ? scheme.error : scheme.primary),
          const SizedBox(width: 6),
          Text(
            inHours
                ? '${creditHours % 1 == 0 ? creditHours.toInt() : creditHours.toStringAsFixed(1)} credit hours'
                : '${totalCredits % 1 == 0 ? totalCredits.toInt() : totalCredits.toStringAsFixed(1)}'
                    '${cap == null ? '' : '/${cap.toInt()}'} credits',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isOver ? scheme.error : scheme.primary),
          ),
          // Only when the timetable is NOT already reporting in hours — this is
          // the mixed case, which the warning above is about.
          if (!inHours && creditHours > 0) ...[
            const SizedBox(width: 8),
            Text(
              '+ ${creditHours % 1 == 0 ? creditHours.toInt() : creditHours.toStringAsFixed(1)} credit hours',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.tertiary),
            ),
          ],
          if (selectedCoursesCodes.isNotEmpty) ...[
            Text(
              '  (${selectedCoursesCodes.length} course${selectedCoursesCodes.length != 1 ? 's' : ''})',
              style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
            ),
          ],
          const Spacer(),
          // Project counter inline — credits only. A project is worth 3 units;
          // there is no hours figure for one, so counting it into an hours
          // total would be inventing a number.
          if (!inHours) ...[
          Text('Projects', style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium))),
          const SizedBox(width: 4),
          InkWell(
            onTap: widget.projectCount > 0 ? () { widget.onProjectCountChanged(widget.projectCount - 1); } : null,
            child: Icon(Icons.remove_circle_outline, size: 16, color: widget.projectCount > 0 ? scheme.primary : scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${widget.projectCount}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
          ),
          InkWell(
            onTap: canAddProject
                ? () { widget.onProjectCountChanged(widget.projectCount + 1); }
                : () { if (totalCredits + 3 > AppLimits.semesterCreditCap) ToastService.showError('Cannot add project — would exceed ${AppLimits.semesterCreditCap.toInt()} credit limit'); },
            child: Icon(Icons.add_circle_outline, size: 16, color: canAddProject ? scheme.primary : scheme.onSurface.withValues(alpha: AppDesign.opacityLow)),
          ),
          if (widget.projectCount > 0) ...[
            const SizedBox(width: 4),
            Text('(+$projectCredits)', style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow))),
          ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);
    
    final mix = CreditMix.of(widget.selectedSections, widget.courses);

    return Column(
      children: [
        if (mix.isMixed) _buildMixWarning(mix),
        _buildStickyCreditsBar(mix),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
            indicatorColor: Theme.of(context).colorScheme.primary,
            dividerColor: Theme.of(context).colorScheme.outline,
            isScrollable: false,
            labelPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 4) : null,
            tabAlignment: TabAlignment.fill,
            tabs: isMobile ? [
              Tab(
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        'Search',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${widget.courses.length})',
                        style: TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Tab(
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        'Selected',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${widget.selectedSections.map((s) => s.courseCode).toSet().length})',
                        style: TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Tab(
                height: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event, size: 16),
                      const SizedBox(height: 2),
                      Text(
                        'Exams',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] : [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search, size: 16),
                    const SizedBox(width: 4),
                    Text('Search (${widget.courses.length})', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school, size: 16),
                    const SizedBox(width: 4),
                    Text('My Courses (${widget.selectedSections.map((s) => s.courseCode).toSet().length})', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16),
                    const SizedBox(width: 4),
                    const Text('Exams', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Search tab - shows all courses without reordering
              CourseListWidget(
                courses: widget.courses,
                selectedSections: widget.selectedSections,
                onSectionToggle: widget.onSectionToggle,
                record: widget.record,
                showOnlySelected: false,
                allowSectionClash: widget.allowSectionClash,
                creditBasis: widget.creditBasis,
              ),
              // My Courses tab - shows only selected courses
              CourseListWidget(
                courses: widget.courses,
                selectedSections: widget.selectedSections,
                onSectionToggle: widget.onSectionToggle,
                showOnlySelected: true,
                allowSectionClash: widget.allowSectionClash,
                creditBasis: widget.creditBasis,
              ),
              // Exam schedule tab
              widget.selectedSections.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No courses selected',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add courses to see exam schedules',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ExamDatesWidget(
                        selectedSections: widget.selectedSections,
                        courses: widget.courses,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}