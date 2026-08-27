import 'package:flutter/material.dart';
import '../models/academic_record.dart';
import '../models/course.dart';
import '../models/credit_mix.dart';
import '../models/timetable.dart';
import 'course_list_widget.dart';
import 'exam_dates_widget.dart';
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
  bool _showExamSchedule = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          bottom: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.report_problem_outlined,
                size: 16,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This timetable mixes credits and credit hours',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onErrorContainer,
                  ),
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
              color: scheme.onErrorContainer.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _removeButton('$unitCount in credits', CreditBasis.units, scheme),
              _removeButton(
                '$hourCount in credit hours',
                CreditBasis.hours,
                scheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _removeButton(String what, CreditBasis basis, ColorScheme scheme) {
    return OutlinedButton.icon(
      onPressed:
          widget.onRemoveBasis == null
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
    final selectedCoursesCodes =
        widget.selectedSections.map((s) => s.courseCode).toSet();
    // The two bases are kept apart because they are different quantities —
    // adding them would report a number that matches no rule the registrar has.
    final courseCredits = mix.amountFor(CreditBasis.units);
    final creditHours = mix.amountFor(CreditBasis.hours);

    final scheme = Theme.of(context).colorScheme;
    final inHours = widget.creditBasis == CreditBasis.hours;

    // Projects are worth 3 units each and have no hours figure, so they only
    // load a unit total; the counter below is hidden on an hours timetable.
    final projectCredits = widget.projectCount * 3;
    // Measured on this timetable's own basis against that basis's ceiling.
    // Reading units off an hours timetable gives 0, which never trips the cap.
    final total = inHours ? creditHours : courseCredits + projectCredits;
    final cap = capFor(widget.creditBasis);
    final isOver = total > cap;
    final canAddProject = total + 3 <= cap && widget.projectCount < 8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:
            isOver
                ? scheme.errorContainer
                : scheme.primaryContainer.withValues(
                  alpha: AppDesign.opacityLow,
                ),
        border: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: AppDesign.opacityLow),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.school,
            size: 16,
            color: isOver ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '${total % 1 == 0 ? total.toInt() : total.toStringAsFixed(1)}'
            '/${cap.toInt()} ${widget.creditBasis.label}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isOver ? scheme.error : scheme.primary,
            ),
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
                color: scheme.tertiary,
              ),
            ),
          ],
          if (selectedCoursesCodes.isNotEmpty) ...[
            Text(
              '  (${selectedCoursesCodes.length} course${selectedCoursesCodes.length != 1 ? 's' : ''})',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow),
              ),
            ),
          ],
          const Spacer(),
          // Project counter inline — credits only. A project is worth 3 units;
          // there is no hours figure for one, so counting it into an hours
          // total would be inventing a number.
          if (!inHours) ...[
            Text(
              'Projects',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(
                  alpha: AppDesign.opacityMedium,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap:
                  widget.projectCount > 0
                      ? () {
                        widget.onProjectCountChanged(widget.projectCount - 1);
                      }
                      : null,
              child: Icon(
                Icons.remove_circle_outline,
                size: 16,
                color:
                    widget.projectCount > 0
                        ? scheme.primary
                        : scheme.onSurface.withValues(
                          alpha: AppDesign.opacityLow,
                        ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${widget.projectCount}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ),
            InkWell(
              onTap:
                  canAddProject
                      ? () {
                        widget.onProjectCountChanged(widget.projectCount + 1);
                      }
                      : () {
                        if (total + 3 > cap) {
                          ToastService.showError(
                            'Cannot add project — would exceed the ${cap.toInt()} ${widget.creditBasis.label} limit',
                          );
                        }
                      },
              child: Icon(
                Icons.add_circle_outline,
                size: 16,
                color:
                    canAddProject
                        ? scheme.primary
                        : scheme.onSurface.withValues(
                          alpha: AppDesign.opacityLow,
                        ),
              ),
            ),
            if (widget.projectCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '(+$projectCredits)',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(
                    alpha: AppDesign.opacityLow,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPlanPanel() {
    final scheme = Theme.of(context).colorScheme;
    final selectedCount =
        widget.selectedSections.map((s) => s.courseCode).toSet().length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.12)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _showExamSchedule
                      ? 'Exam schedule'
                      : '$selectedCount selected course${selectedCount == 1 ? '' : 's'}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed:
                    selectedCount == 0
                        ? null
                        : () => setState(
                          () => _showExamSchedule = !_showExamSchedule,
                        ),
                icon: Icon(
                  _showExamSchedule
                      ? Icons.arrow_back_rounded
                      : Icons.event_outlined,
                  size: 17,
                ),
                label: Text(
                  _showExamSchedule ? 'Courses' : 'Exams',
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child:
                _showExamSchedule
                    ? Padding(
                      key: const ValueKey('plan-exams'),
                      padding: const EdgeInsets.all(8),
                      child: ExamDatesWidget(
                        selectedSections: widget.selectedSections,
                        courses: widget.courses,
                      ),
                    )
                    : CourseListWidget(
                      key: const ValueKey('plan-courses'),
                      courses: widget.courses,
                      selectedSections: widget.selectedSections,
                      onSectionToggle: widget.onSectionToggle,
                      showOnlySelected: true,
                      allowSectionClash: widget.allowSectionClash,
                      creditBasis: widget.creditBasis,
                    ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mix = CreditMix.of(widget.selectedSections, widget.courses);
    final scheme = Theme.of(context).colorScheme;
    final selectedCount =
        widget.selectedSections.map((s) => s.courseCode).toSet().length;

    return Column(
      children: [
        if (mix.isMixed) _buildMixWarning(mix),
        _buildStickyCreditsBar(mix),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Container(
            height: 42,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: scheme.onSurface,
              unselectedLabelColor: scheme.onSurfaceVariant,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.12),
                ),
              ),
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                Tab(text: 'Catalog  ${widget.courses.length}'),
                Tab(text: 'My Plan  $selectedCount'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              CourseListWidget(
                courses: widget.courses,
                selectedSections: widget.selectedSections,
                onSectionToggle: widget.onSectionToggle,
                record: widget.record,
                showOnlySelected: false,
                allowSectionClash: widget.allowSectionClash,
                creditBasis: widget.creditBasis,
              ),
              _buildPlanPanel(),
            ],
          ),
        ),
      ],
    );
  }
}
