import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../constants/app_constants.dart';
import '../models/academic_record.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import 'common/course_record_badge.dart';
import '../utils/course_utils.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/campus_service.dart';
import '../services/core/clash_detector.dart';
import '../utils/design_constants.dart';

class CourseListWidget extends StatelessWidget {
  final List<Course> courses;
  final List<SelectedSection> selectedSections;
  final Function(String courseCode, String sectionId, bool isSelected) onSectionToggle;
  final bool showOnlySelected;

  /// Catalog used to resolve [selectedSections] back to courses for the
  /// exam-clash checks. Defaults to [courses]. The elective browsers pass the
  /// full catalog because their [courses] holds electives only, so a CDC
  /// already on the timetable would otherwise be invisible to those checks.
  final List<Course>? catalog;

  /// Marks courses the student has already taken. Empty by default, in which
  /// case nothing extra is drawn.
  final AcademicRecord record;

  /// Whether sections can be added to a timetable from here.
  ///
  /// False when the browser was opened without a timetable — from the timetable
  /// LIST rather than from inside the editor. The Add button used to render
  /// anyway, wired to a no-op callback, so it looked live and silently did
  /// nothing. Browsing is still the point of the screen; only the action goes.
  final bool selectable;

  /// The editor's "allow section clashes" bypass. When on, a schedule
  /// conflict no longer disables the Add button — the reason line stays, so
  /// the student still sees what they're colliding with. Duplicate section
  /// types stay blocked either way.
  final bool allowSectionClash;

  /// What the host timetable counts in. A course offered both ways is shown on
  /// this basis — the timetable-level toggle decides, so a card cannot put a
  /// course on the grid counted differently from the timetable holding it.
  ///
  /// Null in the browsers with no timetable behind them, where the course's own
  /// first variant is all there is to show.
  final CreditBasis? creditBasis;

  CourseListWidget({
    super.key,
    required this.courses,
    required this.selectedSections,
    required this.onSectionToggle,
    this.showOnlySelected = false,
    this.catalog,
    this.record = AcademicRecord.empty,
    this.selectable = true,
    this.allowSectionClash = false,
    this.creditBasis,
  });

  late final Set<String> _selectedKeys = {
    for (final s in selectedSections) '${s.courseCode}|${s.sectionId}',
  };

  late final Set<String> _selectedTypeKeys = {
    for (final s in selectedSections) '${s.courseCode}|${s.section.type}',
  };

  // Built once per widget instance rather than per tile. _getCourseClashes runs
  // for every visible row, and it used to resolve each selected section's course
  // with a firstWhere over the ~2,800-course list — O(rows x selected x catalog)
  // on every scroll. The index makes the lookup O(1); _selectedCourses caches
  // the resolved set the exam checks iterate.
  late final Map<String, Course> _courseIndex = {
    for (final c in catalog ?? courses) c.courseCode: c,
  };

  late final List<Course> _selectedCourses = {
    for (final s in selectedSections) s.courseCode,
  }.map((code) => _courseIndex[code]).whereType<Course>().toList();

  bool _isSectionSelected(String courseCode, String sectionId) {
    return _selectedKeys.contains('$courseCode|$sectionId');
  }

  bool _isSectionTypeAlreadySelected(String courseCode, SectionType type) {
    return _selectedTypeKeys.contains('$courseCode|$type');
  }

  /// Returns a human-readable conflict description for this specific section,
  /// or null if no conflict.
  String? _getSectionConflict(Section section, String courseCode) {
    if (selectedSections.isEmpty) return null;
    final otherSections = selectedSections
        .where((s) => s.courseCode != courseCode)
        .toList();
    if (otherSections.isEmpty) return null;

    final conflicts = ClashDetector.checkScheduleConflicts(section, otherSections);
    if (conflicts.isEmpty) return null;

    final first = conflicts.first;
    return 'Clashes with ${first.conflictingCourse} ${first.conflictingSectionId} (${first.time})';
  }

  String _getSelectedSectionsText(String courseCode) {
    final courseSections = selectedSections
        .where((s) => s.courseCode == courseCode)
        .toList();

    if (courseSections.isEmpty) return '';

    final Map<SectionType, String> typeToSection = {};
    for (final section in courseSections) {
      typeToSection[section.section.type] = section.sectionId;
    }

    final List<String> parts = [];
    for (final type in [SectionType.L, SectionType.T, SectionType.P]) {
      if (typeToSection.containsKey(type)) {
        parts.add('${typeToSection[type]}');
      }
    }

    return parts.join(' ');
  }

  /// Check if a course clashes with already-selected courses (exam or schedule).
  List<String> _getCourseClashes(Course course) {
    if (selectedSections.isEmpty) return [];
    if (selectedSections.any((s) => s.courseCode == course.courseCode)) return [];

    final clashes = <String>[];

    // Check mid-sem exam clashes
    if (course.midSemExam != null) {
      for (final selectedCourse in _selectedCourses) {
        if (selectedCourse.courseCode == course.courseCode) continue;
        if (selectedCourse.midSemExam != null &&
            ClashDetector.examDatesConflict(course.midSemExam!, selectedCourse.midSemExam!)) {
          clashes.add('Midsem exam clashes with ${selectedCourse.courseCode}');
          break;
        }
      }
    }

    // Check end-sem/comprehensive exam clashes
    if (course.endSemExam != null) {
      for (final selectedCourse in _selectedCourses) {
        if (selectedCourse.courseCode == course.courseCode) continue;
        if (selectedCourse.endSemExam != null &&
            ClashDetector.examDatesConflict(course.endSemExam!, selectedCourse.endSemExam!)) {
          clashes.add('Compre exam clashes with ${selectedCourse.courseCode}');
          break;
        }
      }
    }

    // Check each section type individually — are ALL sections of that type blocked?
    final sectionsByType = <SectionType, List<Section>>{};
    for (final section in course.sections) {
      sectionsByType.putIfAbsent(section.type, () => []).add(section);
    }

    for (final entry in sectionsByType.entries) {
      final type = entry.key;
      final sections = entry.value;
      final allBlocked = sections.every((section) {
        final conflicts = ClashDetector.checkScheduleConflicts(section, selectedSections);
        return conflicts.isNotEmpty;
      });
      if (allBlocked) {
        final typeName = type == SectionType.L ? 'lecture' :
                         type == SectionType.P ? 'lab' : 'tutorial';
        clashes.add('Every $typeName section clashes with your timetable');
      }
    }

    return clashes;
  }

  @override
  Widget build(BuildContext context) {
    List<Course> displayCourses;

    if (showOnlySelected) {
      final selectedCodes = <String>{for (final s in selectedSections) s.courseCode};
      displayCourses = courses.where((course) =>
        selectedCodes.contains(course.courseCode)
      ).toList();
    } else {
      displayCourses = courses;
    }

    if (displayCourses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showOnlySelected ? Icons.school_outlined : Icons.search_off,
              size: 64,
              color: AppDesign.muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              showOnlySelected ? 'No courses selected' : 'No courses found',
              style: TextStyle(
                fontSize: 16,
                color: AppDesign.muted(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showOnlySelected
                ? 'Go to Search tab to add courses'
                : 'Try adjusting your search criteria',
              style: TextStyle(
                fontSize: 12,
                color: AppDesign.muted(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      // Pre-build extra rows off-screen so fast wheel/trackpad scrolling
      // doesn't reveal blank gaps before items paint.
      scrollCacheExtent: ScrollCacheExtent.pixels(800),
      padding: ResponsiveService.getAdaptivePadding(
        context,
        EdgeInsets.fromLTRB(
          6,
          10,
          6,
          ResponsiveService.isMobile(context) ? 100 : 12
        ),
      ),
      itemCount: displayCourses.length,
      itemBuilder: (context, index) {
        final course = displayCourses[index];
        final isSelectedCourse = selectedSections.any(
          (s) => s.courseCode == course.courseCode,
        );
        final clashes = _getCourseClashes(course);

        return _CourseCard(
          course: course,
          record: record,
          isSelectedCourse: isSelectedCourse,
          showOnlySelected: showOnlySelected,
          clashes: clashes,
          selectedSummary: _getSelectedSectionsText(course.courseCode),
          selectable: selectable,
          sectionStates: [
            for (final section in course.sections)
              () {
                final isSelected =
                    _isSectionSelected(course.courseCode, section.sectionId);
                return _SectionState(
                  section: section,
                  isSelected: isSelected,
                  // Not a clash: you already picked an L (or T/P) for this
                  // course, so the siblings are unavailable until you swap.
                  // Rendered differently from a clash, because it means
                  // something entirely different to the student.
                  typeTaken: !isSelected &&
                      _isSectionTypeAlreadySelected(
                          course.courseCode, section.type),
                  conflict: isSelected
                      ? null
                      : _getSectionConflict(section, course.courseCode),
                  clashAllowed: allowSectionClash,
                );
              }(),
          ],
          onToggle: (sectionId, isSelected) =>
              onSectionToggle(course.courseCode, sectionId, isSelected),
          creditBasis: creditBasis,
        );
      },
    );
  }
}

/// One section's state, resolved once by [CourseListWidget] so the card stays
/// presentational.
class _SectionState {
  const _SectionState({
    required this.section,
    required this.isSelected,
    required this.typeTaken,
    required this.conflict,
    this.clashAllowed = false,
  });

  final Section section;
  final bool isSelected;

  /// Another section of this same component is already on the timetable.
  /// Distinct from [conflict]: nothing clashes, you have simply already chosen.
  final bool typeTaken;

  /// The editor's section-clash bypass: a conflict informs but no longer
  /// blocks.
  final bool clashAllowed;

  /// Human-readable schedule collision with the current timetable, or null.
  final String? conflict;

  bool get blocked => typeTaken || (conflict != null && !clashAllowed);
}

/// A course, its metadata and its sections.
///
/// Rewritten from a hand-decorated Container + ExpansionTile whose subtitle was
/// a column of six labelled sentences ("Instructor in Charge: …", "Credits: …",
/// "MidSem: …"). That read as roughly six lines collapsed and eighteen expanded
/// for a six-section course — poor for a screen whose whole job is scanning.
/// Metadata is now one wrapped row of compact facts, and each section is one
/// line instead of three.
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.record,
    required this.isSelectedCourse,
    required this.showOnlySelected,
    required this.clashes,
    required this.selectedSummary,
    required this.selectable,
    required this.sectionStates,
    required this.onToggle,
    this.creditBasis,
  });

  final Course course;
  final AcademicRecord record;
  final bool isSelectedCourse;
  final bool showOnlySelected;
  final List<String> clashes;
  final String selectedSummary;
  final bool selectable;
  final List<_SectionState> sectionStates;
  final void Function(String sectionId, bool isSelected) onToggle;
  final CreditBasis? creditBasis;

  /// The variant in force for this card: the one matching the timetable's
  /// basis, or the course's own when there is no timetable to answer to.
  CourseVariant get _variant =>
      (creditBasis == null ? null : course.variantOn(creditBasis!)) ??
      course.variants.first;

  /// Whether to spell out which com cod this is — only worth the line when the
  /// course is printed more than one way and the student has to register under
  /// the right one.
  bool get _showsComCode => course.hasVariantChoice && _variant.comCode > 0;

  bool get _hasClashes => clashes.isNotEmpty;
  bool get _highlight => isSelectedCourse && !showOnlySelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Tonal surfaces rather than a hand-rolled boxShadow. The old card drew its
    // own shadow, which meant wrapping the contents in a transparent Material
    // just to get ink splashes back on top of it.
    final Color surface;
    final Color? outline;
    if (_hasClashes) {
      // Tinted with the error colour rather than merely a duller grey. Greys
      // differ by a few percent lightness between themes, so "is this one
      // available?" was not answerable at a glance on every theme — a hue
      // shift is, whatever the palette.
      surface = scheme.errorContainer.withValues(alpha: 0.22);
      outline = scheme.error.withValues(alpha: 0.5);
    } else if (_highlight) {
      surface = scheme.primaryContainer.withValues(alpha: 0.35);
      outline = scheme.primary.withValues(alpha: 0.45);
    } else {
      surface = scheme.surfaceContainerLow;
      outline = scheme.outlineVariant.withValues(alpha: 0.5);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      elevation: 0,
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outline),
      ),
      child: Theme(
        // The divider the ExpansionTile draws fights the card outline.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // The clash banner sits OUTSIDE the ExpansionTile, not among its
        // children: a course you cannot take must say so while collapsed,
        // otherwise the warning is hidden behind a tap.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              childrenPadding: const EdgeInsets.only(bottom: 10),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: _header(context),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 9, bottom: 4),
                child: _metadata(context),
              ),
              children: [
                for (final state in sectionStates) _sectionRow(context, state),
              ],
            ),
            if (_hasClashes) _clashFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      course.courseCode,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                        color: _hasClashes
                            ? scheme.onSurface.withValues(alpha: 0.55)
                            : _highlight
                                ? scheme.primary
                                : scheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_hasClashes) ...[
                    const SizedBox(width: 8),
                    // Colour alone is not enough — it fails for colour-blind
                    // users and washes out on some themes. The word is the
                    // affordance; the tint reinforces it.
                    _pill(context, "Can't take", scheme.error, filled: true),
                  ],
                  if (_highlight && selectedSummary.isEmpty) ...[
                    const SizedBox(width: 8),
                    _pill(context, 'Added', scheme.primary, filled: true),
                  ],
                ],
              ),
              if (course.courseTitle.isNotEmpty &&
                  course.courseTitle != course.courseCode)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    course.courseTitle,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        CourseRecordBadge(record: record, courseCode: course.courseCode),
      ],
    );
  }

  /// One wrapped row of facts, replacing five labelled sentences.
  Widget _metadata(BuildContext context) {
    final ic = CourseUtils.getInstructorInCharge(course);

    // The clock time, never the slot code. "MS2" and "FN" are registrar
    // shorthand that a first-year has no way to decode; the start time needs
    // no explaining. Only the start is shown — the end adds width, not meaning.
    String examLabel(ExamSchedule e) {
      final slot = TimeSlotInfo.getTimeSlotName(e.timeSlot,
          campus: CampusService.campusId);
      // Booklet slots come through as "9:30AM-11:00AM"; give the meridiem the
      // space it should have had.
      final start = slot
          .split('-')
          .first
          .trim()
          .replaceAllMapped(RegExp(r'(\d)(AM|PM)'), (m) => '${m[1]} ${m[2]}');
      final when = '${e.date.day} ${_month(e.date.month)}';
      return start.isEmpty ? when : '$when, $start';
    }

    return Wrap(
      spacing: 16,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _fact(
            context,
            Icons.workspace_premium_outlined,
            _showsComCode
                ? '${_creditLabel(course, _variant)}  ·  com ${_variant.comCode}'
                : _creditLabel(course, _variant)),
        if (course.midSemExam != null)
          _fact(context, Icons.event_outlined,
              'Midsem ${examLabel(course.midSemExam!)}'),
        if (course.endSemExam != null)
          _fact(context, Icons.event_available_outlined,
              'Compre ${examLabel(course.endSemExam!)}'),
        // Last: the widest value, and the one a student scans for least often.
        // Labelled, because a bare name beside dates and credits reads as
        // unexplained.
        if (ic.isNotEmpty)
          _fact(context, Icons.person_outline, 'In-Charge: $ic', wide: true),
        if (selectedSummary.isNotEmpty)
          _fact(context, Icons.check_circle_outline,
              'Selected: $selectedSummary',
              wide: true, color: Theme.of(context).colorScheme.primary),
      ],
    );
  }

  /// "4U · 3L 1P" — units first, then the breakdown, zero parts omitted.
  ///
  /// Units lead because they are what counts toward the semester cap, and they
  /// are NOT always L + P: projects and theses print as "- - 3" in the booklet,
  /// so the breakdown alone would be wrong as often as it is confusing. A
  /// course with no lecture or lab component shows the units and nothing else,
  /// rather than a row of zeroes.
  ///
  /// A course stated only in contact hours has no unit count to lead with, so
  /// it says so instead of printing "0U".
  static String _creditLabel(Course course, CourseVariant variant) {
    if (variant.isInHours) return '${_num(variant.creditHours)} credit hours';
    final parts = <String>[
      if (course.lectureCredits > 0) '${_num(course.lectureCredits)}L',
      if (course.practicalCredits > 0) '${_num(course.practicalCredits)}P',
    ];
    final units = '${_num(variant.credits)}U';
    return parts.isEmpty ? units : '$units · ${parts.join(' ')}';
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _fact(BuildContext context, IconData icon, String text,
      {bool wide = false, Color? color}) {
    final tint = color ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68);
    return ConstrainedBox(
      // A wide fact takes the whole row rather than sharing it, so a long list
      // of names wraps onto its own lines instead of being truncated. Nothing
      // here is decorative — a cut-off instructor is a missing answer.
      constraints: BoxConstraints(maxWidth: wide ? double.infinity : 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: tint),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: tint,
                fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color color,
      {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  /// One line per section, where the old card used three.
  Widget _sectionRow(BuildContext context, _SectionState state) {
    final scheme = Theme.of(context).colorScheme;
    final section = state.section;
    final dimmed = state.blocked && !state.isSelected;

    // Every row keeps a filled surface, so an unavailable one reads as a
    // deliberate state rather than a half-transparent version of a normal row —
    // which is what made the expanded list look patchy.
    final Color rowColor;
    final Color rowBorder;
    if (state.isSelected) {
      rowColor = scheme.primary.withValues(alpha: 0.13);
      rowBorder = scheme.primary.withValues(alpha: 0.45);
    } else if (state.conflict != null) {
      rowColor = scheme.errorContainer.withValues(alpha: 0.28);
      rowBorder = scheme.error.withValues(alpha: 0.28);
    } else if (state.typeTaken) {
      rowColor = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
      rowBorder = scheme.outlineVariant.withValues(alpha: 0.5);
    } else {
      rowColor = scheme.surfaceContainerLowest.withValues(alpha: 0.7);
      rowBorder = scheme.outlineVariant.withValues(alpha: 0.45);
    }

    // Text stays legible even when the row is unavailable: dimming it to 45%
    // made blocked rows genuinely hard to read, which is not the same as
    // marking them unavailable.
    final textColor = dimmed
        ? scheme.onSurface.withValues(alpha: 0.7)
        : scheme.onSurface;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      constraints: BoxConstraints(
        minHeight: ResponsiveService.getTouchTargetSize(context),
      ),
      decoration: BoxDecoration(
        color: rowColor,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: rowBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      section.sectionId,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // Schedule and room on the section's own line, instead
                        // of a "Room:" and a "Schedule:" line beneath it.
                        [
                          _compactSchedule(section.schedule),
                          if (section.room.isNotEmpty) section.room,
                        ].join('  ·  '),
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.85),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (section.instructor.isNotEmpty)
                  Text(
                    // Wraps rather than ellipsising: a section is often taught
                    // by two or three people, and "SUNDAR B, Rajesh Ku…" hides
                    // exactly the thing a student picks a section on.
                    section.instructor
                        .split(',')
                        .map((n) => n.trim())
                        .where((n) => n.isNotEmpty)
                        .join(', '),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: textColor.withValues(alpha: 0.65),
                    ),
                  ),
                // The two reasons a row is unavailable read differently,
                // because they are different: one is a collision, the other is
                // "you already chose".
                if (state.conflict != null)
                  _reason(context, Icons.error_outline, state.conflict!,
                      scheme.error)
                else if (state.typeTaken)
                  _reason(
                      context,
                      Icons.check_circle_outline,
                      'Another ${_typeName(section.type)} section is on your timetable',
                      scheme.onSurface.withValues(alpha: 0.55)),
              ],
            ),
          ),
          if (selectable) ...[
            const SizedBox(width: 8),
            _action(context, state),
          ],
        ],
      ),
    );
  }

  Widget _reason(
      BuildContext context, IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, height: 1.3, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, _SectionState state) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = !state.blocked || state.isSelected;
    final color = state.isSelected ? scheme.error : scheme.primary;

    return SizedBox(
      height: 30,
      child: TextButton(
        onPressed:
            enabled ? () => onToggle(state.section.sectionId, state.isSelected) : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor:
              enabled ? color.withValues(alpha: 0.11) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          state.isSelected ? 'Remove' : 'Add',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: enabled ? color : AppDesign.muted(context),
          ),
        ),
      ),
    );
  }

  Widget _clashFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              clashes.join(' · '),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "M W F · 10 AM" rather than "M 10:00-10:50 AM, W 10:00-10:50 AM, F …".
  ///
  /// The days share an hour far more often than not, so repeating the clock
  /// time per day was the single widest string on the card — wide enough that
  /// it truncated mid-word.
  static String _compactSchedule(List<ScheduleEntry> schedule) {
    if (schedule.isEmpty) return '';
    return schedule.map((entry) {
      final days = entry.days.map((d) => d.name).join(' ');
      final hours = TimeSlotInfo.getHourRangeName(entry.hours);
      return hours.isEmpty ? days : '$days · $hours';
    }).join('  ·  ');
  }

  /// "10 Mar" reads unambiguously; "10/3" is a date-format coin toss.
  static String _month(int m) =>
      (m >= 1 && m <= 12) ? DayConstants.monthNames[m] : '$m';

  static String _typeName(SectionType type) => switch (type) {
        SectionType.L => 'lecture',
        SectionType.P => 'practical',
        SectionType.T => 'tutorial',
      };
}
